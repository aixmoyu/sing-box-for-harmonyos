#!/usr/bin/env python3
"""Fail-closed verification and staging for the native core supply chain.

This tool never promotes staged source into ``third_party`` and never builds a
HAP.  Exactly one component is reproduced in a temporary sibling directory and
atomically renamed to an outside-repository candidate path.  A maintainer must
review and separately promote that candidate in a dedicated branch.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from typing import Any, Dict, Iterable, List, Optional


SCRIPT_PATH = Path(__file__).resolve()
PROJECT_ROOT = SCRIPT_PATH.parent.parent
DEFAULT_LOCK = PROJECT_ROOT / "third_party" / "core-lock.json"
TREE_FORMAT = b"HNA-TREE-SHA256-v1\0"
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")


class CoreLockError(RuntimeError):
    pass


def fail(message: str) -> None:
    raise CoreLockError(message)


def run(
    command: List[str],
    *,
    cwd: Optional[Path] = None,
    env: Optional[Dict[str, str]] = None,
) -> str:
    completed = subprocess.run(
        command,
        cwd=str(cwd) if cwd else None,
        env=env,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        fail(f"command failed ({' '.join(command)}): {detail}")
    return completed.stdout.strip()


def load_lock(path: Path) -> Dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read lock {path}: {error}")
    if data.get("schema_version") != 2:
        fail("unsupported core lock schema")
    policy = data.get("delivery_policy", {})
    if policy.get("native_core") != "signed-hap-only":
        fail("native core delivery policy must remain signed-hap-only")
    if policy.get("runtime_core_download") is not False:
        fail("runtime native core download must remain disabled")
    return data


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        fail(f"cannot hash {path}: {error}")
    return digest.hexdigest()


def excluded(relative: Path, prefixes: Iterable[str]) -> bool:
    parts = relative.parts
    if not parts:
        return False
    if ".git" in parts or "__pycache__" in parts or relative.name == ".DS_Store":
        return True
    for prefix in prefixes:
        prefix_parts = Path(prefix).parts
        if parts[: len(prefix_parts)] == prefix_parts:
            return True
    return False


def tree_sha256(root: Path, exclude_prefixes: Iterable[str] = ()) -> str:
    if not root.is_dir():
        fail(f"tree root is missing: {root}")
    paths: List[Path] = []
    for path in root.rglob("*"):
        relative = path.relative_to(root)
        if excluded(relative, exclude_prefixes):
            continue
        if path.is_file() or path.is_symlink():
            paths.append(path)
    paths.sort(key=lambda item: item.relative_to(root).as_posix())

    digest = hashlib.sha256(TREE_FORMAT)
    for path in paths:
        relative = path.relative_to(root).as_posix().encode("utf-8")
        mode = path.lstat().st_mode
        executable = b"x" if mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH) else b"-"
        if path.is_symlink():
            kind = b"l"
            content = os.readlink(path).encode("utf-8")
        else:
            kind = b"f"
            content = bytes.fromhex(sha256_file(path))
        digest.update(kind + b"\0" + executable + b"\0" + relative + b"\0" + content + b"\n")
    return digest.hexdigest()


def project_path(value: str) -> Path:
    path = (PROJECT_ROOT / value).resolve()
    try:
        path.relative_to(PROJECT_ROOT)
    except ValueError:
        fail(f"lock path escapes project root: {value}")
    return path


def lock_relative_path(lock_path: Path, value: str) -> Path:
    path = Path(value)
    if path.is_absolute():
        return path.resolve()
    candidate = (lock_path.parent / path).resolve()
    if candidate.exists():
        return candidate
    # Production locks live in third_party/, while tests commonly copy only the
    # manifest to a temporary directory. Fall back to the project root so a
    # copied lock still verifies the real inputs and only changes its metadata.
    return project_path(value)


def require_hex(value: Any, length: int, label: str) -> str:
    expression = HEX40 if length == 40 else HEX64
    if not isinstance(value, str) or not expression.fullmatch(value):
        fail(f"{label} must be a lowercase {length}-character hex digest")
    return value


def verify_component(name: str, component: Dict[str, Any], lock_path: Path) -> None:
    patch = lock_relative_path(lock_path, component["patch_path"])
    vendor = lock_relative_path(lock_path, component["vendor_path"])
    expected_patch = require_hex(component.get("patch_sha256"), 64, f"{name}.patch_sha256")
    expected_vendor = require_hex(component.get("vendor_tree_sha256"), 64, f"{name}.vendor_tree_sha256")
    actual_patch = sha256_file(patch)
    if actual_patch != expected_patch:
        fail(f"{name} patch drift: expected {expected_patch}, got {actual_patch}")
    actual_vendor = tree_sha256(vendor)
    if actual_vendor != expected_vendor:
        fail(f"{name} vendor drift: expected {expected_vendor}, got {actual_vendor}")


def verify_ohos_go_source(lock: Dict[str, Any], lock_path: Path = DEFAULT_LOCK) -> Path:
    ohos_go = lock["ohos_go"]
    require_hex(ohos_go.get("openharmony_port_commit"), 40, "ohos_go.openharmony_port_commit")
    require_hex(ohos_go.get("openharmony_port_tree"), 40, "ohos_go.openharmony_port_tree")
    require_hex(ohos_go.get("upstream_go_commit"), 40, "ohos_go.upstream_go_commit")
    require_hex(ohos_go.get("upstream_go_tree"), 40, "ohos_go.upstream_go_tree")
    require_hex(
        ohos_go.get("upstream_source_tree_sha256"),
        64,
        "ohos_go.upstream_source_tree_sha256",
    )
    replay_patch = lock_relative_path(lock_path, ohos_go["replay_patch_path"])
    expected_patch = require_hex(
        ohos_go.get("replay_patch_sha256"), 64, "ohos_go.replay_patch_sha256"
    )
    actual_patch = sha256_file(replay_patch)
    if actual_patch != expected_patch:
        fail(f"OHOS Go replay patch drift: expected {expected_patch}, got {actual_patch}")
    ohos_root = lock_relative_path(lock_path, ohos_go["source_path"])
    expected_go_tree = require_hex(ohos_go.get("source_tree_sha256"), 64, "ohos_go.source_tree_sha256")
    actual_go_tree = tree_sha256(ohos_root, ohos_go.get("tree_exclude", []))
    if actual_go_tree != expected_go_tree:
        fail(f"OHOS Go source drift: expected {expected_go_tree}, got {actual_go_tree}")
    version_lines = (ohos_root / "VERSION").read_text(encoding="utf-8").splitlines()
    version_text = version_lines[0].strip() if version_lines else ""
    if version_text != ohos_go["version"]:
        fail(f"OHOS Go VERSION is {version_text}, lock requires {ohos_go['version']}")
    return ohos_root


def copy_tree_filtered(source: Path, destination: Path, excludes: Iterable[str]) -> None:
    exclude_list = tuple(excludes)

    def ignored(directory: str, names: List[str]) -> List[str]:
        directory_path = Path(directory)
        relative_directory = directory_path.relative_to(source)
        return [
            name
            for name in names
            if excluded(relative_directory / name, exclude_list)
        ]

    shutil.copytree(source, destination, symlinks=True, ignore=ignored)


def verify_ohos_go_replay(lock: Dict[str, Any], lock_path: Path = DEFAULT_LOCK) -> None:
    """Prove the checked-in result reverses to the pinned base and replays exactly."""

    ohos_go = lock["ohos_go"]
    result_root = verify_ohos_go_source(lock, lock_path)
    patch = lock_relative_path(lock_path, ohos_go["replay_patch_path"])
    excludes = ohos_go.get("tree_exclude", [])
    expected_base = require_hex(
        ohos_go.get("upstream_source_tree_sha256"),
        64,
        "ohos_go.upstream_source_tree_sha256",
    )
    expected_result = require_hex(
        ohos_go.get("source_tree_sha256"), 64, "ohos_go.source_tree_sha256"
    )

    with tempfile.TemporaryDirectory(prefix="hna-ohos-go-replay-") as temp:
        replay_root = Path(temp) / "source"
        copy_tree_filtered(result_root, replay_root, excludes)
        run(["git", "apply", "--reverse", "--check", str(patch)], cwd=replay_root)
        run(["git", "apply", "--reverse", str(patch)], cwd=replay_root)
        actual_base = tree_sha256(replay_root, excludes)
        if actual_base != expected_base:
            fail(f"OHOS Go replay base drift: expected {expected_base}, got {actual_base}")
        apply_patch(replay_root, patch)
        actual_result = tree_sha256(replay_root, excludes)
        if actual_result != expected_result:
            fail(f"OHOS Go replay result drift: expected {expected_result}, got {actual_result}")


def verify_local(lock: Dict[str, Any], lock_path: Path = DEFAULT_LOCK) -> None:
    sing_box = lock["sing_box"]
    gvisor = lock["gvisor"]
    ohos_go = lock["ohos_go"]

    require_hex(sing_box.get("tag_object"), 40, "sing_box.tag_object")
    require_hex(sing_box.get("commit"), 40, "sing_box.commit")
    require_hex(sing_box.get("upstream_tree"), 40, "sing_box.upstream_tree")
    require_hex(gvisor.get("commit"), 40, "gvisor.commit")

    verify_component("sing-box", sing_box, lock_path)
    verify_component("gVisor", gvisor, lock_path)

    # `verify-local` is the common entry point used by build_core, smoke tests,
    # and formal release builds. Prove the complete reverse-to-base/reapply
    # reconstruction here; reverse applicability alone would not establish that
    # the patch reaches the pinned pristine upstream digest.
    verify_ohos_go_replay(lock, lock_path)
    ohos_root = lock_relative_path(lock_path, ohos_go["source_path"])
    go_binary = ohos_root / "bin" / "go"
    if not go_binary.is_file() or not os.access(go_binary, os.X_OK):
        fail(f"OHOS Go host binary is missing: {go_binary}")
    binary_version = run([str(go_binary), "version"])
    if f"go version {ohos_go['version']} " not in binary_version:
        fail(f"OHOS Go binary version mismatch: {binary_version}")

    go_mod = (PROJECT_ROOT / "core" / "go" / "go.mod").read_text(encoding="utf-8")
    if f"github.com/sagernet/sing-box {sing_box['version']}" not in go_mod:
        fail("core/go/go.mod does not require the locked sing-box version")
    if f"github.com/sagernet/gvisor {gvisor['version']}" not in go_mod:
        fail("core/go/go.mod does not require the locked gVisor version")
    if "replace github.com/sagernet/sing-box => ../../third_party/sing-box" not in go_mod:
        fail("core/go/go.mod does not use the locked sing-box vendor tree")
    if "replace github.com/sagernet/gvisor => ../../third_party/gvisor" not in go_mod:
        fail("core/go/go.mod does not use the locked gVisor vendor tree")


def make_writable(root: Path) -> None:
    for path in [root, *root.rglob("*")]:
        if path.is_symlink():
            continue
        try:
            path.chmod(path.stat().st_mode | stat.S_IWUSR)
        except OSError as error:
            fail(f"cannot make staged source writable ({path}): {error}")


def apply_patch(root: Path, patch: Path) -> None:
    run(["git", "apply", "--check", str(patch)], cwd=root)
    run(["git", "apply", str(patch)], cwd=root)


def validate_tag(label: str, tag: str) -> None:
    if not tag or tag.startswith("-") or ".." in tag:
        fail(f"{label} tag is unsafe: {tag!r}")
    run(["git", "check-ref-format", f"refs/tags/{tag}"])


def checkout_locked_tag(
    *,
    label: str,
    source: str,
    tag: str,
    tag_object: str,
    commit: str,
    tree: str,
    destination: Path,
) -> None:
    expected_tag_object = require_hex(tag_object, 40, f"{label}.tag_object")
    expected_commit = require_hex(commit, 40, f"{label}.commit")
    expected_tree = require_hex(tree, 40, f"{label}.tree")
    validate_tag(label, tag)
    run(["git", "init", "--quiet", str(destination)])
    run(["git", "remote", "add", "origin", source], cwd=destination)
    locked_ref = "refs/tags/hna-locked-upstream"
    run(
        [
            "git",
            "fetch",
            "--quiet",
            "--depth=1",
            "origin",
            f"refs/tags/{tag}:{locked_ref}",
        ],
        cwd=destination,
    )
    identities = {
        "tag object": (run(["git", "rev-parse", locked_ref], cwd=destination), expected_tag_object),
        "commit": (run(["git", "rev-parse", f"{locked_ref}^{{commit}}"], cwd=destination), expected_commit),
        "tree": (run(["git", "rev-parse", f"{locked_ref}^{{tree}}"], cwd=destination), expected_tree),
    }
    for identity, (actual, expected) in identities.items():
        if actual != expected:
            fail(f"{label} {identity} {actual}, expected {expected}")
    run(["git", "checkout", "--quiet", "--detach", expected_commit], cwd=destination)


def stage_sing_box(component: Dict[str, Any], destination: Path, lock_path: Path) -> str:
    checkout_locked_tag(
        label="sing_box",
        source=component["source"],
        tag=component["version"],
        tag_object=component["tag_object"],
        commit=component["commit"],
        tree=component["upstream_tree"],
        destination=destination,
    )
    patch = lock_relative_path(lock_path, component["patch_path"])
    if sha256_file(patch) != require_hex(component.get("patch_sha256"), 64, "sing_box.patch_sha256"):
        fail("sing-box patch changed before staging")
    apply_patch(destination, patch)
    return tree_sha256(destination)


def go_download(module: str, version: str) -> Dict[str, Any]:
    output = run(["go", "mod", "download", "-json", f"{module}@{version}"])
    try:
        return json.loads(output)
    except json.JSONDecodeError as error:
        fail(f"go mod download returned invalid JSON: {error}")


def stage_gvisor(component: Dict[str, Any], destination: Path, lock_path: Path) -> str:
    metadata = go_download(component["module"], component["version"])
    checks = {
        "module sum": (metadata.get("Sum"), component["module_sum"]),
        "go.mod sum": (metadata.get("GoModSum"), component["go_mod_sum"]),
        "origin commit": (metadata.get("Origin", {}).get("Hash"), component["commit"]),
    }
    for label, (actual, expected) in checks.items():
        if actual != expected:
            fail(f"gVisor {label} {actual!r}, expected {expected!r}")
    source_dir = Path(metadata.get("Dir", ""))
    if not source_dir.is_dir():
        fail("gVisor module source directory is unavailable")
    shutil.copytree(source_dir, destination, symlinks=True)
    make_writable(destination)
    patch = lock_relative_path(lock_path, component["patch_path"])
    if sha256_file(patch) != require_hex(component.get("patch_sha256"), 64, "gvisor.patch_sha256"):
        fail("gVisor patch changed before staging")
    apply_patch(destination, patch)
    return tree_sha256(destination)


def stage_ohos_go(component: Dict[str, Any], destination: Path, lock_path: Path) -> str:
    checkout_locked_tag(
        label="ohos_go.upstream",
        source=component["upstream_go_source"],
        tag=component["upstream_go_tag"],
        tag_object=component["upstream_go_tag_object"],
        commit=component["upstream_go_commit"],
        tree=component["upstream_go_tree"],
        destination=destination,
    )
    excludes = component.get("tree_exclude", [])
    expected_base = require_hex(
        component.get("upstream_source_tree_sha256"),
        64,
        "ohos_go.upstream_source_tree_sha256",
    )
    actual_base = tree_sha256(destination, excludes)
    if actual_base != expected_base:
        fail(f"OHOS Go upstream source tree {actual_base}, expected {expected_base}")
    patch = lock_relative_path(lock_path, component["replay_patch_path"])
    expected_patch = require_hex(
        component.get("replay_patch_sha256"), 64, "ohos_go.replay_patch_sha256"
    )
    if sha256_file(patch) != expected_patch:
        fail("OHOS Go replay patch changed before staging")
    apply_patch(destination, patch)
    version_lines = (destination / "VERSION").read_text(encoding="utf-8").splitlines()
    if not version_lines or version_lines[0].strip() != component["version"]:
        fail("OHOS Go replay produced an unexpected VERSION")
    return tree_sha256(destination, excludes)


def validated_stage_output(output: Path) -> Path:
    if output.exists() or output.is_symlink():
        fail(f"stage destination already exists: {output}")
    parent = output.parent.resolve()
    if not parent.is_dir():
        fail(f"stage destination parent must already exist: {parent}")
    candidate = parent / output.name
    project_root = PROJECT_ROOT.resolve()
    if candidate == project_root or project_root in candidate.parents:
        fail(f"stage destination must be outside the repository: {candidate}")
    return candidate


def stage_component(
    lock: Dict[str, Any],
    lock_path: Path,
    name: str,
    output: Path,
    allow_unpinned_result: bool,
) -> None:
    output = validated_stage_output(output)
    specifications = {
        "sing-box": ("sing_box", "vendor_tree_sha256", stage_sing_box),
        "gvisor": ("gvisor", "vendor_tree_sha256", stage_gvisor),
        "ohos-go": ("ohos_go", "source_tree_sha256", stage_ohos_go),
    }
    if name not in specifications:
        fail(f"unsupported stage component: {name}")
    lock_key, digest_key, stage_function = specifications[name]
    component = lock[lock_key]
    temporary = Path(
        tempfile.mkdtemp(prefix=f".{output.name}.stage-", dir=str(output.parent))
    )
    promoted = False
    try:
        source = temporary / "source"
        digest = stage_function(component, source, lock_path)
        expected = require_hex(component.get(digest_key), 64, f"{lock_key}.{digest_key}")
        if digest != expected and not allow_unpinned_result:
            fail(f"staged {name} tree {digest}, expected {expected}")
        report = {
            "component": name,
            "result": "candidate-only" if allow_unpinned_result else "reproduced-locked-component",
            "source_path": "source",
            "source_tree_sha256": digest,
            "expected_tree_sha256": expected,
            "candidate_promotion": "atomic-rename",
            "vendor_promotion_performed": False,
        }
        (temporary / "upgrade-report.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        if output.exists() or output.is_symlink():
            fail(f"stage destination appeared during reproduction: {output}")
        os.rename(temporary, output)
        promoted = True
        print(json.dumps(report, ensure_ascii=False, indent=2))
    finally:
        if not promoted and temporary.exists():
            shutil.rmtree(temporary)


def resolve_git_tag(source: str, version: str, label: str) -> Dict[str, str]:
    validate_tag(label, version)
    with tempfile.TemporaryDirectory(prefix=f"hna-{label}-resolve-") as temp:
        root = Path(temp)
        run(["git", "init", "--quiet", str(root)])
        run(["git", "remote", "add", "origin", source], cwd=root)
        locked_ref = "refs/tags/hna-resolved-upstream"
        run(
            [
                "git",
                "fetch",
                "--quiet",
                "--depth=1",
                "origin",
                f"refs/tags/{version}:{locked_ref}",
            ],
            cwd=root,
        )
        return {
            "version": version,
            "tag_object": run(["git", "rev-parse", locked_ref], cwd=root),
            "commit": run(["git", "rev-parse", f"{locked_ref}^{{commit}}"], cwd=root),
            "upstream_tree": run(["git", "rev-parse", f"{locked_ref}^{{tree}}"], cwd=root),
        }


def resolve_sing_box(source: str, version: str) -> None:
    print(json.dumps(resolve_git_tag(source, version, "sing-box"), indent=2))


def resolve_ohos_go(source: str, version: str) -> None:
    result = resolve_git_tag(source, version, "ohos-go")
    print(json.dumps({
        "version": result["version"],
        "upstream_go_tag_object": result["tag_object"],
        "upstream_go_commit": result["commit"],
        "upstream_go_tree": result["upstream_tree"],
    }, indent=2))


def resolve_gvisor(module: str, version: str) -> None:
    metadata = go_download(module, version)
    print(json.dumps({
        "version": version,
        "commit": metadata.get("Origin", {}).get("Hash"),
        "module_sum": metadata.get("Sum"),
        "go_mod_sum": metadata.get("GoModSum"),
    }, indent=2))


def nested_field(data: Dict[str, Any], name: str) -> Any:
    current: Any = data
    for segment in name.split("."):
        if not isinstance(current, dict) or segment not in current:
            fail(f"unknown lock field: {name}")
        current = current[segment]
    return current


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lock", type=Path, default=DEFAULT_LOCK)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("verify-local", help="verify checked-in source and toolchain against the lock")
    subparsers.add_parser(
        "verify-toolchain-source",
        help="verify the checked-in OHOS Go source before building its ignored host binaries",
    )
    tree_parser = subparsers.add_parser("tree-sha256", help="calculate the canonical source-tree digest")
    tree_parser.add_argument("path", type=Path)
    tree_parser.add_argument("--exclude", action="append", default=[])
    field_parser = subparsers.add_parser("field", help="print one lock field")
    field_parser.add_argument("name")
    stage_parser = subparsers.add_parser(
        "stage-component",
        help="atomically reproduce exactly one component outside the repository",
    )
    stage_parser.add_argument("component", choices=["sing-box", "gvisor", "ohos-go"])
    stage_parser.add_argument("output", type=Path)
    stage_parser.add_argument(
        "--allow-unpinned-result",
        action="store_true",
        help="candidate bootstrap only; still verifies upstream commit/sums and patch SHA",
    )
    resolve_sing = subparsers.add_parser("resolve-sing-box", help="resolve a tag to immutable upstream IDs")
    resolve_sing.add_argument("version")
    resolve_ohos = subparsers.add_parser(
        "resolve-ohos-go", help="resolve an upstream Go tag to immutable IDs"
    )
    resolve_ohos.add_argument("version")
    resolve_gvisor_parser = subparsers.add_parser("resolve-gvisor", help="resolve a module version to immutable IDs")
    resolve_gvisor_parser.add_argument("version")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.command == "tree-sha256":
        print(tree_sha256(args.path.resolve(), args.exclude))
        return 0
    lock = load_lock(args.lock.resolve())
    if args.command == "verify-local":
        verify_local(lock, args.lock.resolve())
        print("CORE LOCK VERIFIED")
    elif args.command == "verify-toolchain-source":
        verify_ohos_go_replay(lock, args.lock.resolve())
        print("OHOS GO SOURCE AND REPLAY VERIFIED")
    elif args.command == "field":
        value = nested_field(lock, args.name)
        if isinstance(value, (dict, list)):
            print(json.dumps(value, ensure_ascii=False))
        else:
            print(value)
    elif args.command == "stage-component":
        stage_component(
            lock,
            args.lock.resolve(),
            args.component,
            args.output,
            args.allow_unpinned_result,
        )
    elif args.command == "resolve-sing-box":
        resolve_sing_box(lock["sing_box"]["source"], args.version)
    elif args.command == "resolve-ohos-go":
        resolve_ohos_go(lock["ohos_go"]["upstream_go_source"], args.version)
    elif args.command == "resolve-gvisor":
        resolve_gvisor(lock["gvisor"]["module"], args.version)
    else:
        fail(f"unhandled command: {args.command}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CoreLockError as error:
        print(f"BLOCKED: {error}", file=sys.stderr)
        raise SystemExit(1)
