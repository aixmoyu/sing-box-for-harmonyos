#!/usr/bin/env python3
"""Fail-closed content binding for formal HarmonyOS releases.

This helper intentionally has no development-server or insecure-TLS mode.  A
formal build can only bind reviewed policy bytes and corresponding source that
are already available from public HTTPS URLs.
"""

from __future__ import annotations

import argparse
import contextlib
import gzip
import hashlib
import http.client
import ipaddress
import json
import os
import pathlib
import re
import shutil
import socket
import ssl
import subprocess
import sys
import tarfile
import tempfile
import time
from collections.abc import Iterable
from typing import NoReturn
from urllib.parse import urljoin, urlsplit


POLICY_MAX_BYTES = 2 * 1024 * 1024
SUPPORT_PAGE_MAX_BYTES = 2 * 1024 * 1024
SOURCE_MAX_BYTES = 1024 * 1024 * 1024
MAX_REDIRECTS = 5
CONNECT_TIMEOUT_SECONDS = 10
READ_TIMEOUT_SECONDS = 30
TOTAL_TIMEOUT_SECONDS = 300
SUPPORT_PAGE_TOTAL_TIMEOUT_SECONDS = 30
POLICY_MIME_TYPES = {
    "application/xhtml+xml",
    "text/html",
    "text/markdown",
    "text/plain",
}
SUPPORT_PAGE_MIME_TYPES = POLICY_MIME_TYPES
SOURCE_MIME_TYPES = {
    "application/gzip",
    "application/octet-stream",
    "application/tar+gzip",
    "application/x-gzip",
    "application/x-compressed-tar",
    "application/x-tar",
}
PLACEHOLDER_RE = re.compile(
    r"HNA_LEGAL_TEMPLATE_DO_NOT_SUBMIT|\[TODO[^]]*\]|"
    r"(?:^|[^A-Za-z0-9])(todo|tbd|placeholder|self-test)(?:[^A-Za-z0-9]|$)",
    re.IGNORECASE | re.MULTILINE,
)


class GateError(RuntimeError):
    pass


def fail(message: str) -> NoReturn:
    raise GateError(message)


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def regular_file(path_text: str, *, label: str) -> pathlib.Path:
    unresolved = pathlib.Path(path_text).expanduser()
    if unresolved.is_symlink() or not unresolved.is_file():
        fail(f"{label} must be a regular file")
    return unresolved.resolve()


def validate_approved_policy(path_text: str, *, label: str) -> dict[str, object]:
    path = regular_file(path_text, label=label)
    size = path.stat().st_size
    if size < 256 or size > POLICY_MAX_BYTES:
        fail(f"{label} must be between 256 bytes and {POLICY_MAX_BYTES} bytes")
    payload = path.read_bytes()
    try:
        text = payload.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise GateError(f"{label} must be UTF-8") from exc
    if "\x00" in text or any(ord(ch) < 32 and ch not in "\t\n\r" for ch in text):
        fail(f"{label} contains binary/control data")
    if PLACEHOLDER_RE.search(text):
        fail(f"{label} is still a template or contains placeholder markers")
    return {
        "sha256": hashlib.sha256(payload).hexdigest(),
        "sizeBytes": size,
    }


def _canonical_https_url(url: str) -> tuple[str, str, int, str]:
    if not isinstance(url, str) or len(url) > 2048:
        fail("URL is missing or too long")
    parsed = urlsplit(url)
    if (
        parsed.scheme.lower() != "https"
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.fragment
    ):
        fail("URL must be public HTTPS without credentials or a fragment")
    try:
        port = parsed.port or 443
    except ValueError as exc:
        raise GateError("URL port is invalid") from exc
    if port != 443:
        fail("URL must use the standard HTTPS port")
    try:
        host = parsed.hostname.rstrip(".").encode("idna").decode("ascii").lower()
    except UnicodeError as exc:
        raise GateError("URL hostname is invalid") from exc
    lower = url.lower()
    if any(token in lower for token in ("todo", "tbd", "placeholder", "[", "]")):
        fail("URL contains a placeholder marker")
    if host in {"localhost", "example.com", "example.org", "example.net"} or host.endswith(
        (".localhost", ".local", ".invalid", ".test", ".example")
    ):
        fail("URL host is not a public release host")
    if not re.fullmatch(
        r"(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+"
        r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?",
        host,
    ):
        try:
            address = ipaddress.ip_address(host)
        except ValueError as exc:
            raise GateError("URL hostname is invalid") from exc
        if not address.is_global:
            fail("URL address is not globally routable")
    target = parsed.path or "/"
    if parsed.query:
        target += "?" + parsed.query
    canonical = parsed._replace(scheme="https", netloc=host, fragment="").geturl()
    return canonical, host, port, target


def _global_addresses(host: str, port: int) -> list[tuple[int, int, int, tuple[object, ...]]]:
    try:
        results = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    except OSError as exc:
        raise GateError("public release host could not be resolved") from exc
    addresses: list[tuple[int, int, int, tuple[object, ...]]] = []
    seen: set[tuple[int, tuple[object, ...]]] = set()
    for family, socktype, proto, _canonname, sockaddr in results:
        address_text = str(sockaddr[0])
        try:
            address = ipaddress.ip_address(address_text)
        except ValueError as exc:
            raise GateError("DNS returned an invalid address") from exc
        if not address.is_global:
            fail("DNS returned a non-global address")
        key = (family, sockaddr)
        if key not in seen:
            seen.add(key)
            addresses.append((family, socktype, proto, sockaddr))
    if not addresses:
        fail("public release host resolved to no usable address")
    return addresses


def _connect_pinned(
    addresses: list[tuple[int, int, int, tuple[object, ...]]],
    timeout: float,
    source_address: tuple[str, int] | None = None,
) -> socket.socket:
    last_error: OSError | None = None
    for family, socktype, proto, sockaddr in addresses:
        candidate = socket.socket(family, socktype, proto)
        try:
            candidate.settimeout(timeout)
            if source_address:
                candidate.bind(source_address)
            candidate.connect(sockaddr)
            return candidate
        except OSError as exc:
            last_error = exc
            candidate.close()
    raise OSError("none of the DNS-validated public addresses accepted HTTPS") from last_error


def _request(url: str) -> tuple[http.client.HTTPSConnection, http.client.HTTPResponse, str]:
    canonical, host, port, target = _canonical_https_url(url)
    addresses = _global_addresses(host, port)
    connection = http.client.HTTPSConnection(
        host,
        port,
        timeout=CONNECT_TIMEOUT_SECONDS,
        context=ssl.create_default_context(),
    )

    def pinned_create_connection(
        _address: tuple[str, int],
        timeout: float = CONNECT_TIMEOUT_SECONDS,
        source_address: tuple[str, int] | None = None,
    ) -> socket.socket:
        return _connect_pinned(addresses, timeout, source_address)

    connection._create_connection = pinned_create_connection  # type: ignore[attr-defined]
    try:
        connection.request(
            "GET",
            target,
            headers={
                "Accept": "text/html,text/plain,text/markdown,application/xhtml+xml,application/gzip,application/octet-stream",
                "Accept-Encoding": "identity",
                "User-Agent": "HarmonyOS-Network-Assistant-Release-Gate/1",
            },
        )
        response = connection.getresponse()
        if connection.sock is not None:
            connection.sock.settimeout(READ_TIMEOUT_SECONDS)
        return connection, response, canonical
    except Exception:
        connection.close()
        raise


def fetch_url(
    url: str,
    destination: pathlib.Path,
    *,
    max_bytes: int,
    allowed_mime_types: set[str],
    accept_any_2xx: bool = False,
    total_timeout_seconds: int = TOTAL_TIMEOUT_SECONDS,
) -> dict[str, object]:
    current, _host, _port, _target = _canonical_https_url(url)
    redirects = 0
    started = time.monotonic()
    temp_path = destination.with_name(destination.name + ".part")
    with contextlib.suppress(FileNotFoundError):
        temp_path.unlink()
    try:
        while True:
            if time.monotonic() - started > total_timeout_seconds:
                fail("HTTPS content fetch exceeded the total timeout")
            connection, response, canonical = _request(current)
            try:
                if response.status in {301, 302, 303, 307, 308}:
                    location = response.getheader("Location")
                    if not location or redirects >= MAX_REDIRECTS:
                        fail("HTTPS redirect chain is missing a location or is too long")
                    next_url = urljoin(canonical, location)
                    current, _host, _port, _target = _canonical_https_url(next_url)
                    redirects += 1
                    continue
                if accept_any_2xx:
                    if response.status < 200 or response.status >= 300:
                        fail("public HTTPS content did not return a 2xx status")
                elif response.status != 200:
                    fail("public HTTPS content did not return status 200")
                content_encoding = (response.getheader("Content-Encoding") or "identity").strip().lower()
                if content_encoding not in {"", "identity"}:
                    fail("public HTTPS content must not use transport content encoding")
                content_type = (response.getheader("Content-Type") or "").split(";", 1)[0].strip().lower()
                if content_type not in allowed_mime_types:
                    fail("public HTTPS content has an unapproved MIME type")
                length_text = response.getheader("Content-Length")
                if length_text:
                    try:
                        content_length = int(length_text)
                    except ValueError as exc:
                        raise GateError("public HTTPS content length is invalid") from exc
                    if content_length < 1 or content_length > max_bytes:
                        fail("public HTTPS content length is outside the approved limit")
                digest = hashlib.sha256()
                size = 0
                destination.parent.mkdir(parents=True, exist_ok=True)
                with temp_path.open("wb") as output:
                    while True:
                        if time.monotonic() - started > total_timeout_seconds:
                            fail("HTTPS content fetch exceeded the total timeout")
                        chunk = response.read(1024 * 1024)
                        if not chunk:
                            break
                        size += len(chunk)
                        if size > max_bytes:
                            fail("public HTTPS content exceeds the approved size limit")
                        digest.update(chunk)
                        output.write(chunk)
                    output.flush()
                    os.fsync(output.fileno())
                if size < 1 or (length_text and size != int(length_text)):
                    fail("public HTTPS response body is empty or truncated")
                os.replace(temp_path, destination)
                return {
                    "url": url,
                    "resolvedUrl": canonical,
                    "redirectCount": redirects,
                    "status": response.status,
                    "contentType": content_type,
                    "sha256": digest.hexdigest(),
                    "sizeBytes": size,
                }
            finally:
                response.close()
                connection.close()
    finally:
        with contextlib.suppress(FileNotFoundError):
            temp_path.unlink()


def probe_url(url: str) -> dict[str, object]:
    """Verify that a bounded public support page is reachable without binding its body.

    The request path is identical to policy/source verification: every DNS
    answer must be globally routable, the selected address is pinned for the
    connection, and ``HTTPSConnection`` performs normal certificate and
    hostname verification. Every redirect is independently revalidated as
    public HTTPS before it can be followed.
    """
    with tempfile.TemporaryDirectory(prefix="hna-release-probe.") as directory:
        downloaded = pathlib.Path(directory) / "support-page"
        return fetch_url(
            url,
            downloaded,
            max_bytes=SUPPORT_PAGE_MAX_BYTES,
            allowed_mime_types=SUPPORT_PAGE_MIME_TYPES,
            accept_any_2xx=True,
            total_timeout_seconds=SUPPORT_PAGE_TOTAL_TIMEOUT_SECONDS,
        )


def verify_url_against_file(
    url: str,
    expected_path: pathlib.Path,
    *,
    kind: str,
) -> dict[str, object]:
    max_bytes = POLICY_MAX_BYTES if kind == "policy" else SOURCE_MAX_BYTES
    mime_types = POLICY_MIME_TYPES if kind == "policy" else SOURCE_MIME_TYPES
    expected_size = expected_path.stat().st_size
    if expected_size < 1 or expected_size > max_bytes:
        fail("approved local content size is outside the release limit")
    with tempfile.TemporaryDirectory(prefix="hna-release-content.") as directory:
        downloaded = pathlib.Path(directory) / "body"
        metadata = fetch_url(
            url,
            downloaded,
            max_bytes=max_bytes,
            allowed_mime_types=mime_types,
        )
        if metadata["sizeBytes"] != expected_size or metadata["sha256"] != sha256_file(expected_path):
            fail("published HTTPS body differs from the reviewed local bytes")
    return metadata


def verify_policy_set(args: argparse.Namespace) -> dict[str, object]:
    declarations = [
        ("privacy", "zh-CN", args.privacy_zh_file, args.privacy_zh_url),
        ("privacy", "en", args.privacy_en_file, args.privacy_en_url),
        ("userAgreement", "zh-CN", args.agreement_zh_file, args.agreement_zh_url),
        ("userAgreement", "en", args.agreement_en_file, args.agreement_en_url),
    ]
    canonical_urls = {_canonical_https_url(url)[0] for _kind, _language, _file, url in declarations}
    if len(canonical_urls) != len(declarations):
        fail("every localized policy document must have its own public HTTPS URL")
    documents: list[dict[str, object]] = []
    approved_hashes: set[str] = set()
    for kind, language, file_text, url in declarations:
        label = f"approved {kind} {language}"
        approved = validate_approved_policy(file_text, label=label)
        path = regular_file(file_text, label=label)
        published = verify_url_against_file(url, path, kind="policy")
        if published["sha256"] != approved["sha256"] or published["sizeBytes"] != approved["sizeBytes"]:
            fail(f"{label} binding changed during verification")
        if str(approved["sha256"]) in approved_hashes:
            fail("localized policy documents must not reuse identical approved bodies")
        approved_hashes.add(str(approved["sha256"]))
        documents.append(
            {
                "kind": kind,
                "language": language,
                "url": url,
                "resolvedUrl": published["resolvedUrl"],
                "redirectCount": published["redirectCount"],
                "sha256": approved["sha256"],
                "sizeBytes": approved["sizeBytes"],
                "contentType": published["contentType"],
            }
        )
    return {"schemaVersion": 1, "documents": documents}


def _safe_archive_members(archive: tarfile.TarFile, prefix: str) -> set[str]:
    names: set[str] = set()
    for member in archive:
        pure = pathlib.PurePosixPath(member.name)
        if pure.is_absolute() or ".." in pure.parts or "\\" in member.name:
            fail("source archive contains an unsafe path")
        if member.name in names:
            fail("source archive contains a duplicate path")
        names.add(member.name)
        if not member.name.startswith(prefix + "/") and member.name not in {prefix, prefix + "/"}:
            fail("source archive contains a path outside its release prefix")
        if member.ischr() or member.isblk() or member.isfifo() or member.isdev():
            fail("source archive contains a special file")
        if member.issym() or member.islnk():
            target = pathlib.PurePosixPath(member.linkname)
            if target.is_absolute() or ".." in target.parts:
                fail("source archive contains an unsafe link")
    return names


def _require_source_completeness(names: set[str], prefix: str) -> None:
    relative = {name[len(prefix) + 1 :] for name in names if name.startswith(prefix + "/")}
    required = {
        "LICENSE",
        "THIRD_PARTY_NOTICES.md",
        "AppScope/app.json5",
        "build-profile.example.json5",
        "hvigorfile.ts",
        "oh-package.json5",
        "entry/build-profile.json5",
        "entry/hvigorfile.ts",
        "core/go/go.mod",
        "core/go/go.sum",
        "core/go/main.go",
        "scripts/build_core.sh",
        "scripts/build_ohos_go.sh",
        "scripts/core_smoke_test.sh",
        "scripts/core_vendor.py",
        "scripts/prepare_core_upgrade.sh",
        "scripts/release_content_gate.py",
        "scripts/verify_build_toolchain.py",
        "scripts/verify_core_vendor.sh",
        "third_party/core-lock.json",
        "third_party/build-toolchain-lock.json",
        "third_party/CORE_UPGRADE.md",
        "third_party/sing-box/LICENSE",
        "third_party/sing-box/go.mod",
        "third_party/gvisor/LICENSE",
        "third_party/gvisor/go.mod",
        "third_party/ohos-golang-go-1.24/LICENSE",
        "third_party/ohos-golang-go-1.24/src/make.bash",
    }
    missing = sorted(required - relative)
    if missing:
        fail("source archive is missing required source/build/license inputs: " + ", ".join(missing))
    for tree in (
        "core/go/",
        "entry/src/main/",
        "third_party/sing-box/",
        "third_party/gvisor/",
        "third_party/ohos-golang-go-1.24/",
    ):
        if sum(name.startswith(tree) for name in relative) < 2:
            fail(f"source archive does not contain the complete {tree} tree")
    if not any(name.startswith("third_party/patches/") and name.endswith(".patch") for name in relative):
        fail("source archive contains no reviewed toolchain patch")
    forbidden = {
        "build-profile.json5",
        "build-profile.local.json5",
    }
    if relative & forbidden or any(
        part in {".signing", "signing-private"}
        for name in relative
        for part in pathlib.PurePosixPath(name).parts
    ):
        fail("source archive contains local signing material")


def create_source_archive(
    repo: pathlib.Path,
    commit: str,
    version: str,
    output: pathlib.Path,
) -> dict[str, object]:
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        fail("source commit must be a full lowercase Git SHA-1")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?", version):
        fail("source archive version is invalid")
    resolved = subprocess.run(
        ["git", "-C", str(repo), "rev-parse", f"{commit}^{{commit}}"],
        check=False,
        capture_output=True,
        text=True,
    )
    if resolved.returncode != 0 or resolved.stdout.strip() != commit:
        fail("source commit is unavailable in this Git repository")
    prefix = f"HarmonyOS-Network-Assistant-{version}-{commit}"
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="hna-source-archive.") as directory:
        raw_tar = pathlib.Path(directory) / "source.tar"
        with raw_tar.open("wb") as target:
            archived = subprocess.run(
                [
                    "git",
                    "-C",
                    str(repo),
                    "archive",
                    "--format=tar",
                    f"--prefix={prefix}/",
                    commit,
                ],
                check=False,
                stdout=target,
                stderr=subprocess.PIPE,
            )
        if archived.returncode != 0:
            fail("Git could not create the corresponding source archive")
        with tarfile.open(raw_tar, "r:") as archive:
            names = _safe_archive_members(archive, prefix)
        _require_source_completeness(names, prefix)
        temporary_output = output.with_name(output.name + ".part")
        with contextlib.suppress(FileNotFoundError):
            temporary_output.unlink()
        try:
            with raw_tar.open("rb") as source, temporary_output.open("wb") as raw_output:
                with gzip.GzipFile(
                    filename="",
                    mode="wb",
                    compresslevel=9,
                    fileobj=raw_output,
                    mtime=0,
                ) as compressed:
                    shutil.copyfileobj(source, compressed, length=1024 * 1024)
                raw_output.flush()
                os.fsync(raw_output.fileno())
            os.replace(temporary_output, output)
        finally:
            with contextlib.suppress(FileNotFoundError):
                temporary_output.unlink()
    size = output.stat().st_size
    if size < 1 or size > SOURCE_MAX_BYTES:
        fail("corresponding source archive size is outside the release limit")
    return {
        "file": output.name,
        "gitCommit": commit,
        "sha256": sha256_file(output),
        "sizeBytes": size,
        "format": "tar+gzip",
        "prefix": prefix + "/",
    }


def dump_json(value: dict[str, object]) -> None:
    print(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")))


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    subcommands = root.add_subparsers(dest="command", required=True)

    policy_file = subcommands.add_parser("policy-file")
    policy_file.add_argument("--approved-file", required=True)
    policy_file.add_argument("--label", default="approved policy")

    policies = subcommands.add_parser("verify-policies")
    policies.add_argument("--privacy-zh-file", required=True)
    policies.add_argument("--privacy-zh-url", required=True)
    policies.add_argument("--privacy-en-file", required=True)
    policies.add_argument("--privacy-en-url", required=True)
    policies.add_argument("--agreement-zh-file", required=True)
    policies.add_argument("--agreement-zh-url", required=True)
    policies.add_argument("--agreement-en-file", required=True)
    policies.add_argument("--agreement-en-url", required=True)

    verify_url = subcommands.add_parser("verify-url")
    verify_url.add_argument("--url", required=True)
    verify_url.add_argument("--expected-file", required=True)
    verify_url.add_argument("--kind", required=True, choices=("policy", "source"))

    probe = subcommands.add_parser("probe-url")
    probe.add_argument("--url", required=True)

    source = subcommands.add_parser("create-source")
    source.add_argument("--repo", required=True)
    source.add_argument("--commit", required=True)
    source.add_argument("--version", required=True)
    source.add_argument("--output", required=True)
    return root


def main(argv: Iterable[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        if args.command == "policy-file":
            dump_json(validate_approved_policy(args.approved_file, label=args.label))
        elif args.command == "verify-policies":
            dump_json(verify_policy_set(args))
        elif args.command == "verify-url":
            expected = regular_file(args.expected_file, label="expected release content")
            dump_json(verify_url_against_file(args.url, expected, kind=args.kind))
        elif args.command == "probe-url":
            dump_json(probe_url(args.url))
        elif args.command == "create-source":
            dump_json(
                create_source_archive(
                    pathlib.Path(args.repo).resolve(),
                    args.commit,
                    args.version,
                    pathlib.Path(args.output).resolve(),
                )
            )
        else:  # pragma: no cover - argparse owns this branch.
            fail("unsupported command")
    except (GateError, OSError, ssl.SSLError, http.client.HTTPException) as exc:
        print(f"RELEASE_CONTENT_BLOCKED: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
