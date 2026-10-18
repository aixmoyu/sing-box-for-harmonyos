#!/usr/bin/env python3
"""Fail-closed release gate for a signed vulnerability and license scan report.

This tool does not scan dependencies and never interprets an absent scanner
database as "no vulnerabilities".  It verifies that a trusted, fresh scanner
report covers the exact deterministic SBOM and that every blocking finding is
resolved by policy or by a still-valid signed waiver.
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


class SecurityGateError(RuntimeError):
    pass


def canonical(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise SecurityGateError(f"cannot read valid JSON {path}: {error}") from error


def parse_time(value: Any, field: str) -> dt.datetime:
    if not isinstance(value, str) or not value.endswith("Z"):
        raise SecurityGateError(f"{field} must be an RFC3339 UTC timestamp ending in Z")
    try:
        parsed = dt.datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as error:
        raise SecurityGateError(f"{field} is not a valid timestamp") from error
    return parsed


def require_text(value: Any, field: str, minimum: int = 1) -> str:
    if not isinstance(value, str) or len(value.strip()) < minimum:
        raise SecurityGateError(f"{field} must contain at least {minimum} non-whitespace characters")
    if re.search(r"(?i)\b(todo|tbd|placeholder|example|unknown|n/?a)\b", value):
        raise SecurityGateError(f"{field} contains a placeholder value")
    return value.strip()


def require_sha256(value: Any, field: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value) or len(set(value)) == 1:
        raise SecurityGateError(f"{field} must be a non-placeholder lowercase SHA-256 digest")
    return value


def require_exact_keys(value: Any, required: set[str], optional: set[str], field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise SecurityGateError(f"{field} must be an object")
    missing = required - set(value)
    extra = set(value) - required - optional
    if missing or extra:
        raise SecurityGateError(f"{field} schema mismatch; missing={sorted(missing)} extra={sorted(extra)}")
    return value


def decode_base64(value: Any, expected_size: int, field: str) -> bytes:
    if not isinstance(value, str):
        raise SecurityGateError(f"{field} is not valid base64")
    try:
        decoded = base64.b64decode(value, validate=True)
    except (ValueError, TypeError) as error:
        raise SecurityGateError(f"{field} is not valid base64") from error
    if len(decoded) != expected_size:
        raise SecurityGateError(f"{field} must decode to exactly {expected_size} bytes")
    return decoded


def verify_signature(report: dict[str, Any], policy: dict[str, Any]) -> tuple[str, dict[str, Any]]:
    signature = require_exact_keys(report.get("signature"), {"algorithm", "keyId", "value"}, set(), "signature")
    if signature.get("algorithm") != "Ed25519":
        raise SecurityGateError("only Ed25519 scan report signatures are accepted")
    key_id = require_text(signature.get("keyId"), "signature.keyId")
    trusted = [key for key in policy.get("trustedKeys", []) if key.get("id") == key_id]
    if len(trusted) != 1:
        raise SecurityGateError(f"signature key is not uniquely trusted by policy: {key_id}")
    key = trusted[0]
    if "release-security" not in key.get("roles", []):
        raise SecurityGateError(f"trusted key lacks release-security role: {key_id}")
    key_bytes = decode_base64(
        key.get("publicKeyBase64"), 32, f"trustedKeys[{key_id}].publicKeyBase64",
    )
    if sha256_bytes(key_bytes) != require_sha256(key.get("sha256"), f"trustedKeys[{key_id}].sha256"):
        raise SecurityGateError(f"trusted public key digest mismatch: {key_id}")
    signature_bytes = decode_base64(signature.get("value"), 64, "signature.value")

    unsigned = dict(report)
    unsigned.pop("signature", None)
    expected_payload_hash = unsigned.pop("payloadSha256", None)
    payload = canonical(unsigned)
    if sha256_bytes(payload) != require_sha256(expected_payload_hash, "payloadSha256"):
        raise SecurityGateError("scan report payload digest mismatch")
    # RFC 8410 SubjectPublicKeyInfo prefix for a raw 32-byte Ed25519 key. Use
    # the already-required OpenSSL CLI so the gate has no undeclared Python
    # package dependency and never writes private material.
    public_key_der = bytes.fromhex("302a300506032b6570032100") + key_bytes
    with tempfile.TemporaryDirectory(prefix="hna-security-signature.") as temp:
        directory = Path(temp)
        key_path = directory / "public-key.der"
        payload_path = directory / "payload.bin"
        signature_path = directory / "signature.bin"
        key_path.write_bytes(public_key_der)
        payload_path.write_bytes(payload)
        signature_path.write_bytes(signature_bytes)
        try:
            verified = subprocess.run([
                "openssl", "pkeyutl", "-verify", "-pubin", "-keyform", "DER",
                "-inkey", str(key_path), "-rawin", "-in", str(payload_path),
                "-sigfile", str(signature_path),
            ], text=True, capture_output=True, check=False)
        except OSError as error:
            raise SecurityGateError("OpenSSL is required for Ed25519 verification") from error
    if verified.returncode != 0:
        raise SecurityGateError("scan report signature verification failed")
    return key_id, key


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sbom", type=Path, required=True)
    parser.add_argument("--security-report", "--report", dest="report", type=Path, required=True)
    parser.add_argument("--policy", type=Path, required=True)
    parser.add_argument("--now", help="test-only UTC timestamp")
    parser.add_argument("--allow-test-time", action="store_true")
    args = parser.parse_args()
    if args.now and not args.allow_test_time:
        raise SecurityGateError("--now requires explicit --allow-test-time")
    if args.allow_test_time and not args.now:
        raise SecurityGateError("--allow-test-time is valid only with --now")
    now = parse_time(args.now, "--now") if args.now else dt.datetime.now(dt.timezone.utc)

    sbom_bytes = args.sbom.read_bytes()
    sbom, report, policy = load_json(args.sbom), load_json(args.report), load_json(args.policy)
    if canonical(sbom) != sbom_bytes:
        raise SecurityGateError("SBOM is not canonical deterministic JSON")
    if sbom.get("bomFormat") != "CycloneDX" or sbom.get("specVersion") != "1.6" or sbom.get("version") != 1:
        raise SecurityGateError("unsupported or malformed CycloneDX SBOM")
    if policy.get("schemaVersion") != 1:
        raise SecurityGateError("unsupported security policy schema")
    require_exact_keys(policy, {
        "schemaVersion", "maxReportAgeDays", "maxDatabaseAgeDays", "maxFutureSkewMinutes",
        "maxWaiverDays",
        "blockSeverities", "allowCriticalWaivers", "allowedLicenseExpressions",
        "deniedLicenseExpressions", "trustedKeys",
    }, set(), "security policy")
    for numeric_field in ("maxReportAgeDays", "maxDatabaseAgeDays", "maxFutureSkewMinutes", "maxWaiverDays"):
        if not isinstance(policy.get(numeric_field), int) or policy[numeric_field] < 0:
            raise SecurityGateError(f"security policy {numeric_field} must be a non-negative integer")
    if not isinstance(policy.get("allowCriticalWaivers"), bool):
        raise SecurityGateError("security policy allowCriticalWaivers must be boolean")
    known_severities = {"critical", "high", "medium", "low", "negligible"}
    if not isinstance(policy.get("blockSeverities"), list) or not set(policy["blockSeverities"]).issubset(known_severities):
        raise SecurityGateError("security policy blockSeverities is invalid")
    if len(policy["blockSeverities"]) != len(set(policy["blockSeverities"])):
        raise SecurityGateError("security policy blockSeverities contains duplicates")
    for license_field in ("allowedLicenseExpressions", "deniedLicenseExpressions"):
        if not isinstance(policy.get(license_field), list) or any(not isinstance(value, str) or not value for value in policy[license_field]):
            raise SecurityGateError(f"security policy {license_field} is invalid")
        if len(policy[license_field]) != len(set(policy[license_field])):
            raise SecurityGateError(f"security policy {license_field} contains duplicates")
    if set(policy["allowedLicenseExpressions"]) & set(policy["deniedLicenseExpressions"]):
        raise SecurityGateError("security policy allows and denies the same license expression")
    if not isinstance(policy.get("trustedKeys"), list):
        raise SecurityGateError("security policy trustedKeys must be an array")
    trusted_ids: list[str] = []
    for index, trusted in enumerate(policy["trustedKeys"]):
        trusted = require_exact_keys(trusted, {"id", "roles", "publicKeyBase64", "sha256", "notBefore", "notAfter"}, set(), f"trustedKeys[{index}]")
        trusted_ids.append(require_text(trusted.get("id"), f"trustedKeys[{index}].id"))
        if not isinstance(trusted.get("roles"), list) or not all(isinstance(role, str) for role in trusted["roles"]):
            raise SecurityGateError(f"trustedKeys[{index}].roles must be a string array")
        if len(trusted["roles"]) != len(set(trusted["roles"])):
            raise SecurityGateError(f"trustedKeys[{index}].roles contains duplicates")
        require_sha256(trusted.get("sha256"), f"trustedKeys[{index}].sha256")
        decode_base64(trusted.get("publicKeyBase64"), 32, f"trustedKeys[{index}].publicKeyBase64")
        if parse_time(trusted.get("notAfter"), f"trustedKeys[{index}].notAfter") <= parse_time(trusted.get("notBefore"), f"trustedKeys[{index}].notBefore"):
            raise SecurityGateError(f"trustedKeys[{index}] validity window is invalid")
    if len(trusted_ids) != len(set(trusted_ids)):
        raise SecurityGateError("security policy contains duplicate trusted key IDs")
    if report.get("schemaVersion") != 1 or report.get("kind") != "hna.release-security-scan":
        raise SecurityGateError("unsupported scan report schema or kind")
    require_exact_keys(report, {
        "schemaVersion", "kind", "generatedAt", "sbomSha256", "sbomSerialNumber", "componentCount",
        "scanner", "vulnerabilityDatabase", "coverage", "licenseAnalysis", "findings", "waivers",
        "payloadSha256", "signature",
    }, set(), "scan report")

    metadata_properties = {item.get("name"): item.get("value") for item in sbom.get("metadata", {}).get("properties", [])}
    if metadata_properties.get("hna:fixtureInput") != "false":
        raise SecurityGateError("fixture-derived SBOMs cannot pass a formal release gate")
    required_inputs = {
        "AppScope/app.json5",
        "core/go/go.mod", "core/go/go.sum", "third_party/core-lock.json", "oh-package-lock.json5",
        "entry/oh-package-lock.json5", "coreBuildInfo",
    }
    for key in sorted(required_inputs):
        require_sha256(metadata_properties.get(f"hna:inputSha256:{key}"), f"SBOM input {key}")

    root = sbom.get("metadata", {}).get("component")
    components = sbom.get("components")
    if not isinstance(root, dict) or not isinstance(components, list) or not components:
        raise SecurityGateError("SBOM component inventory is empty")
    all_components = [root, *components]
    refs = [item.get("bom-ref") for item in all_components]
    if any(not isinstance(ref, str) or not ref for ref in refs) or len(refs) != len(set(refs)):
        raise SecurityGateError("SBOM has missing or duplicate component references")
    ref_set = set(refs)
    dependency_entries = sbom.get("dependencies")
    if not isinstance(dependency_entries, list):
        raise SecurityGateError("SBOM dependency graph is missing")
    dependency_refs = {entry.get("ref") for entry in dependency_entries}
    if dependency_refs != ref_set:
        raise SecurityGateError("SBOM dependency graph does not cover every component exactly")
    for entry in dependency_entries:
        if not isinstance(entry.get("dependsOn"), list) or not set(entry["dependsOn"]).issubset(ref_set):
            raise SecurityGateError(f"SBOM dependency graph contains an unknown reference: {entry.get('ref')}")
    for component in all_components:
        props = {item.get("name"): item.get("value") for item in component.get("properties", [])}
        scopes = set((props.get("hna:dependencyScopes") or "").split(","))
        if not scopes.intersection({"direct", "transitive", "build", "runtime"}):
            raise SecurityGateError(f"component lacks an explicit dependency scope: {component.get('bom-ref')}")
    runtime_modules = [item for item in components if any(
        prop.get("name") == "hna:dependencyScopes" and "runtime" in prop.get("value", "").split(",")
        for prop in item.get("properties", [])
    )]
    if not runtime_modules:
        raise SecurityGateError("SBOM has no modules proven by compiled-core BuildInfo")

    key_id, trusted_key = verify_signature(report, policy)
    report_time = parse_time(report.get("generatedAt"), "generatedAt")
    database = report.get("vulnerabilityDatabase")
    scanner = report.get("scanner")
    scanner = require_exact_keys(scanner, {"name", "version"}, set(), "scanner")
    database = require_exact_keys(database, {"name", "version", "updatedAt", "sha256"}, set(), "vulnerabilityDatabase")
    require_text(scanner.get("name"), "scanner.name", 2)
    require_text(scanner.get("version"), "scanner.version", 1)
    require_text(database.get("name"), "vulnerabilityDatabase.name", 2)
    require_text(database.get("version"), "vulnerabilityDatabase.version", 1)
    require_sha256(database.get("sha256"), "vulnerabilityDatabase.sha256")
    database_time = parse_time(database.get("updatedAt"), "vulnerabilityDatabase.updatedAt")
    max_future = dt.timedelta(minutes=int(policy.get("maxFutureSkewMinutes", 5)))
    key_not_before = parse_time(trusted_key.get("notBefore"), f"trustedKeys[{key_id}].notBefore")
    key_not_after = parse_time(trusted_key.get("notAfter"), f"trustedKeys[{key_id}].notAfter")
    if (not key_not_before <= report_time < key_not_after or
            not key_not_before <= now < key_not_after):
        raise SecurityGateError(f"trusted signing key is not valid for this release: {key_id}")
    if report_time > now + max_future or database_time > now + max_future:
        raise SecurityGateError("scan report or database snapshot is dated in the future")
    if now - report_time > dt.timedelta(days=int(policy.get("maxReportAgeDays", 7))):
        raise SecurityGateError("scan report is stale")
    if now - database_time > dt.timedelta(days=int(policy.get("maxDatabaseAgeDays", 7))):
        raise SecurityGateError("vulnerability database snapshot is stale")

    sbom_hash = sha256_bytes(sbom_bytes)
    if report.get("sbomSha256") != sbom_hash or report.get("sbomSerialNumber") != sbom.get("serialNumber"):
        raise SecurityGateError("scan report is not bound to this exact SBOM")
    if report.get("componentCount") != len(ref_set):
        raise SecurityGateError("scan report component count does not match SBOM")
    coverage = report.get("coverage")
    coverage = require_exact_keys(coverage, {"mode", "vulnerabilityComponentRefs", "licenseComponentRefs"}, set(), "coverage")
    if coverage.get("mode") != "all-components":
        raise SecurityGateError("scan report does not declare complete component coverage")
    for field in ("vulnerabilityComponentRefs", "licenseComponentRefs"):
        values = coverage.get(field)
        if not isinstance(values, list) or len(values) != len(set(values)) or set(values) != ref_set:
            raise SecurityGateError(f"scan report {field} does not exactly cover the SBOM")

    allowed_licenses = set(policy.get("allowedLicenseExpressions", []))
    denied_licenses = set(policy.get("deniedLicenseExpressions", []))
    license_results = report.get("licenseAnalysis")
    if not isinstance(license_results, list) or len(license_results) != len(ref_set):
        raise SecurityGateError("license analysis does not cover every component exactly once")
    license_refs: set[str] = set()
    for index, result in enumerate(license_results):
        result = require_exact_keys(result, {"componentRef", "expression"}, set(), f"licenseAnalysis[{index}]")
        ref = result.get("componentRef")
        expression = require_text(result.get("expression"), f"licenseAnalysis[{index}].expression")
        if ref not in ref_set or ref in license_refs:
            raise SecurityGateError(f"invalid or duplicate license result component: {ref}")
        license_refs.add(ref)
        if expression in denied_licenses or expression not in allowed_licenses:
            raise SecurityGateError(f"license is not approved by release policy: {ref}: {expression}")

    findings = report.get("findings")
    waivers = report.get("waivers")
    if not isinstance(findings, list) or not isinstance(waivers, list):
        raise SecurityGateError("scan report findings/waivers must be arrays")
    findings_by_id: dict[str, dict[str, Any]] = {}
    for finding in findings:
        finding = require_exact_keys(finding, {"id", "componentRef", "severity", "status"}, {"resolutionReason", "evidence"}, "finding")
        finding_id = require_text(finding.get("id"), "finding.id")
        if finding_id in findings_by_id:
            raise SecurityGateError(f"duplicate finding ID: {finding_id}")
        if finding.get("componentRef") not in ref_set:
            raise SecurityGateError(f"finding refers to an unknown component: {finding_id}")
        if finding.get("severity") not in {"critical", "high", "medium", "low", "negligible"}:
            raise SecurityGateError(f"finding has unsupported/unknown severity: {finding_id}")
        status = finding.get("status")
        if status not in {"open", "fixed", "not_affected", "waived"}:
            raise SecurityGateError(f"finding has unsupported status: {finding_id}")
        if status in {"fixed", "not_affected"}:
            require_text(finding.get("resolutionReason"), f"finding[{finding_id}].resolutionReason", 12)
            require_text(finding.get("evidence"), f"finding[{finding_id}].evidence", 8)
        findings_by_id[finding_id] = finding

    waiver_by_finding: dict[str, dict[str, Any]] = {}
    waiver_ids: set[str] = set()
    for waiver in waivers:
        waiver = require_exact_keys(waiver, {"id", "findingId", "reviewer", "reason", "approvedAt", "expiresAt"}, set(), "waiver")
        waiver_id = require_text(waiver.get("id"), "waiver.id")
        if waiver_id in waiver_ids:
            raise SecurityGateError(f"duplicate waiver ID: {waiver_id}")
        waiver_ids.add(waiver_id)
        finding_id = require_text(waiver.get("findingId"), f"waiver[{waiver_id}].findingId")
        if finding_id not in findings_by_id or finding_id in waiver_by_finding:
            raise SecurityGateError(f"waiver refers to a missing/duplicate finding: {finding_id}")
        require_text(waiver.get("reviewer"), f"waiver[{waiver_id}].reviewer", 3)
        require_text(waiver.get("reason"), f"waiver[{waiver_id}].reason", 20)
        approved = parse_time(waiver.get("approvedAt"), f"waiver[{waiver_id}].approvedAt")
        expires = parse_time(waiver.get("expiresAt"), f"waiver[{waiver_id}].expiresAt")
        if approved > report_time + max_future or expires <= now or expires <= approved:
            raise SecurityGateError(f"waiver is expired or has invalid approval dates: {waiver_id}")
        if expires - approved > dt.timedelta(days=policy["maxWaiverDays"]):
            raise SecurityGateError(f"waiver validity exceeds policy maximum: {waiver_id}")
        waiver_by_finding[finding_id] = waiver

    blocked_severities = set(policy.get("blockSeverities", ["critical", "high"]))
    for finding_id, finding in findings_by_id.items():
        waiver = waiver_by_finding.get(finding_id)
        if finding["status"] == "waived":
            if not waiver:
                raise SecurityGateError(f"waived finding has no signed waiver record: {finding_id}")
            if finding["severity"] == "critical" and not policy.get("allowCriticalWaivers", False):
                raise SecurityGateError(f"critical findings cannot be waived: {finding_id}")
        elif waiver:
            raise SecurityGateError(f"unused waiver does not match finding status: {finding_id}")
        if finding["severity"] in blocked_severities and finding["status"] == "open":
            raise SecurityGateError(f"unresolved blocking-severity finding: {finding_id}")
    unused = set(waiver_by_finding) - set(findings_by_id)
    if unused:  # pragma: no cover - rejected while parsing
        raise SecurityGateError(f"orphaned waivers: {sorted(unused)}")

    print(json.dumps({
        "status": "verified", "meaning": "trusted scan evidence passed policy; this tool did not perform a scan",
        "sbomSha256": sbom_hash, "componentCount": len(ref_set), "findingCount": len(findings),
        "waiverCount": len(waivers), "trustedKeyId": key_id,
        "scanner": f"{scanner['name']} {scanner['version']}", "databaseVersion": database["version"],
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (SecurityGateError, KeyError, TypeError, ValueError, OSError) as error:
        print(f"RELEASE_SECURITY_BLOCKED: {error}", file=sys.stderr)
        raise SystemExit(1)
