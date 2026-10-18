#!/usr/bin/env python3
"""Fail closed unless external native/release build tools match the reviewed lock."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import re
import stat
import sys
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_LOCK = PROJECT_ROOT / "third_party" / "build-toolchain-lock.json"
SHA256 = re.compile(r"^[0-9a-f]{64}$")
TREE_FORMAT = b"HNA-BUILD-TOOLCHAIN-TREE-SHA256-v1\0"


class ToolchainError(RuntimeError):
    pass


def fail(message: str) -> None:
    raise ToolchainError(message)


def load_lock(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read build toolchain lock: {error}")
    if value.get("schema_version") != 1:
        fail("unsupported build toolchain lock schema")
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        fail(f"cannot hash required build input {path.name}: {error}")
    return digest.hexdigest()


def verify_files(root: Path, files: Any, label: str) -> None:
    if not isinstance(files, dict) or not files:
        fail(f"{label}.files must be a non-empty object")
    for relative, expected in files.items():
        if not isinstance(relative, str) or Path(relative).is_absolute() or ".." in Path(relative).parts:
            fail(f"{label} contains an unsafe file path")
        if not isinstance(expected, str) or not SHA256.fullmatch(expected):
            fail(f"{label} contains an invalid SHA-256")
        actual = sha256_file(root / relative)
        if actual != expected:
            fail(f"{label} file drift: {relative}")


def tree_sha256(root: Path) -> str:
    if not root.is_dir() or root.is_symlink():
        fail(f"required build-tool directory is missing: {root.name}")
    paths: list[Path] = []
    try:
        for path in root.rglob("*"):
            if path.is_symlink() or path.is_file():
                paths.append(path)
            elif not path.is_dir():
                fail(f"build-tool directory contains a special file: {path.name}")
    except OSError as error:
        fail(f"cannot enumerate build-tool directory {root.name}: {error}")
    paths.sort(key=lambda item: item.relative_to(root).as_posix())

    digest = hashlib.sha256(TREE_FORMAT)
    for path in paths:
        relative = path.relative_to(root).as_posix().encode("utf-8")
        try:
            mode = path.lstat().st_mode
            executable = b"x" if mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH) else b"-"
            if path.is_symlink():
                kind = b"l"
                content = os.readlink(path).encode("utf-8", "surrogateescape")
            else:
                kind = b"f"
                content = bytes.fromhex(sha256_file(path))
        except OSError as error:
            fail(f"cannot inspect build-tool input {path.name}: {error}")
        digest.update(kind + b"\0" + executable + b"\0" + relative + b"\0" + content + b"\n")
    return digest.hexdigest()


def verify_trees(root: Path, trees: Any, label: str) -> None:
    if not isinstance(trees, dict) or not trees:
        fail(f"{label}.trees must be a non-empty object")
    for relative, expected in trees.items():
        if not isinstance(relative, str) or Path(relative).is_absolute() or ".." in Path(relative).parts:
            fail(f"{label} contains an unsafe directory path")
        if not isinstance(expected, str) or not SHA256.fullmatch(expected):
            fail(f"{label} contains an invalid directory SHA-256")
        actual = tree_sha256(root / relative)
        if actual != expected:
            fail(f"{label} directory drift: {relative}")


def verify_bootstrap(lock: dict[str, Any], root: Path) -> None:
    host = lock.get("host", {})
    if platform.system() != host.get("system") or platform.machine() != host.get("machine"):
        fail("host OS/architecture differs from the reviewed build host")
    bootstrap = lock.get("bootstrap_go", {})
    version_file = root / "VERSION"
    try:
        version = version_file.read_text(encoding="utf-8").splitlines()[0].strip()
    except (OSError, UnicodeError, IndexError) as error:
        fail(f"cannot read bootstrap Go VERSION: {error}")
    if version != bootstrap.get("version"):
        fail("bootstrap Go version differs from the reviewed lock")
    archive_url = bootstrap.get("official_archive_url")
    archive_sha = bootstrap.get("official_archive_sha256")
    if not isinstance(archive_url, str) or not archive_url.startswith("https://go.dev/dl/"):
        fail("bootstrap Go official archive URL is invalid")
    if not isinstance(archive_sha, str) or not SHA256.fullmatch(archive_sha):
        fail("bootstrap Go official archive SHA-256 is invalid")
    verify_files(root, bootstrap.get("files"), "bootstrap_go")


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read SDK metadata {path.name}: {error}")
    if not isinstance(value, dict):
        fail(f"SDK metadata {path.name} is not an object")
    return value


def verify_deveco(lock: dict[str, Any], contents: Path) -> None:
    deveco = lock.get("deveco", {})
    sdk_metadata = read_json(contents / "sdk/default/sdk-pkg.json").get("data", {})
    if str(sdk_metadata.get("apiVersion")) != str(deveco.get("sdk_api_version")):
        fail("HarmonyOS SDK API version differs from the reviewed lock")
    if sdk_metadata.get("version") != deveco.get("sdk_version"):
        fail("HarmonyOS SDK version differs from the reviewed lock")
    if sdk_metadata.get("releaseType") != deveco.get("sdk_release_type"):
        fail("HarmonyOS SDK release type differs from the reviewed lock")
    for relative in (
        "sdk/default/openharmony/native/oh-uni-package.json",
        "sdk/default/openharmony/toolchains/oh-uni-package.json",
    ):
        metadata = read_json(contents / relative)
        if str(metadata.get("apiVersion")) != str(deveco.get("sdk_api_version")):
            fail(f"{relative} API version differs from the reviewed lock")
        if metadata.get("version") != deveco.get("sdk_version"):
            fail(f"{relative} version differs from the reviewed lock")
        if metadata.get("releaseType") != deveco.get("sdk_release_type"):
            fail(f"{relative} release type differs from the reviewed lock")
    verify_files(contents, deveco.get("files"), "deveco")
    verify_trees(contents, deveco.get("trees"), "deveco")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lock", type=Path, default=DEFAULT_LOCK)
    subparsers = parser.add_subparsers(dest="command", required=True)
    bootstrap_parser = subparsers.add_parser("bootstrap")
    bootstrap_parser.add_argument("--goroot", type=Path, required=True)
    deveco_parser = subparsers.add_parser("deveco")
    deveco_parser.add_argument("--contents", type=Path, required=True)
    all_parser = subparsers.add_parser("all")
    all_parser.add_argument("--goroot", type=Path, required=True)
    all_parser.add_argument("--contents", type=Path, required=True)
    args = parser.parse_args()
    lock = load_lock(args.lock.resolve())
    if args.command in ("bootstrap", "all"):
        verify_bootstrap(lock, args.goroot.resolve())
        print("BOOTSTRAP GO TOOLCHAIN VERIFIED")
    if args.command in ("deveco", "all"):
        verify_deveco(lock, args.contents.resolve())
        print("DEVECO BUILD TOOLCHAIN VERIFIED")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ToolchainError as error:
        print(f"BLOCKED: {error}", file=sys.stderr)
        raise SystemExit(1)
