#!/usr/bin/env python3
"""Generate a deterministic CycloneDX SBOM from release-authoritative inputs.

The generator deliberately records both the complete declared build graph and the
modules embedded in the native core.  A release SBOM is never inferred only from
go.mod: the compiled core's Go BuildInfo is mandatory.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.parse
import uuid
from pathlib import Path
from typing import Any


GENERATOR_VERSION = "1.1.0"
SERIAL_NAMESPACE = uuid.UUID("ed7b35c6-c6fa-51a9-aead-e82d15a2830c")


class SbomError(RuntimeError):
    pass


def canonical(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_relaxed_json(path: Path) -> Any:
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"(^|\s)//.*?$", r"\1", text, flags=re.M)
    text = re.sub(r",\s*([}\]])", r"\1", text)
    try:
        return json.loads(text)
    except json.JSONDecodeError as error:
        raise SbomError(f"invalid JSON/JSON5 input {path}: {error}") from error


def require_file(path: Path) -> Path:
    if not path.is_file():
        raise SbomError(f"required input is missing: {path}")
    return path


def run(command: list[str], cwd: Path) -> str:
    completed = subprocess.run(command, cwd=cwd, text=True, capture_output=True, check=False)
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise SbomError(f"command failed ({' '.join(command)}): {detail}")
    return completed.stdout


def split_module(token: str) -> tuple[str, str]:
    if "@" not in token:
        return token, ""
    path, version = token.rsplit("@", 1)
    return path, version


def go_ref(path: str, version: str) -> str:
    return f"pkg:golang/{urllib.parse.quote(path, safe='/')}@{urllib.parse.quote(version, safe='.+-')}"


def generic_ref(namespace: str, name: str, version: str) -> str:
    identity = urllib.parse.quote(f"{namespace}/{name}", safe="/")
    return f"pkg:generic/{identity}@{urllib.parse.quote(version, safe='.+-')}"


def decode_go_sum(value: str) -> str | None:
    if not value.startswith("h1:"):
        return None
    try:
        decoded = base64.b64decode(value[3:], validate=True)
    except ValueError:
        return None
    return decoded.hex() if len(decoded) == 32 else None


def read_go_sums(path: Path) -> dict[tuple[str, str], dict[str, str]]:
    result: dict[tuple[str, str], dict[str, str]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        fields = line.split()
        if len(fields) != 3:
            continue
        module, version, checksum = fields
        is_mod = version.endswith("/go.mod")
        version = version.removesuffix("/go.mod")
        result.setdefault((module, version), {})["goModSum" if is_mod else "sum"] = checksum
    return result


def parse_build_info(text: str) -> dict[str, Any]:
    result: dict[str, Any] = {"goVersion": "", "path": "", "modules": [], "settings": {}}
    previous: dict[str, Any] | None = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if ": go" in line and not line.startswith(("path\t", "mod\t", "dep\t", "build\t")):
            result["goVersion"] = line.rsplit(": ", 1)[-1]
            continue
        fields = line.split("\t")
        kind = fields[0]
        if kind == "path" and len(fields) >= 2:
            result["path"] = fields[1]
        elif kind in {"mod", "dep"} and len(fields) >= 3:
            previous = {"kind": kind, "path": fields[1], "version": fields[2]}
            if len(fields) >= 4 and fields[3].startswith("h1:"):
                previous["sum"] = fields[3]
            result["modules"].append(previous)
        elif kind == "=>" and previous is not None and len(fields) >= 2:
            replacement_version = fields[2] if len(fields) >= 3 else ""
            if replacement_version == "(devel)":
                replacement_version = ""
            previous["replacement"] = {"path": fields[1], "version": replacement_version}
        elif kind == "build" and len(fields) >= 2:
            setting = fields[1]
            key, _, value = setting.partition("=")
            result["settings"][key] = value
    if not result["goVersion"] or not result["path"] or not result["modules"]:
        raise SbomError("compiled core BuildInfo is incomplete or unreadable")
    return result


def properties(values: dict[str, Any]) -> list[dict[str, str]]:
    return [{"name": key, "value": str(values[key]).lower() if isinstance(values[key], bool) else str(values[key])}
            for key in sorted(values)]


def load_go_inputs(repo: Path, go_tool: Path, fixture_dir: Path | None) -> tuple[dict[str, Any], str, str]:
    core_dir = repo / "core/go"
    if fixture_dir:
        edit = load_relaxed_json(require_file(fixture_dir / "go-mod-edit.json"))
        graph = require_file(fixture_dir / "go-mod-graph.txt").read_text(encoding="utf-8")
        build_info = require_file(fixture_dir / "core-build-info.txt").read_text(encoding="utf-8")
    else:
        environment = [str(go_tool)]
        edit = json.loads(run(environment + ["mod", "edit", "-json"], core_dir))
        graph = run(environment + ["mod", "graph"], core_dir)
        build_info = ""
    return edit, graph, build_info


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--core-binary", type=Path)
    parser.add_argument("--go-tool", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--fixture-input-dir", type=Path)
    parser.add_argument("--allow-fixture-input", action="store_true")
    args = parser.parse_args()

    repo = args.repo.resolve()
    fixture = args.fixture_input_dir.resolve() if args.fixture_input_dir else None
    if fixture and not args.allow_fixture_input:
        raise SbomError("fixture inputs require the explicit --allow-fixture-input test flag")
    if args.allow_fixture_input and not fixture:
        raise SbomError("--allow-fixture-input is valid only with --fixture-input-dir")

    go_mod = require_file(repo / "core/go/go.mod")
    go_sum = require_file(repo / "core/go/go.sum")
    core_lock_path = require_file(repo / "third_party/core-lock.json")
    root_ohpm_path = require_file(repo / "oh-package-lock.json5")
    entry_ohpm_path = require_file(repo / "entry/oh-package-lock.json5")
    root_manifest_path = require_file(repo / "oh-package.json5")
    entry_manifest_path = require_file(repo / "entry/oh-package.json5")
    app_manifest_path = require_file(repo / "AppScope/app.json5")
    go_tool = (args.go_tool or repo / "third_party/ohos-golang-go-1.24/bin/go").resolve()
    require_file(go_tool)

    edit, graph_text, fixture_build_info = load_go_inputs(repo, go_tool, fixture)
    if fixture:
        binary_path = require_file(fixture / "core-binary.bin")
        build_info_text = fixture_build_info
    else:
        binary_path = require_file((args.core_binary or repo / "core/go/out/libharmonycore.so").resolve())
        build_info_text = run([str(go_tool), "version", "-m", str(binary_path)], repo)
    build_info = parse_build_info(build_info_text)
    if build_info["settings"].get("GOOS") != "openharmony" or build_info["settings"].get("GOARCH") != "arm64":
        raise SbomError("compiled core BuildInfo is not GOOS=openharmony GOARCH=arm64")

    core_lock = load_relaxed_json(core_lock_path)
    if core_lock.get("schema_version") != 2:
        raise SbomError("unsupported third_party/core-lock.json schema")
    application = load_relaxed_json(app_manifest_path).get("app", {})
    bundle_name = application.get("bundleName")
    application_version = application.get("versionName")
    if (not isinstance(bundle_name, str) or not bundle_name or
            not isinstance(application_version, str) or not application_version):
        raise SbomError("AppScope/app.json5 has no release application identity")
    sums = read_go_sums(go_sum)
    requires = {(item["Path"], item["Version"]): item for item in edit.get("Require", [])}
    replacements = {(item["Old"]["Path"], item["Old"].get("Version", "")): item["New"]
                    for item in edit.get("Replace", [])}

    graph_edges: set[tuple[tuple[str, str], tuple[str, str]]] = set()
    graph_nodes: set[tuple[str, str]] = set()
    for line in graph_text.splitlines():
        fields = line.split()
        if len(fields) != 2:
            continue
        source, target = split_module(fields[0]), split_module(fields[1])
        if source[0] == "go" or target[0] == "go" or not source[1] or not target[1]:
            continue
        graph_nodes.update((source, target))
        graph_edges.add((source, target))

    root_module = edit.get("Module", {}).get("Path")
    if not root_module:
        raise SbomError("go.mod has no module path")
    root_ref = generic_ref("harmonyos", bundle_name, application_version)
    components: dict[str, dict[str, Any]] = {}
    scopes: dict[tuple[str, str], set[str]] = {node: {"build"} for node in graph_nodes}
    for key, requirement in requires.items():
        scopes.setdefault(key, set()).add("transitive" if requirement.get("Indirect") else "direct")
    runtime_keys: set[tuple[str, str]] = set()
    for module in build_info["modules"]:
        if module["kind"] == "mod":
            continue
        key = (module["path"], module["version"])
        runtime_keys.add(key)
        scopes.setdefault(key, set()).add("runtime")
        if key not in requires or requires[key].get("Indirect"):
            scopes[key].add("transitive")
        if key not in graph_nodes and key not in requires:
            raise SbomError(f"compiled module is absent from go.mod/module graph: {key[0]}@{key[1]}")
        expected_replacement = replacements.get(key) or replacements.get((key[0], ""))
        actual_replacement = module.get("replacement")
        if bool(expected_replacement) != bool(actual_replacement):
            raise SbomError(f"compiled replacement state differs from go.mod: {key[0]}@{key[1]}")
        if expected_replacement and (
            actual_replacement["path"] != expected_replacement["Path"]
            or actual_replacement.get("version", "") != expected_replacement.get("Version", "")
        ):
            raise SbomError(f"compiled replacement target differs from go.mod: {key[0]}@{key[1]}")
        if module.get("sum") and sums.get(key, {}).get("sum") != module["sum"]:
            raise SbomError(f"compiled module checksum differs from go.sum: {key[0]}@{key[1]}")

    lock_by_module = {
        core_lock["sing_box"].get("module", "github.com/sagernet/sing-box"): core_lock["sing_box"],
        core_lock["gvisor"]["module"]: core_lock["gvisor"],
    }
    if build_info["goVersion"] != core_lock["ohos_go"]["version"]:
        raise SbomError("compiled Go version differs from third_party/core-lock.json")
    for locked_path, locked in lock_by_module.items():
        locked_key = (locked_path, locked["version"])
        if locked_key not in requires or locked_key not in runtime_keys:
            raise SbomError(f"locked native dependency is not present at the exact compiled version: {locked_path}@{locked['version']}")
    for module_path, version in sorted(scopes):
        if module_path == root_module:
            continue
        ref = go_ref(module_path, version)
        prop: dict[str, Any] = {"hna:dependencyScopes": ",".join(sorted(scopes[(module_path, version)]))}
        checksum = sums.get((module_path, version), {})
        hashes: list[dict[str, str]] = []
        if digest := decode_go_sum(checksum.get("sum", "")):
            hashes.append({"alg": "SHA-256", "content": digest})
        if checksum.get("goModSum"):
            prop["hna:goModSum"] = checksum["goModSum"]
        replacement = replacements.get((module_path, version)) or replacements.get((module_path, ""))
        if replacement:
            prop["hna:replacementPath"] = replacement["Path"]
            prop["hna:replacementVersion"] = replacement.get("Version", "local")
        if locked := lock_by_module.get(module_path):
            prop["hna:sourceCommit"] = locked["commit"]
            prop["hna:vendorTreeSha256"] = locked["vendor_tree_sha256"]
            prop["hna:patchSha256"] = locked["patch_sha256"]
            if not hashes:
                hashes.append({"alg": "SHA-256", "content": locked["vendor_tree_sha256"]})
        component: dict[str, Any] = {
            "type": "library", "bom-ref": ref, "group": module_path.rpartition("/")[0],
            "name": module_path.rpartition("/")[2], "version": version,
            "purl": ref, "scope": "required", "properties": properties(prop),
        }
        if hashes:
            component["hashes"] = hashes
        if locked and locked.get("license"):
            component["licenses"] = [{"license": {"id": locked["license"]}}]
        components[ref] = component

    # The OpenHarmony Go fork is a release build input even though it is not a
    # Go module dependency of the application.
    go_lock = core_lock["ohos_go"]
    toolchain_ref = generic_ref("toolchain", "openharmony-go", go_lock["version"])
    components[toolchain_ref] = {
        "type": "framework", "bom-ref": toolchain_ref, "name": "openharmony-go",
        "version": go_lock["version"], "scope": "excluded",
        "hashes": [{"alg": "SHA-256", "content": go_lock["source_tree_sha256"]}],
        "licenses": [{"license": {"id": "BSD-3-Clause"}}],
        "properties": properties({
            "hna:dependencyScopes": "build", "hna:portCommit": go_lock["openharmony_port_commit"],
            "hna:upstreamCommit": go_lock["upstream_go_commit"],
            "hna:replayPatchSha256": go_lock["replay_patch_sha256"],
        }),
    }

    def add_ohpm(lock_path: Path, manifest_path: Path, namespace: str) -> list[str]:
        lock, manifest = load_relaxed_json(lock_path), load_relaxed_json(manifest_path)
        dependency_names = set(manifest.get("dependencies", {}))
        dev_names = set(manifest.get("devDependencies", {}))
        result: list[str] = []
        for package_key, package in sorted(lock.get("packages", {}).items()):
            name, version = package.get("name"), package.get("version")
            if not name or not version:
                raise SbomError(f"OHPM lock package lacks name/version: {lock_path}:{package_key}")
            ref = generic_ref(f"ohpm/{namespace}", name, version)
            scope = "runtime" if name in dependency_names else "build" if name in dev_names else "transitive"
            props = {"hna:dependencyScopes": scope, "hna:registryType": package.get("registryType", "unknown")}
            if package.get("resolved"):
                props["hna:resolved"] = package["resolved"]
            component = {
                "type": "library", "bom-ref": ref, "name": name, "version": version,
                "purl": ref, "scope": "required" if scope == "runtime" else "excluded",
                "properties": properties(props),
            }
            if package.get("integrity"):
                algorithm, _, encoded = package["integrity"].partition("-")
                try:
                    integrity_digest = base64.b64decode(encoded, validate=True).hex()
                except ValueError:
                    integrity_digest = ""
                if algorithm.lower() in {"sha256", "sha384", "sha512"} and integrity_digest:
                    component["hashes"] = [{"alg": algorithm.upper().replace("SHA", "SHA-"), "content": integrity_digest}]
                component["externalReferences"] = [{"type": "distribution", "url": package.get("resolved", "urn:local") ,
                                                     "comment": f"OHPM integrity {package['integrity']}"}]
            components[ref] = component
            result.append(ref)
        return result

    ohpm_refs = add_ohpm(root_ohpm_path, root_manifest_path, "root") + add_ohpm(entry_ohpm_path, entry_manifest_path, "entry")
    # Stripping a Go shared library changes its raw bytes but preserves the Go
    # BuildInfo that proves the compiled dependency graph.  Use that canonical
    # BuildInfo as the SBOM's native-core identity so the preflight can
    # regenerate the exact same SBOM from the signed, packaged (stripped) core.
    # Raw unstripped and packaged core hashes remain separately bound by the
    # signed provenance and release manifest.
    core_build_info_hash = sha256_bytes(canonical(build_info))
    input_hashes = {
        "AppScope/app.json5": sha256_file(app_manifest_path),
        "core/go/go.mod": sha256_file(go_mod), "core/go/go.sum": sha256_file(go_sum),
        "third_party/core-lock.json": sha256_file(core_lock_path),
        "oh-package-lock.json5": sha256_file(root_ohpm_path),
        "entry/oh-package-lock.json5": sha256_file(entry_ohpm_path),
        "coreBuildInfo": core_build_info_hash,
    }
    metadata_props = {f"hna:inputSha256:{key}": value for key, value in input_hashes.items()}
    metadata_props.update({
        "hna:fixtureInput": bool(fixture), "hna:generatorVersion": GENERATOR_VERSION,
        "hna:coreBuildGoVersion": build_info["goVersion"],
        "hna:coreBuildTags": build_info["settings"].get("-tags", ""),
        "hna:coreTarget": f"{build_info['settings']['GOOS']}/{build_info['settings']['GOARCH']}",
    })
    root_component = {
        "type": "application", "bom-ref": root_ref, "name": "HarmonyOS Network Assistant",
        "version": application_version, "licenses": [{"license": {"id": "GPL-3.0-or-later"}}],
        "properties": properties({
            "hna:bundleName": bundle_name,
            "hna:dependencyScopes": "runtime",
            "hna:nativeCoreBuildInfoSha256": core_build_info_hash,
            "hna:nativeCorePath": "entry/libs/arm64-v8a/libharmonycore.so",
        }),
    }
    dependency_map: dict[str, set[str]] = {ref: set() for ref in [root_ref, toolchain_ref, *components]}
    for source, target in graph_edges:
        source_ref = root_ref if source[0] == root_module else go_ref(*source)
        target_ref = go_ref(*target)
        if source_ref in dependency_map and target_ref in components:
            dependency_map[source_ref].add(target_ref)
    for key, requirement in requires.items():
        if not requirement.get("Indirect") and go_ref(*key) in components:
            dependency_map[root_ref].add(go_ref(*key))
    dependency_map[root_ref].update(ohpm_refs)
    dependency_map[root_ref].add(toolchain_ref)

    identity = {"inputs": input_hashes, "components": sorted(components), "dependencies": {key: sorted(value) for key, value in sorted(dependency_map.items())}}
    serial = f"urn:uuid:{uuid.uuid5(SERIAL_NAMESPACE, sha256_bytes(canonical(identity)))}"
    document = {
        "bomFormat": "CycloneDX", "specVersion": "1.6", "serialNumber": serial, "version": 1,
        "metadata": {"component": root_component, "properties": properties(metadata_props),
                     "tools": {"components": [{"type": "application", "name": "generate_release_sbom.py", "version": GENERATOR_VERSION}]}},
        "components": [components[ref] for ref in sorted(components)],
        "dependencies": [{"ref": ref, "dependsOn": sorted(dependency_map[ref])} for ref in sorted(dependency_map)],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(canonical(document))
    print(json.dumps({"output": str(args.output), "sha256": sha256_file(args.output),
                      "serialNumber": serial, "componentCount": len(components) + 1,
                      "fixtureInput": bool(fixture)}, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (SbomError, KeyError, TypeError, ValueError) as error:
        if os.environ.get("HNA_SBOM_DEBUG_TRACE") == "1":
            import traceback
            traceback.print_exc()
        print(f"SBOM_BLOCKED: {error}", file=sys.stderr)
        raise SystemExit(1)
