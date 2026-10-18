#!/usr/bin/env python3
"""Verify a detached, Ed25519-signed release approval against exact inputs.

This gate never creates approvals or keys.  A release operator supplies the
canonical release-approval.json, its detached signature envelope, and an
explicitly trusted public-key file.  Every signed artifact and evidence digest
is recomputed locally so an approval cannot be replayed for another market,
package, source commit, policy set, or security review.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import datetime as dt
import hashlib
import json
import pathlib
import re
import subprocess
import sys
import tempfile
from typing import Any


DOMAIN = b"HNA-RELEASE-APPROVAL-V1\0"
MAX_FUTURE_SKEW = dt.timedelta(minutes=5)
SHA256 = re.compile(r"^[0-9a-f]{64}$")
GIT_COMMIT = re.compile(r"^[0-9a-f]{40}$")
BUNDLE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$")
TIMESTAMP = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
KIND = re.compile(r"^[a-z][a-z0-9-]{2,63}$")
PLACEHOLDER = re.compile(
    r"(?:^|[\s:/_.-])(x+|todo|tbd|placeholder|example|sample|fixture|self[- ]?test|test[- ]?only|unknown|n/?a)(?:$|[\s:/_.-])",
    re.IGNORECASE,
)
ARTIFACT_ARGUMENTS = {
    "app": "app",
    "releaseManifest": "release_manifest",
    "privacyPolicyZh": "privacy_policy_zh",
    "privacyPolicyEn": "privacy_policy_en",
    "userAgreementZh": "user_agreement_zh",
    "userAgreementEn": "user_agreement_en",
    "correspondingSource": "corresponding_source",
    "sbom": "sbom",
    "securityReport": "security_report",
}
MARKET_EVIDENCE = {
    "cn": {
        "huawei-vpn-category-review",
        "cn-app-filing",
        "cn-app-copyright",
        "cn-telecom-vpn-legal-review",
    },
    "overseas": {
        "huawei-vpn-category-review",
        "huawei-overseas-phone-eligibility",
        "encryption-export-control-review",
    },
}


class ApprovalError(ValueError):
    pass


def object_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ApprovalError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def canonical_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def load_canonical_json(path: pathlib.Path, label: str) -> tuple[dict[str, Any], bytes]:
    try:
        raw = path.read_bytes()
        if len(raw) > 1024 * 1024:
            raise ApprovalError(f"{label} exceeds size limit")
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=object_pairs)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ApprovalError(f"invalid {label} JSON") from error
    if not isinstance(value, dict):
        raise ApprovalError(f"{label} root must be an object")
    if raw != canonical_bytes(value):
        raise ApprovalError(f"{label} must use canonical JSON encoding")
    return value, raw


def require_keys(value: dict[str, Any], required: set[str], label: str) -> None:
    if set(value) != required:
        raise ApprovalError(f"{label} fields mismatch")


def require_text(value: Any, label: str, minimum: int = 1, maximum: int = 500) -> str:
    if not isinstance(value, str) or value != value.strip() or not (minimum <= len(value) <= maximum):
        raise ApprovalError(f"invalid {label}")
    if PLACEHOLDER.search(value):
        raise ApprovalError(f"placeholder {label} is forbidden")
    return value


def require_sha(value: Any, label: str) -> str:
    if not isinstance(value, str) or not SHA256.fullmatch(value):
        raise ApprovalError(f"invalid {label}")
    return value


def timestamp(value: Any, label: str) -> dt.datetime:
    if not isinstance(value, str) or not TIMESTAMP.fullmatch(value):
        raise ApprovalError(f"invalid {label}")
    try:
        return dt.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)
    except ValueError as error:
        raise ApprovalError(f"invalid {label}") from error


def digest(path: pathlib.Path) -> tuple[str, int]:
    if not path.is_file():
        raise ApprovalError(f"bound input is missing: {path.name}")
    size = path.stat().st_size
    if size <= 0:
        raise ApprovalError(f"bound input is empty: {path.name}")
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest(), size


def decode_base64(value: Any, size: int, label: str) -> bytes:
    if not isinstance(value, str):
        raise ApprovalError(f"invalid {label}")
    try:
        decoded = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError) as error:
        raise ApprovalError(f"invalid {label}") from error
    if len(decoded) != size:
        raise ApprovalError(f"invalid {label} length")
    return decoded


def verify_ed25519(public_key: bytes, signature: bytes, message: bytes) -> None:
    public_key_der = bytes.fromhex("302a300506032b6570032100") + public_key
    with tempfile.TemporaryDirectory(prefix="hna-release-approval-signature.") as temp:
        directory = pathlib.Path(temp)
        key_path = directory / "public-key.der"
        message_path = directory / "message.bin"
        signature_path = directory / "signature.bin"
        key_path.write_bytes(public_key_der)
        message_path.write_bytes(message)
        signature_path.write_bytes(signature)
        try:
            verified = subprocess.run([
                "openssl", "pkeyutl", "-verify", "-pubin", "-keyform", "DER",
                "-inkey", str(key_path), "-rawin", "-in", str(message_path),
                "-sigfile", str(signature_path),
            ], text=True, capture_output=True, check=False)
        except OSError as error:
            raise ApprovalError("OpenSSL is required for Ed25519 verification") from error
    if verified.returncode != 0:
        raise ApprovalError("detached Ed25519 signature is invalid")


def parse_evidence_arguments(values: list[str]) -> dict[str, pathlib.Path]:
    result: dict[str, pathlib.Path] = {}
    for raw in values:
        kind, separator, path = raw.partition("=")
        if not separator or not KIND.fullmatch(kind) or not path or kind in result:
            raise ApprovalError("--evidence must be unique KIND=PATH values")
        result[kind] = pathlib.Path(path)
    return result


def verify(args: argparse.Namespace) -> dict[str, Any]:
    approval, approval_bytes = load_canonical_json(args.approval, "release approval")
    signature_envelope, _ = load_canonical_json(args.signature, "signature envelope")
    trusted_key, _ = load_canonical_json(args.trusted_key, "trusted public key")

    require_keys(trusted_key, {
        "schemaVersion", "keyId", "issuer", "algorithm", "publicKeyBase64",
        "notBefore", "expiresAt", "markets",
    }, "trusted public key")
    if type(trusted_key["schemaVersion"]) is not int or trusted_key["schemaVersion"] != 1 or trusted_key["algorithm"] != "Ed25519":
        raise ApprovalError("unsupported trusted public key")
    key_id = require_text(trusted_key["keyId"], "trusted key ID", 8, 128)
    key_issuer = require_text(trusted_key["issuer"], "trusted key issuer", 3, 200)
    markets = trusted_key["markets"]
    if not isinstance(markets, list) or not markets or len(markets) != len(set(markets)) or any(item not in MARKET_EVIDENCE for item in markets):
        raise ApprovalError("invalid trusted key markets")
    public_key = decode_base64(trusted_key["publicKeyBase64"], 32, "trusted Ed25519 public key")
    key_fingerprint = hashlib.sha256(public_key).hexdigest()
    key_not_before = timestamp(trusted_key["notBefore"], "trusted key notBefore")
    key_expires = timestamp(trusted_key["expiresAt"], "trusted key expiresAt")

    require_keys(signature_envelope, {
        "schemaVersion", "algorithm", "keyId", "approvalSha256", "signatureBase64",
    }, "signature envelope")
    if type(signature_envelope["schemaVersion"]) is not int or signature_envelope["schemaVersion"] != 1 or signature_envelope["algorithm"] != "Ed25519":
        raise ApprovalError("unsupported signature envelope")
    if signature_envelope["keyId"] != key_id:
        raise ApprovalError("signature key is not the explicitly trusted key")
    if require_sha(signature_envelope["approvalSha256"], "signed approval digest") != hashlib.sha256(approval_bytes).hexdigest():
        raise ApprovalError("signature envelope approval digest mismatch")
    signature = decode_base64(signature_envelope["signatureBase64"], 64, "Ed25519 signature")
    verify_ed25519(public_key, signature, DOMAIN + approval_bytes)

    require_keys(approval, {
        "schemaVersion", "approvalId", "market", "application", "source",
        "artifacts", "evidence", "validity", "signer",
    }, "release approval")
    if type(approval["schemaVersion"]) is not int or approval["schemaVersion"] != 1:
        raise ApprovalError("unsupported release approval schema")
    approval_id = require_text(approval["approvalId"], "approval ID", 12, 128)
    market = approval["market"]
    if market != args.market or market not in markets:
        raise ApprovalError("approval market mismatch")

    application = approval["application"]
    if not isinstance(application, dict):
        raise ApprovalError("invalid approved application")
    require_keys(application, {"bundleName", "versionCode", "versionName"}, "approved application")
    if (application["bundleName"] != args.bundle or not BUNDLE.fullmatch(args.bundle) or
            type(application["versionCode"]) is not int or application["versionCode"] != args.version_code or args.version_code <= 0 or
            application["versionName"] != args.version_name):
        raise ApprovalError("approved bundle or version mismatch")
    require_text(application["versionName"], "version name", 1, 64)

    source = approval["source"]
    if not isinstance(source, dict):
        raise ApprovalError("invalid approved source")
    require_keys(source, {"gitCommit"}, "approved source")
    if source["gitCommit"] != args.git_commit or not GIT_COMMIT.fullmatch(args.git_commit):
        raise ApprovalError("approved Git commit mismatch")

    signer = approval["signer"]
    if not isinstance(signer, dict):
        raise ApprovalError("invalid approval signer")
    require_keys(signer, {"keyId", "issuer", "keyFingerprintSha256"}, "approval signer")
    if (signer["keyId"] != key_id or signer["issuer"] != key_issuer or
            require_sha(signer["keyFingerprintSha256"], "signer key fingerprint") != key_fingerprint):
        raise ApprovalError("approval signer is not the explicitly trusted key")

    validity = approval["validity"]
    if not isinstance(validity, dict):
        raise ApprovalError("invalid approval validity")
    require_keys(validity, {"issuedAt", "notBefore", "expiresAt"}, "approval validity")
    issued_at = timestamp(validity["issuedAt"], "approval issuedAt")
    not_before = timestamp(validity["notBefore"], "approval notBefore")
    expires_at = timestamp(validity["expiresAt"], "approval expiresAt")
    now = dt.datetime.now(dt.timezone.utc)
    if not (key_not_before <= not_before <= issued_at <= expires_at <= key_expires):
        raise ApprovalError("approval validity is outside trusted key validity")
    if not (not_before <= now < expires_at) or not (key_not_before <= now < key_expires):
        raise ApprovalError("approval or trusted key is not currently valid")
    if issued_at > now + MAX_FUTURE_SKEW:
        raise ApprovalError("approval issuedAt is unacceptably far in the future")

    artifacts = approval["artifacts"]
    if not isinstance(artifacts, dict):
        raise ApprovalError("invalid approved artifacts")
    require_keys(artifacts, set(ARTIFACT_ARGUMENTS), "approved artifacts")
    for artifact_name, argument_name in ARTIFACT_ARGUMENTS.items():
        item = artifacts[artifact_name]
        if not isinstance(item, dict):
            raise ApprovalError(f"invalid approved artifact: {artifact_name}")
        require_keys(item, {"sha256", "sizeBytes"}, f"approved artifact {artifact_name}")
        actual_hash, actual_size = digest(getattr(args, argument_name))
        if (require_sha(item["sha256"], f"{artifact_name} digest") != actual_hash or
                type(item["sizeBytes"]) is not int or item["sizeBytes"] != actual_size):
            raise ApprovalError(f"approved artifact mismatch: {artifact_name}")

    try:
        release_manifest = json.loads(args.release_manifest.read_text(encoding="utf-8"), object_pairs_hook=object_pairs)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ApprovalError("release manifest is invalid") from error
    if not isinstance(release_manifest, dict):
        raise ApprovalError("release manifest root must be an object")
    manifest_application = release_manifest.get("application", {})
    manifest_source = release_manifest.get("source", {})
    manifest_pack = release_manifest.get("appPack", {})
    if not all(isinstance(value, dict) for value in (manifest_application, manifest_source, manifest_pack)):
        raise ApprovalError("release manifest identity sections are invalid")
    if (manifest_application.get("bundleName") != args.bundle or
            manifest_application.get("versionCode") != args.version_code or
            manifest_application.get("versionName") != args.version_name or
            manifest_source.get("gitCommit") != args.git_commit or
            manifest_pack.get("sha256") != artifacts["app"]["sha256"]):
        raise ApprovalError("release manifest does not bind the expected release identity")

    evidence_paths = parse_evidence_arguments(args.evidence)
    required_evidence = MARKET_EVIDENCE[market]
    if set(evidence_paths) != required_evidence:
        raise ApprovalError("evidence set does not exactly match the selected market")
    evidence = approval["evidence"]
    if not isinstance(evidence, list) or len(evidence) != len(required_evidence):
        raise ApprovalError("approved evidence set is incomplete")
    seen: set[str] = set()
    for item in evidence:
        if not isinstance(item, dict):
            raise ApprovalError("invalid approved evidence")
        require_keys(item, {"kind", "issuer", "reference", "sha256", "effectiveAt", "expiresAt"}, "approved evidence")
        kind = item["kind"]
        if not isinstance(kind, str) or not KIND.fullmatch(kind) or kind not in required_evidence or kind in seen:
            raise ApprovalError("unexpected or duplicate approved evidence kind")
        seen.add(kind)
        require_text(item["issuer"], f"{kind} issuer", 3, 200)
        require_text(item["reference"], f"{kind} reference", 8, 500)
        actual_hash, _ = digest(evidence_paths[kind])
        if require_sha(item["sha256"], f"{kind} evidence digest") != actual_hash:
            raise ApprovalError(f"approved evidence mismatch: {kind}")
        effective_at = timestamp(item["effectiveAt"], f"{kind} effectiveAt")
        evidence_expires = timestamp(item["expiresAt"], f"{kind} expiresAt")
        if not (effective_at <= issued_at < evidence_expires) or expires_at > evidence_expires or not (effective_at <= now < evidence_expires):
            raise ApprovalError(f"approved evidence is expired or not effective: {kind}")

    return {
        "verified": True,
        "schemaVersion": 1,
        "approvalId": approval_id,
        "market": market,
        "bundleName": args.bundle,
        "versionCode": args.version_code,
        "versionName": args.version_name,
        "gitCommit": args.git_commit,
        "appSha256": artifacts["app"]["sha256"],
        "releaseManifestSha256": artifacts["releaseManifest"]["sha256"],
        "keyId": key_id,
        "keyFingerprintSha256": key_fingerprint,
        "expiresAt": validity["expiresAt"],
        "evidenceKinds": sorted(seen),
    }


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(
        description=__doc__,
        epilog=(
            "CN evidence kinds: huawei-vpn-category-review, cn-app-filing, "
            "cn-app-copyright, cn-telecom-vpn-legal-review. Overseas evidence "
            "kinds: huawei-vpn-category-review, huawei-overseas-phone-eligibility, "
            "encryption-export-control-review. Repeat --evidence KIND=PATH once "
            "for every required kind. The trusted-key path is the trust decision; "
            "never point it at an unreviewed key delivered with an approval."
        ),
    )
    value.add_argument("--approval", required=True, type=pathlib.Path)
    value.add_argument("--signature", required=True, type=pathlib.Path)
    value.add_argument("--trusted-key", required=True, type=pathlib.Path)
    value.add_argument("--market", required=True, choices=sorted(MARKET_EVIDENCE))
    value.add_argument("--bundle", required=True)
    value.add_argument("--version-code", required=True, type=int)
    value.add_argument("--version-name", required=True)
    value.add_argument("--git-commit", required=True)
    value.add_argument("--app", required=True, type=pathlib.Path)
    value.add_argument("--release-manifest", required=True, type=pathlib.Path)
    value.add_argument("--privacy-policy-zh", required=True, type=pathlib.Path)
    value.add_argument("--privacy-policy-en", required=True, type=pathlib.Path)
    value.add_argument("--user-agreement-zh", required=True, type=pathlib.Path)
    value.add_argument("--user-agreement-en", required=True, type=pathlib.Path)
    value.add_argument("--corresponding-source", required=True, type=pathlib.Path)
    value.add_argument("--sbom", required=True, type=pathlib.Path)
    value.add_argument("--security-report", required=True, type=pathlib.Path)
    value.add_argument("--evidence", action="append", default=[], metavar="KIND=PATH")
    return value


def main() -> int:
    try:
        result = verify(parser().parse_args())
    except (ApprovalError, KeyError, TypeError) as error:
        print(f"RELEASE_APPROVAL_INVALID: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
