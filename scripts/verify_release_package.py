#!/usr/bin/env python3
"""Fail-closed structural and semantic verifier for HarmonyOS release packages.

The verifier deliberately does not extract archives.  It validates every ZIP
entry before reading bounded metadata and rejects archive tricks that ordinary
`unzip` based checks can miss.  Signature cryptography remains the job of
Huawei's hap-sign-tool; this script validates the signed HAP payload itself.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import stat
import sys
import zipfile


MAX_APP_ENTRIES = 64
MAX_APP_UNCOMPRESSED = 256 * 1024 * 1024
MAX_HAP_ENTRIES = 8192
MAX_HAP_UNCOMPRESSED = 384 * 1024 * 1024
MAX_METADATA_BYTES = 2 * 1024 * 1024
EXPECTED_PERMISSIONS = {
    "ohos.permission.GET_BUNDLE_INFO",
    "ohos.permission.GET_NETWORK_INFO",
    "ohos.permission.INTERNET",
}


class PackageError(ValueError):
    pass


def load_json(path: pathlib.Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise PackageError(f"invalid JSON metadata: {path.name}") from error
    if not isinstance(value, dict):
        raise PackageError(f"JSON root is not an object: {path.name}")
    return value


def normalized_archive_name(raw: str) -> str:
    if not raw or "\\" in raw or any(ord(character) < 32 or ord(character) == 127 for character in raw):
        raise PackageError("unsafe ZIP entry name")
    if raw.startswith(("/", "\\")) or re.match(r"^[A-Za-z]:", raw):
        raise PackageError("absolute ZIP entry path")
    path = pathlib.PurePosixPath(raw)
    if any(part in ("", ".", "..") for part in path.parts):
        raise PackageError("non-canonical ZIP entry path")
    return str(path)


def validate_zip(path: pathlib.Path, *, max_entries: int, max_uncompressed: int) -> tuple[zipfile.ZipFile, dict[str, zipfile.ZipInfo]]:
    try:
        archive = zipfile.ZipFile(path)
    except (OSError, zipfile.BadZipFile) as error:
        raise PackageError(f"not a readable ZIP: {path.name}") from error
    infos: dict[str, zipfile.ZipInfo] = {}
    total = 0
    for info in archive.infolist():
        name = normalized_archive_name(info.filename.rstrip("/") if info.is_dir() else info.filename)
        if name in infos:
            archive.close()
            raise PackageError(f"duplicate ZIP entry: {name}")
        mode = (info.external_attr >> 16) & 0xFFFF
        if mode and not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
            archive.close()
            raise PackageError(f"symlink or special ZIP entry: {name}")
        if info.file_size < 0 or info.compress_size < 0:
            archive.close()
            raise PackageError("negative ZIP entry size")
        total += info.file_size
        if total > max_uncompressed:
            archive.close()
            raise PackageError("ZIP uncompressed size limit exceeded")
        infos[name] = info
        if len(infos) > max_entries:
            archive.close()
            raise PackageError("ZIP entry count limit exceeded")
    if not infos:
        archive.close()
        raise PackageError("empty ZIP package")
    return archive, infos


def read_bounded_json(archive: zipfile.ZipFile, infos: dict[str, zipfile.ZipInfo], name: str) -> dict:
    info = infos.get(name)
    if info is None or info.is_dir():
        raise PackageError(f"missing required package metadata: {name}")
    if info.file_size > MAX_METADATA_BYTES:
        raise PackageError(f"package metadata is too large: {name}")
    try:
        value = json.loads(archive.read(info).decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError, RuntimeError, zipfile.BadZipFile) as error:
        raise PackageError(f"invalid package JSON: {name}") from error
    if not isinstance(value, dict):
        raise PackageError(f"package JSON root is not an object: {name}")
    return value


def require_equal(actual: object, expected: object, label: str) -> None:
    if actual != expected:
        raise PackageError(f"{label} mismatch")


def require_artifact_binding(value: object, label: str) -> None:
    if not isinstance(value, dict) or set(value) != {"file", "sha256", "sizeBytes", "format"}:
        raise PackageError(f"{label} binding mismatch")
    filename = value.get("file")
    digest = value.get("sha256")
    size = value.get("sizeBytes")
    format_name = value.get("format")
    if (not isinstance(filename, str) or not filename or "/" in filename or "\\" in filename or
            not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest) or
            not isinstance(size, int) or size <= 0 or
            not isinstance(format_name, str) or not format_name):
        raise PackageError(f"{label} binding mismatch")


def api_major(value: object, label: str) -> int:
    if not isinstance(value, int):
        raise PackageError(f"invalid {label}")
    # Accept only the exact encodings produced by the reviewed API 26 SDK.
    # Inferring from trailing digits would let malformed values such as 1022
    # masquerade as the HarmonyOS 6.0.2 / API 22 compatibility declaration.
    reviewed_encodings = {
        22: 22,
        26: 26,
        60002022: 22,
        260000026: 26,
    }
    if value in reviewed_encodings:
        return reviewed_encodings[value]
    raise PackageError(f"invalid encoded {label}")


def verify_app(args: argparse.Namespace) -> dict:
    repository_app = load_json(args.app_json).get("app")
    repository_module = load_json(args.module_json).get("module")
    release_manifest = load_json(args.release_manifest) if args.release_manifest else None
    if not isinstance(repository_app, dict) or not isinstance(repository_module, dict):
        raise PackageError("repository app/module manifest is invalid")

    expected_bundle = repository_app.get("bundleName")
    expected_version_name = repository_app.get("versionName")
    expected_version_code = repository_app.get("versionCode")
    expected_module_name = repository_module.get("name")
    expected_device_types = repository_module.get("deviceTypes")
    expected_main_element = repository_module.get("mainElement")
    expected_pages = repository_module.get("pages")
    repository_abilities = repository_module.get("abilities")
    expected_home_skills = [{
        "entities": ["entity.system.home"],
        "actions": ["ohos.want.action.home"],
    }]
    if (not isinstance(repository_abilities, list) or len(repository_abilities) != 1 or
            not isinstance(repository_abilities[0], dict)):
        raise PackageError("repository must declare exactly one reviewed application ability")
    repository_ability = repository_abilities[0]
    require_equal(expected_main_element, "EntryAbility", "repository main ability")
    require_equal(repository_ability.get("name"), expected_main_element, "repository ability name")
    require_equal(repository_ability.get("exported"), True, "repository home ability exported flag")
    require_equal(repository_ability.get("skills"), expected_home_skills, "repository home ability skills")
    if not isinstance(expected_pages, str) or not expected_pages:
        raise PackageError("repository page profile is invalid")
    if release_manifest is not None:
        manifest_app = release_manifest.get("application", {})
        require_equal(manifest_app.get("bundleName"), expected_bundle, "release bundle name")
        require_equal(manifest_app.get("versionName"), expected_version_name, "release version name")
        require_equal(manifest_app.get("versionCode"), expected_version_code, "release version code")
        require_equal(manifest_app.get("targetApi"), 26, "release target API")
        security_evidence = release_manifest.get("securityEvidence")
        if not isinstance(security_evidence, dict) or set(security_evidence) != {
                "schemaVersion", "sbom", "report", "policy", "verification"}:
            raise PackageError("release security evidence metadata mismatch")
        require_equal(security_evidence.get("schemaVersion"), 1, "release security evidence schema")
        for evidence_name in ("sbom", "report", "policy", "verification"):
            require_artifact_binding(security_evidence.get(evidence_name), f"release security {evidence_name}")

    app_archive, app_infos = validate_zip(
        args.app, max_entries=MAX_APP_ENTRIES, max_uncompressed=MAX_APP_UNCOMPRESSED
    )
    try:
        pack_info = read_bounded_json(app_archive, app_infos, "pack.info")
        payloads = [name for name, info in app_infos.items() if not info.is_dir()]
        directories = [name for name, info in app_infos.items() if info.is_dir()]
        if directories:
            raise PackageError("App Pack contains unexpected directory entries")
        hap_names = [name for name in payloads if name.lower().endswith(".hap")]
        hsp_names = [name for name in payloads if name.lower().endswith(".hsp")]
        allowed = {"pack.info", *hap_names}
        extras = sorted(set(payloads) - allowed)
        if len(hap_names) != 1:
            raise PackageError("App Pack must contain exactly one HAP")
        if hsp_names:
            raise PackageError("App Pack must not contain HSP payloads")
        if extras:
            raise PackageError("App Pack contains unexpected payloads")
        if "/" in hap_names[0]:
            raise PackageError("HAP payload must be at App Pack root")

        summary = pack_info.get("summary", {})
        pack_app = summary.get("app", {}) if isinstance(summary, dict) else {}
        pack_version = pack_app.get("version", {}) if isinstance(pack_app, dict) else {}
        require_equal(pack_app.get("bundleName"), expected_bundle, "pack.info bundle name")
        require_equal(pack_app.get("bundleType"), "app", "pack.info bundle type")
        require_equal(pack_version.get("name"), expected_version_name, "pack.info version name")
        require_equal(pack_version.get("code"), expected_version_code, "pack.info version code")
        modules = summary.get("modules") if isinstance(summary, dict) else None
        packages = pack_info.get("packages")
        if not isinstance(modules, list) or len(modules) != 1:
            raise PackageError("pack.info must describe exactly one module")
        if not isinstance(packages, list) or len(packages) != 1:
            raise PackageError("pack.info must describe exactly one package")
        pack_module = modules[0]
        pack_package = packages[0]
        if not isinstance(pack_module, dict) or not isinstance(pack_package, dict):
            raise PackageError("pack.info module/package is invalid")
        distro = pack_module.get("distro", {})
        pack_api = pack_module.get("apiVersion", {})
        if not isinstance(distro, dict) or not isinstance(pack_api, dict):
            raise PackageError("pack.info distro/API metadata is invalid")
        require_equal(distro.get("moduleName"), expected_module_name, "pack.info module name")
        require_equal(distro.get("moduleType"), "entry", "pack.info module type")
        require_equal(distro.get("deliveryWithInstall"), True, "pack.info delivery mode")
        require_equal(distro.get("installationFree"), False, "pack.info installation mode")
        require_equal(pack_module.get("deviceType"), expected_device_types, "pack.info device type")
        require_equal(pack_package.get("deviceType"), expected_device_types, "pack.info package device type")
        require_equal(pack_package.get("moduleType"), "entry", "pack.info package module type")
        require_equal(pack_package.get("deliveryWithInstall"), True, "pack.info package delivery mode")
        require_equal(pack_package.get("name"), f"{expected_module_name}-default", "pack.info package name")
        expected_hap_names = {
            f"{pack_package.get('name')}.hap",
            f"{pack_package.get('name')}-signed.hap",
        }
        if hap_names[0] not in expected_hap_names:
            raise PackageError("App Pack HAP filename does not match pack.info package")
        require_equal(pack_api.get("compatible"), 22, "pack.info compatible API")
        require_equal(pack_api.get("target"), 26, "pack.info target API")
        require_equal(str(pack_api.get("releaseType", "")).lower(), "release",
                      "pack.info SDK release channel")
        require_equal(pack_module.get("mainAbility"), expected_main_element, "pack.info main ability")
        pack_abilities = pack_module.get("abilities")
        if (not isinstance(pack_abilities, list) or len(pack_abilities) != 1 or
                not isinstance(pack_abilities[0], dict)):
            raise PackageError("pack.info must describe exactly one application ability")
        require_equal(pack_abilities[0].get("name"), expected_main_element, "pack.info ability name")
        pack_extensions = pack_module.get("extensionAbilities")
        if (not isinstance(pack_extensions, list) or len(pack_extensions) != 1 or
                not isinstance(pack_extensions[0], dict) or
                pack_extensions[0].get("name") != "NetworkVpnExtAbility"):
            raise PackageError("pack.info VPN extension list mismatch")

        hap_payload = app_archive.read(app_infos[hap_names[0]])
        hap_digest = hashlib.sha256(hap_payload).hexdigest()
        if release_manifest is not None:
            manifest_haps = release_manifest.get("appPack", {}).get("haps")
            if not isinstance(manifest_haps, list) or len(manifest_haps) != 1:
                raise PackageError("release manifest must declare exactly one HAP")
            declared_hap = manifest_haps[0]
            if not isinstance(declared_hap, dict):
                raise PackageError("release HAP manifest is invalid")
            require_equal(declared_hap.get("path"), hap_names[0], "release HAP path")
            require_equal(declared_hap.get("profileType"), "release", "release HAP profile")
            require_equal(declared_hap.get("sha256"), hap_digest, "release HAP digest")
    finally:
        app_archive.close()

    # Re-open from bounded bytes in memory: the .app itself was already checked
    # for pathological entry sizes before this payload was read.
    import io
    try:
        hap_archive = zipfile.ZipFile(io.BytesIO(hap_payload))
    except zipfile.BadZipFile as error:
        raise PackageError("embedded HAP is not a readable ZIP") from error
    hap_infos: dict[str, zipfile.ZipInfo] = {}
    total = 0
    try:
        for info in hap_archive.infolist():
            name = normalized_archive_name(info.filename.rstrip("/") if info.is_dir() else info.filename)
            if name in hap_infos:
                raise PackageError(f"duplicate HAP entry: {name}")
            mode = (info.external_attr >> 16) & 0xFFFF
            if mode and not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
                raise PackageError(f"symlink or special HAP entry: {name}")
            total += info.file_size
            if total > MAX_HAP_UNCOMPRESSED or len(hap_infos) + 1 > MAX_HAP_ENTRIES:
                raise PackageError("HAP expansion limit exceeded")
            hap_infos[name] = info
        compiled = read_bounded_json(hap_archive, hap_infos, "module.json")
        embedded_pack = read_bounded_json(hap_archive, hap_infos, "pack.info")
        require_equal(embedded_pack, pack_info, "HAP/App Pack pack.info")
    finally:
        hap_archive.close()

    compiled_app = compiled.get("app")
    compiled_module = compiled.get("module")
    if not isinstance(compiled_app, dict) or not isinstance(compiled_module, dict):
        raise PackageError("compiled HAP module manifest is invalid")
    require_equal(compiled_app.get("bundleName"), expected_bundle, "HAP bundle name")
    require_equal(compiled_app.get("bundleType"), "app", "HAP bundle type")
    require_equal(compiled_app.get("versionName"), expected_version_name, "HAP version name")
    require_equal(compiled_app.get("versionCode"), expected_version_code, "HAP version code")
    require_equal(compiled_app.get("debug"), False, "HAP debug flag")
    require_equal(compiled_app.get("buildMode"), "release", "HAP build mode")
    require_equal(compiled_app.get("compileSdkType"), "HarmonyOS", "HAP compile SDK type")
    require_equal(str(compiled_app.get("apiReleaseType", "")).lower(), "release",
                  "HAP SDK release channel")
    compile_sdk = compiled_app.get("compileSdkVersion")
    if not isinstance(compile_sdk, str) or not re.fullmatch(r"26(?:\.[0-9]+){2,3}", compile_sdk):
        raise PackageError("HAP compile SDK is not API 26")
    require_equal(api_major(compiled_app.get("minAPIVersion"), "HAP compatible API"),
                  22, "HAP compatible API")
    require_equal(api_major(compiled_app.get("targetAPIVersion"), "HAP target API"),
                  26, "HAP target API")
    require_equal(compiled_module.get("name"), expected_module_name, "HAP module name")
    require_equal(compiled_module.get("type"), "entry", "HAP module type")
    require_equal(compiled_module.get("deviceTypes"), expected_device_types, "HAP device type")
    require_equal(compiled_module.get("deliveryWithInstall"), True, "HAP delivery mode")
    require_equal(compiled_module.get("installationFree"), False, "HAP installation mode")
    require_equal(compiled_module.get("mainElement"), expected_main_element, "HAP main ability")
    require_equal(compiled_module.get("pages"), expected_pages, "HAP page profile")
    compiled_abilities = compiled_module.get("abilities")
    if (not isinstance(compiled_abilities, list) or len(compiled_abilities) != 1 or
            not isinstance(compiled_abilities[0], dict)):
        raise PackageError("HAP must contain exactly one application ability")
    compiled_ability = compiled_abilities[0]
    require_equal(compiled_ability.get("name"), expected_main_element, "HAP application ability name")
    require_equal(compiled_ability.get("exported"), True, "HAP home ability exported flag")
    require_equal(compiled_ability.get("srcEntry"), repository_ability.get("srcEntry"), "HAP ability source entry")
    require_equal(compiled_ability.get("skills"), expected_home_skills, "HAP home ability skills")
    permissions = compiled_module.get("requestPermissions")
    if not isinstance(permissions, list) or any(not isinstance(item, dict) for item in permissions):
        raise PackageError("HAP permission manifest is invalid")
    actual_permissions = [item.get("name") for item in permissions]
    if len(actual_permissions) != len(EXPECTED_PERMISSIONS) or set(actual_permissions) != EXPECTED_PERMISSIONS:
        raise PackageError("HAP permission surface is not exactly the reviewed three permissions")
    extension_abilities = compiled_module.get("extensionAbilities")
    if not isinstance(extension_abilities, list) or len(extension_abilities) != 1:
        raise PackageError("HAP must contain exactly one extension ability")
    extension = extension_abilities[0]
    if not isinstance(extension, dict):
        raise PackageError("HAP VPN extension manifest is invalid")
    require_equal(extension.get("name"), "NetworkVpnExtAbility", "HAP VPN extension name")
    require_equal(extension.get("type"), "vpn", "HAP VPN extension type")
    require_equal(extension.get("exported"), False, "HAP VPN extension exported flag")

    return {
        "bundleName": expected_bundle,
        "versionName": expected_version_name,
        "versionCode": expected_version_code,
        "hapPath": hap_names[0],
        "hapSha256": hap_digest,
        "permissions": sorted(EXPECTED_PERMISSIONS),
    }


def verify_build_profile(args: argparse.Namespace) -> dict:
    parsed = load_json(args.parsed_build_profile)
    app = parsed.get("app")
    modules = parsed.get("modules")
    if not isinstance(app, dict) or not isinstance(modules, list):
        raise PackageError("build profile root is invalid")
    products = app.get("products")
    signing_configs = app.get("signingConfigs")
    build_modes = app.get("buildModeSet")
    if not isinstance(products, list) or len(products) != 1 or not isinstance(products[0], dict):
        raise PackageError("build profile must contain exactly one product")
    product = products[0]
    require_equal(product.get("name"), "default", "build product name")
    require_equal(product.get("runtimeOS"), "HarmonyOS", "build runtime OS")
    require_equal(product.get("compileSdkVersion"), "26.0.0", "build compileSdkVersion")
    require_equal(product.get("targetSdkVersion"), "26.0.0", "build targetSdkVersion")
    require_equal(product.get("compatibleSdkVersion"), "6.0.2(22)", "build compatibleSdkVersion")
    signing_name = product.get("signingConfig")
    if not isinstance(signing_name, str) or not signing_name:
        raise PackageError("default product does not reference a signing config")
    if not isinstance(signing_configs, list) or len(signing_configs) != 1 or not isinstance(signing_configs[0], dict):
        raise PackageError("build profile must contain exactly one signing config")
    signing = signing_configs[0]
    require_equal(signing.get("name"), signing_name, "referenced signing config")
    require_equal(signing.get("type"), "HarmonyOS", "signing config type")
    material = signing.get("material")
    if not isinstance(material, dict):
        raise PackageError("signing material declaration is invalid")
    expected_material_keys = {
        "certpath", "keyAlias", "keyPassword", "profile", "signAlg",
        "storeFile", "storePassword",
    }
    require_equal(set(material), expected_material_keys, "signing material fields")
    require_equal(material.get("signAlg"), "SHA256withECDSA", "signing algorithm")
    for key in expected_material_keys - {"signAlg"}:
        value = material.get(key)
        if not isinstance(value, str) or not value:
            raise PackageError(f"signing material field is empty: {key}")
    if not isinstance(build_modes, list) or {item.get("name") for item in build_modes if isinstance(item, dict)} != {"debug", "release"}:
        raise PackageError("build profile mode set must be exactly debug and release")
    if len(modules) != 1 or not isinstance(modules[0], dict):
        raise PackageError("build profile must contain exactly one module")
    module = modules[0]
    require_equal(module.get("name"), "entry", "build module name")
    require_equal(module.get("srcPath"), "./entry", "build module path")
    targets = module.get("targets")
    if not isinstance(targets, list) or len(targets) != 1 or not isinstance(targets[0], dict):
        raise PackageError("build module must contain exactly one target")
    require_equal(targets[0].get("name"), "default", "build target name")
    require_equal(targets[0].get("applyToProducts"), ["default"], "build target product")

    # This digest is safe to record: it is computed only from release semantics
    # and public certificate/profile bytes. Passwords, aliases and local paths
    # are reduced to presence booleans and never enter the digest.
    public_files: dict[str, str] = {}
    for key in ("certpath", "profile", "storeFile"):
        path = pathlib.Path(material[key]).expanduser()
        if not path.is_absolute():
            path = (args.build_profile_dir / path).resolve()
        if not path.is_file():
            raise PackageError(f"signing file is missing: {key}")
        if key != "storeFile":
            public_files[key] = hashlib.sha256(path.read_bytes()).hexdigest()
    redacted = {
        "schemaVersion": 1,
        "product": {
            key: product[key]
            for key in ("name", "runtimeOS", "compileSdkVersion", "targetSdkVersion", "compatibleSdkVersion")
        },
        "signing": {
            "name": signing_name,
            "type": signing["type"],
            "signAlg": material["signAlg"],
            "certSha256": public_files["certpath"],
            "profileSha256": public_files["profile"],
            "keyAliasPresent": True,
            "keyPasswordPresent": True,
            "storeFilePresent": True,
            "storePasswordPresent": True,
        },
        "buildModes": ["debug", "release"],
        "module": {"name": "entry", "srcPath": "./entry", "target": "default", "products": ["default"]},
    }
    canonical = json.dumps(redacted, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return {"redactedBuildProfileSha256": hashlib.sha256(canonical).hexdigest()}


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    app_parser = subparsers.add_parser("app")
    app_parser.add_argument("--app", type=pathlib.Path, required=True)
    app_parser.add_argument("--release-manifest", type=pathlib.Path)
    app_parser.add_argument("--app-json", type=pathlib.Path, required=True)
    app_parser.add_argument("--module-json", type=pathlib.Path, required=True)
    profile_parser = subparsers.add_parser("build-profile")
    profile_parser.add_argument("--parsed-build-profile", type=pathlib.Path, required=True)
    profile_parser.add_argument("--build-profile-dir", type=pathlib.Path, required=True)
    args = parser.parse_args()
    try:
        result = verify_app(args) if args.command == "app" else verify_build_profile(args)
    except (PackageError, OSError, KeyError, zipfile.BadZipFile) as error:
        print(f"RELEASE_PACKAGE_INVALID: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
