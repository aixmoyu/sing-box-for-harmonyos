#!/usr/bin/env python3
"""Generate small deterministic package fixtures for release-gate tests."""

from __future__ import annotations

import hashlib
import json
import pathlib
import stat
import sys
import zipfile


def encoded(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def add_file(archive: zipfile.ZipFile, name: str, payload: bytes) -> None:
    info = zipfile.ZipInfo(name)
    info.external_attr = (stat.S_IFREG | 0o644) << 16
    archive.writestr(info, payload)


root = pathlib.Path(sys.argv[1])
variant = sys.argv[2]
root.mkdir(parents=True, exist_ok=True)

bundle = "com.harmonynet.assistant"
version_name = "0.1.0"
version_code = 1000000
permissions = [
    {"name": "ohos.permission.INTERNET"},
    {"name": "ohos.permission.GET_NETWORK_INFO"},
    {"name": "ohos.permission.GET_BUNDLE_INFO"},
]
if variant == "bad-permissions":
    permissions.append({"name": "ohos.permission.LOCATION"})

home_skills = [{
    "entities": ["entity.system.home"],
    "actions": ["ohos.want.action.home"],
}]
compiled_abilities = [{
    "name": "EntryAbility",
    "srcEntry": "./ets/entryability/EntryAbility.ets",
    "exported": variant != "private-entry-ability",
    "skills": ([{"entities": ["entity.system.home"], "actions": ["unexpected.action"]}]
               if variant == "bad-home-skill" else home_skills),
}]
if variant == "extra-compiled-ability":
    compiled_abilities.append({
        "name": "UnexpectedAbility",
        "srcEntry": "./ets/entryability/UnexpectedAbility.ets",
        "exported": True,
        "skills": [],
    })

pack_abilities = [{"name": "EntryAbility"}]
if variant == "extra-pack-ability":
    pack_abilities.append({"name": "UnexpectedAbility"})

pack_info = {
    "summary": {
        "app": {
            "bundleName": bundle,
            "bundleType": "app",
            "version": {"code": version_code, "name": version_name},
        },
        "modules": [{
            "mainAbility": "UnexpectedAbility" if variant == "bad-pack-main-ability" else "EntryAbility",
            "deviceType": ["phone"],
            "abilities": pack_abilities,
            "extensionAbilities": [{"name": "NetworkVpnExtAbility"}],
            "distro": {
                "moduleType": "entry",
                "installationFree": False,
                "deliveryWithInstall": True,
                "moduleName": "entry",
            },
            "apiVersion": {
                "compatible": 26 if variant == "bad-pack" else 22,
                "releaseType": "Beta2" if variant == "beta-pack-sdk" else "Release",
                "target": 26,
            },
        }],
    },
    "packages": [{
        "deviceType": ["phone"],
        "moduleType": "entry",
        "deliveryWithInstall": True,
        "name": "entry-default",
    }],
}

module = {
    "app": {
        "debug": variant == "debug",
        "buildMode": "debug" if variant == "debug" else "release",
        "minAPIVersion": (260000026 if variant == "bad-min-api" else
                          1022 if variant == "malformed-min-api-encoding" else
                          60002022),
        "targetAPIVersion": 260000026,
        "bundleType": "app",
        "compileSdkType": "HarmonyOS",
        "compileSdkVersion": "26.0.0.32",
        "apiReleaseType": "Beta2" if variant == "beta-hap-sdk" else "Release",
        "versionName": version_name,
        "versionCode": version_code,
        "bundleName": bundle,
    },
    "module": {
        "mainElement": "UnexpectedAbility" if variant == "bad-main-element" else "EntryAbility",
        "installationFree": False,
        "deliveryWithInstall": True,
        "pages": "$profile:main_pages",
        "requestPermissions": permissions,
        "extensionAbilities": [{
            "exported": variant == "exported-vpn",
            "name": "NetworkVpnExtAbility",
            "type": "vpn",
        }],
        "type": "entry",
        "deviceTypes": ["phone"],
        "name": "entry",
        "abilities": compiled_abilities,
    },
}

hap_path = root / "entry-default.hap"
with zipfile.ZipFile(hap_path, "w", zipfile.ZIP_DEFLATED) as archive:
    add_file(archive, "module.json", encoded(module))
    add_file(archive, "pack.info", encoded(pack_info))
    add_file(archive, "libs/arm64-v8a/libharmonycore.so", b"fixture-core")
    if variant == "duplicate-hap-entry":
        add_file(archive, "module.json", encoded(module))
    elif variant == "hap-traversal":
        add_file(archive, "../escape", b"unsafe")
    elif variant == "hap-symlink":
        info = zipfile.ZipInfo("link")
        info.create_system = 3
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        archive.writestr(info, "module.json")

hap_payload = hap_path.read_bytes()
app_path = root / "Fixture.app"
with zipfile.ZipFile(app_path, "w", zipfile.ZIP_DEFLATED) as archive:
    add_file(archive, "pack.info", encoded(pack_info))
    add_file(archive, "entry-default.hap", hap_payload)
    if variant == "hsp":
        add_file(archive, "shared.hsp", b"hsp")
    elif variant == "extra":
        add_file(archive, "payload.bin", b"unexpected")
    elif variant == "two-hap":
        add_file(archive, "second.hap", hap_payload)
    elif variant == "traversal":
        add_file(archive, "../escape", b"unsafe")
    elif variant == "absolute":
        add_file(archive, "/escape", b"unsafe")
    elif variant == "windows-absolute":
        add_file(archive, "C:/escape", b"unsafe")
    elif variant == "backslash":
        add_file(archive, "dir\\escape", b"unsafe")
    elif variant == "duplicate-app-entry":
        add_file(archive, "pack.info", encoded(pack_info))
    elif variant == "symlink":
        info = zipfile.ZipInfo("link")
        info.create_system = 3
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        archive.writestr(info, "pack.info")
    elif variant == "directory":
        info = zipfile.ZipInfo("unexpected/")
        info.create_system = 3
        info.external_attr = (stat.S_IFDIR | 0o755) << 16
        archive.writestr(info, b"")
    elif variant == "special":
        info = zipfile.ZipInfo("fifo")
        info.create_system = 3
        info.external_attr = (stat.S_IFIFO | 0o600) << 16
        archive.writestr(info, b"")

if variant == "oversize":
    payload = bytearray(app_path.read_bytes())
    central = payload.find(b"PK\x01\x02")
    if central < 0:
        raise SystemExit("fixture has no central directory")
    payload[central + 24:central + 28] = (0xFFFFFFFF).to_bytes(4, "little")
    app_path.write_bytes(payload)

manifest = {
    "application": {
        "bundleName": bundle,
        "versionName": version_name,
        "versionCode": version_code,
        "targetApi": 26,
    },
    "appPack": {
        "haps": [{
            "path": "entry-default.hap",
            "sha256": hashlib.sha256(hap_payload).hexdigest(),
            "profileType": "release",
        }],
    },
    "securityEvidence": {
        "schemaVersion": 1,
        **{
            name: {
                "file": f"fixture-{name}.json",
                "sha256": hashlib.sha256(f"fixture-{name}".encode()).hexdigest(),
                "sizeBytes": len(f"fixture-{name}"),
                "format": f"fixture-{name}-v1",
            }
            for name in ("sbom", "report", "policy", "verification")
        },
    },
}
if variant == "bad-security-binding":
    manifest["securityEvidence"].pop("report")
(root / "release-manifest.json").write_bytes(encoded(manifest))
