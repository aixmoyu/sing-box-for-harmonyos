#!/usr/bin/env bash
set -euo pipefail

# Build and verify a formal HarmonyOS App Pack without ever printing signing
# configuration, passwords, private-key contents, or raw Hvigor logs.
#
# This script does not create certificates and does not convert a debug profile
# into a release profile. DevEco/AGC release signing must already be configured
# in the ignored build-profile.json5 before this command is run.

project_root="$(cd "$(dirname "$0")/.." && pwd)"
release_root="$project_root/artifacts/release"
temporary_paths=""

usage() {
  cat <<'EOF'
Usage: scripts/build_release_app.sh

Required local state:
  - DevEco Studio with the bundled API 26 SDK and signing tools
  - ignored build-profile.json5 with an existing signingConfigs entry
  - default product referencing a signingConfig
  - release build mode and a genuine release provision profile
  - HNA_RELEASE_CERT_SHA256 set to the approved leaf release certificate's
    lowercase SHA-256 fingerprint (DER form; public, not a secret)
  - reviewed public release declarations (none are secrets):
      HNA_OPERATOR_NAME, HNA_PRIVACY_URL, HNA_USER_AGREEMENT_URL,
      HNA_PRIVACY_URL_EN, HNA_USER_AGREEMENT_URL_EN,
      HNA_SUPPORT_URL, HNA_SUPPORT_EMAIL, HNA_CORRESPONDING_SOURCE_URL
  - exact UTF-8 copies of the four approved, already-published policy bodies:
      HNA_PRIVACY_POLICY_ZH, HNA_PRIVACY_POLICY_EN,
      HNA_USER_AGREEMENT_ZH, HNA_USER_AGREEMENT_EN
  - HNA_RELEASE_SECURITY_REPORT pointing to a fresh, trusted Ed25519-signed
    scan report for the deterministic SBOM generated from this exact core
  - HNA_RELEASE_SECURITY_POLICY pointing to the reviewed trust/policy file
    (defaults to security/release-security-policy.json, which intentionally
    contains no trusted release key until one is approved)
  - clean Git worktree and a verified third_party/core-lock.json

Output:
  artifacts/release/<version>-<commit>/

The resulting App Pack, manifest, policies, corresponding source, SBOM and
signed security report are then reviewed out of band. A release approver must
create a detached approval after these bytes are fixed; this build never
creates, signs, or trusts an approval.

The script never creates or modifies signing material. Every HAP inside the
generated .app must pass hap-sign-tool verification with profile type release.
EOF
}

if [[ $# -gt 0 ]]; then
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "BLOCKED: unsupported argument: $1"
      usage
      exit 2
      ;;
  esac
fi

register_temp() {
  temporary_paths="${temporary_paths}$1"$'\n'
}

cleanup() {
  local path=""
  while IFS= read -r path; do
    [[ -n "$path" && -d "$path" ]] || continue
    case "$path" in
      /tmp/hna-release-build.*|/tmp/hna-release-verify.*|/tmp/hna-release-profile.*|"$release_root"/.staging.*)
        find "$path" -depth -delete
        ;;
      *)
        echo "WARN    refused to clean unexpected temporary path"
        ;;
    esac
  done <<< "$temporary_paths"
}
trap cleanup EXIT

fail() {
  printf 'BLOCKED: %s\n' "$1"
  exit 1
}

pass() {
  printf 'PASS    %s\n' "$1"
}

require_public_text() {
  local variable_name="$1" label="$2" value="${!1:-}"
  if [[ -z "$value" ]] || ! python3 - "$value" <<'PY' >/dev/null 2>&1
import re
import sys
value = sys.argv[1]
if len(value) > 200 or any(ord(ch) < 32 for ch in value):
    raise SystemExit(1)
if re.search(r"(?:^|[^a-z0-9])(todo|tbd|placeholder|self-test)(?:[^a-z0-9]|$)", value, re.I):
    raise SystemExit(1)
PY
  then
    fail "$label is missing or still a placeholder ($variable_name)"
  fi
}

require_public_https_url() {
  local variable_name="$1" label="$2" value="${!1:-}"
  if ! python3 - "$value" <<'PY' >/dev/null 2>&1
import ipaddress
import re
import sys
from urllib.parse import urlsplit
value = sys.argv[1]
parsed = urlsplit(value)
if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or parsed.fragment:
    raise SystemExit(1)
try:
    if parsed.port not in (None, 443):
        raise SystemExit(1)
except ValueError:
    raise SystemExit(1)
host = parsed.hostname.rstrip('.').lower()
if any(token in value.lower() for token in ('todo', 'tbd', 'placeholder', '[', ']')):
    raise SystemExit(1)
if host in {'localhost', 'example.com', 'example.org', 'example.net'} or host.endswith(('.localhost', '.local', '.invalid', '.test', '.example')):
    raise SystemExit(1)
try:
    if not ipaddress.ip_address(host).is_global:
        raise SystemExit(1)
except ValueError:
    labels = host.split('.')
    if len(labels) < 2 or any(not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', label) for label in labels):
        raise SystemExit(1)
PY
  then
    fail "$label must be a non-placeholder HTTPS URL ($variable_name)"
  fi
}

require_public_email() {
  local value="${HNA_SUPPORT_EMAIL:-}"
  if ! python3 - "$value" <<'PY' >/dev/null 2>&1
import re
import sys
value = sys.argv[1].strip()
if any(token in value.lower() for token in ('todo', 'tbd', 'placeholder', 'example.com', 'example.org', 'example.net')):
    raise SystemExit(1)
if not re.fullmatch(r"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+", value):
    raise SystemExit(1)
PY
  then
    fail "valid support email is missing (HNA_SUPPORT_EMAIL)"
  fi
}

deveco_app="${HNA_DEVECO_HOME:-}"
if [[ -z "$deveco_app" ]]; then
  for candidate in \
    "/Applications/DevEco-Studio.app" \
    "/Applications/DevEco Studio.app" \
    "$HOME/Applications/DevEco-Studio.app" \
    "$HOME/Applications/DevEco Studio.app"; do
    if [[ -d "$candidate" ]]; then
      deveco_app="$candidate"
      break
    fi
  done
fi

[[ -d "$deveco_app/Contents" ]] || fail "DevEco Studio was not found"
deveco_contents="$deveco_app/Contents"
node_bin="$deveco_contents/tools/node/bin/node"
ohpm_bin="$deveco_contents/tools/ohpm/bin/ohpm"
hvigor_bin="$deveco_contents/tools/hvigor/bin/hvigorw"
java_bin="$deveco_contents/jbr/Contents/Home/bin/java"
sdk_root="$deveco_contents/sdk/default"
sign_tool="$sdk_root/openharmony/toolchains/lib/hap-sign-tool.jar"
json5_module="$deveco_contents/tools/hvigor/hvigor-ohos-plugin/node_modules/json5"

for required_executable in "$node_bin" "$ohpm_bin" "$hvigor_bin" "$java_bin"; do
  [[ -x "$required_executable" ]] || fail "a required bundled DevEco executable is missing"
done
unpacking_tool="$sdk_root/openharmony/toolchains/lib/app_unpacking_tool.jar"
for required_file in "$sign_tool" "$unpacking_tool" "$json5_module/package.json" "$sdk_root/sdk-pkg.json"; do
  [[ -f "$required_file" ]] || fail "a required bundled DevEco SDK component is missing"
done
for required_command in git go tar unzip zipinfo shasum stat awk sed grep find file openssl python3; do
  command -v "$required_command" >/dev/null 2>&1 || fail "required host command is missing: $required_command"
done
sdk_metadata="$($node_bin - "$sdk_root/sdk-pkg.json" <<'NODE'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const parsed = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const data = parsed && parsed.data;
if (!data || Number(data.apiVersion) !== 26 || typeof data.version !== 'string') {
  process.exit(2);
}
process.stdout.write(`${data.apiVersion}\t${data.version}\t${data.releaseType || 'unknown'}`);
NODE
)" || fail "the bundled HarmonyOS SDK is not API 26"
IFS=$'\t' read -r sdk_api sdk_version sdk_release_type <<< "$sdk_metadata"
pass "DevEco bundled build/signing tools and API $sdk_api SDK are present"
case "$sdk_release_type" in
  Release|release) ;;
  *) fail "formal AppGallery builds require an official Release SDK; prerelease SDK metadata is not publishable" ;;
esac
pass "HarmonyOS SDK release channel is official Release"

if [[ -n "${HNA_GOROOT_BOOTSTRAP:-}" ]]; then
  bootstrap_root="$HNA_GOROOT_BOOTSTRAP"
else
  bootstrap_root="$(go env GOROOT 2>/dev/null || true)"
fi
[[ -n "$bootstrap_root" ]] || fail "bootstrap Go root could not be resolved"
if ! python3 "$project_root/scripts/verify_build_toolchain.py" all \
    --goroot "$bootstrap_root" --contents "$deveco_contents" >/dev/null 2>&1; then
  fail "bootstrap Go or DevEco/SDK build inputs differ from the reviewed toolchain lock"
fi
pass "bootstrap Go and DevEco/SDK build inputs match the reviewed hashes"

build_profile="$project_root/build-profile.json5"
[[ -f "$build_profile" ]] || fail "build-profile.json5 is missing; configure release signing in DevEco Studio"

# Parse JSON5 with DevEco's bundled parser, but never print it.  A separate
# fail-closed verifier reduces the result to reviewed semantics and hashes of
# the public certificate/profile bytes. Passwords, aliases and local paths are
# neither printed nor included in the recorded digest.
profile_verify_root="$(mktemp -d /tmp/hna-release-profile.XXXXXX)"
register_temp "$profile_verify_root"
parsed_build_profile="$profile_verify_root/build-profile.json"
if ! "$node_bin" - "$build_profile" "$json5_module" "$parsed_build_profile" <<'NODE' >/dev/null 2>&1
const fs = require('fs');
const JSON5 = require(process.argv[3]);
const parsed = JSON5.parse(fs.readFileSync(process.argv[2], 'utf8'));
fs.writeFileSync(process.argv[4], JSON.stringify(parsed));
NODE
then
  fail "build-profile.json5 is not valid JSON5"
fi
profile_verification="$profile_verify_root/verification.json"
if ! python3 "$project_root/scripts/verify_release_package.py" build-profile \
    --parsed-build-profile "$parsed_build_profile" \
    --build-profile-dir "$(dirname "$build_profile")" > "$profile_verification" 2>/dev/null; then
  fail "release build/signing configuration is not the exact reviewed semantic shape"
fi
redacted_build_profile_sha="$(python3 - "$profile_verification" <<'PY'
import json, pathlib, re, sys
value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")).get("redactedBuildProfileSha256")
if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value):
    raise SystemExit(1)
print(value)
PY
)" || fail "redacted build-profile digest could not be computed"
profile_path="$(python3 - "$parsed_build_profile" <<'PY'
import json, pathlib, sys
value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))["app"]["signingConfigs"][0]["material"]["profile"]
if not isinstance(value, str) or not value:
    raise SystemExit(1)
print(value)
PY
)" || fail "release provision profile path is missing"
case "$profile_path" in
  /*) ;;
  *) profile_path="$(dirname "$build_profile")/$profile_path" ;;
esac
profile_result="$profile_verify_root/profile-result.json"
if ! "$java_bin" -jar "$sign_tool" verify-profile -inFile "$profile_path" \
    -outFile "$profile_result" >/dev/null 2>&1; then
  fail "HarmonyOS signing tool rejected the release provision profile"
fi
expected_profile_bundle="$($node_bin - "$project_root/AppScope/app.json5" "$json5_module" <<'NODE'
const fs = require('fs');
const JSON5 = require(process.argv[3]);
const value = JSON5.parse(fs.readFileSync(process.argv[2], 'utf8')).app?.bundleName;
if (typeof value !== 'string' || !value) process.exit(2);
process.stdout.write(value);
NODE
)" || fail "repository bundle name could not be parsed"
if ! python3 - "$profile_result" "$expected_profile_bundle" <<'PY' >/dev/null 2>&1
import json, pathlib, sys, time
result = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
content = result.get("content", {})
validity = content.get("validity", {})
if result.get("verifiedPassed") is not True or content.get("type") != "release":
    raise SystemExit(1)
if content.get("bundle-info", {}).get("bundle-name") != sys.argv[2]:
    raise SystemExit(1)
if not isinstance(validity.get("not-before"), int) or not isinstance(validity.get("not-after"), int):
    raise SystemExit(1)
if not validity["not-before"] <= int(time.time()) < validity["not-after"]:
    raise SystemExit(1)
if content.get("debug-info") not in (None, {}):
    raise SystemExit(1)
PY
then
  fail "provision profile is not a current release profile for this bundle"
fi
rm -f "$parsed_build_profile" "$profile_result"
pass "release build/signing semantics are verified and reduced to a redacted digest"

expected_release_cert_sha="${HNA_RELEASE_CERT_SHA256:-}"
if [[ ! "$expected_release_cert_sha" =~ ^[0-9a-f]{64}$ ]]; then
  fail "HNA_RELEASE_CERT_SHA256 must contain the approved lowercase leaf release certificate SHA-256"
fi
pass "approved release certificate fingerprint is declared"

cd "$project_root"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "project is not a Git worktree"
[[ -z "$(git status --porcelain)" ]] || fail "Git worktree is dirty; commit reviewed source before a formal release build"
git_commit="$(git rev-parse HEAD)"
short_commit="$(git rev-parse --short=12 HEAD)"
[[ "$git_commit" =~ ^[0-9a-f]{40}$ ]] || fail "Git commit could not be resolved"
pass "source tree is clean at commit $short_commit"

core_build_root="$(mktemp -d /tmp/hna-release-build.XXXXXX)"
register_temp "$core_build_root"
git archive --format=tar "$git_commit" | tar -x -C "$core_build_root"
app_json="$core_build_root/AppScope/app.json5"
core_lock="$core_build_root/third_party/core-lock.json"
build_toolchain_lock="$core_build_root/third_party/build-toolchain-lock.json"
[[ -f "$app_json" && -f "$core_lock" && -f "$build_toolchain_lock" ]] ||
  fail "app metadata, core lock, or build toolchain lock is missing from the Git commit archive"
pass "native build inputs come from the immutable Git commit archive"

# core/go/out and the host OHOS Go binaries are intentionally ignored and
# therefore cannot be trusted merely because the Git tree is clean. Rebuild
# the locked host toolchain first. build_ohos_go verifies the checked-in source
# and patch lock before make.bash, then runs the complete local verifier after
# the ignored bin/go exists. This order also works in a true clean checkout.
[[ -x "$core_build_root/scripts/verify_core_vendor.sh" ]] || fail "core vendor verification script is missing"
if ! "$core_build_root/scripts/build_ohos_go.sh" >/dev/null 2>&1; then
  fail "locked OpenHarmony Go host toolchain rebuild failed"
fi
ohos_go_bin="$core_build_root/third_party/ohos-golang-go-1.24/bin/go"
[[ -x "$ohos_go_bin" ]] || fail "OpenHarmony Go rebuild produced no host compiler"
ohos_go_version="$($ohos_go_bin version 2>/dev/null | awk '{print $3}')"
expected_ohos_go_version="$("$node_bin" - "$core_lock" <<'NODE'
const fs = require('fs');
const lock = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (!lock.ohos_go || typeof lock.ohos_go.version !== 'string') process.exit(2);
process.stdout.write(lock.ohos_go.version);
NODE
)" || fail "OHOS Go version is missing from core lock"
[[ "$ohos_go_version" == "$expected_ohos_go_version" ]] ||
  fail "rebuilt OpenHarmony Go host compiler version differs from core lock"
bootstrap_go_version="$(if [[ -n "${HNA_GOROOT_BOOTSTRAP:-}" ]]; then \
  "${HNA_GOROOT_BOOTSTRAP}/bin/go" version; else go version; fi 2>/dev/null | awk '{print $3}')"
[[ "$bootstrap_go_version" =~ ^go[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] ||
  fail "bootstrap Go version could not be recorded"
pass "locked OpenHarmony Go host toolchain was freshly rebuilt"

if ! "$core_build_root/scripts/verify_core_vendor.sh" >/dev/null 2>&1; then
  fail "sing-box vendor tree does not match third_party/core-lock.json"
fi
pass "sing-box source, patch lock, and rebuilt toolchain are verified"

if ! "$core_build_root/scripts/core_smoke_test.sh" >/dev/null 2>&1; then
  fail "HarmonyOS sing-box/gVisor adaptation smoke tests failed"
fi
pass "HarmonyOS native-core adaptation smoke tests pass"

# Rebuild the native core from the just-verified locked source.
if ! "$core_build_root/scripts/build_core.sh" >/dev/null 2>&1; then
  fail "locked OpenHarmony native core rebuild failed"
fi
built_core="$core_build_root/core/go/out/libharmonycore.so"
[[ -f "$built_core" ]] || fail "native core rebuild produced no shared library"
if ! file "$built_core" | grep -Eq 'ELF 64-bit.*ARM aarch64|ELF 64-bit.*ARM64'; then
  fail "rebuilt native core is not an ARM64 OpenHarmony shared library"
fi
built_core_sha="$(shasum -a 256 "$built_core" | awk '{print $1}')"
[[ "$built_core_sha" =~ ^[0-9a-f]{64}$ ]] || fail "rebuilt native core digest is invalid"
pass "ARM64 native core was freshly rebuilt from the locked source"

if [[ "$(git -C "$project_root" rev-parse HEAD)" != "$git_commit" ]] ||
  ! git -C "$project_root" diff --quiet ||
  ! git -C "$project_root" diff --cached --quiet ||
  [[ -n "$(git -C "$project_root" ls-files --others --exclude-standard)" ]]; then
  fail "source worktree or HEAD changed while the isolated native core was building"
fi
pass "source HEAD remained unchanged while the isolated core was built"

core_lock_sha="$(shasum -a 256 "$core_lock" | awk '{print $1}')"
[[ "$core_lock_sha" =~ ^[0-9a-f]{64}$ ]] || fail "core lock digest is invalid"
build_toolchain_lock_sha="$(shasum -a 256 "$build_toolchain_lock" | awk '{print $1}')"
[[ "$build_toolchain_lock_sha" =~ ^[0-9a-f]{64}$ ]] ||
  fail "build toolchain lock digest is invalid"

sing_box_version="$($node_bin - "$core_lock" <<'NODE'
const fs = require('fs');
const lock = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const core = lock && lock.sing_box;
const sha256 = /^[0-9a-f]{64}$/;
const commit = /^[0-9a-f]{40}$/;
if (!core || typeof core.version !== 'string' || !commit.test(core.commit) ||
    !sha256.test(core.vendor_tree_sha256) || !sha256.test(core.patch_sha256)) {
  process.exit(2);
}
process.stdout.write(core.version);
NODE
)" || fail "third_party/core-lock.json has incomplete sing-box provenance"
pass "release manifest provenance is locked to sing-box $sing_box_version"

app_metadata="$($node_bin - "$app_json" "$json5_module" <<'NODE'
const fs = require('fs');
const JSON5 = require(process.argv[3]);
const parsed = JSON5.parse(fs.readFileSync(process.argv[2], 'utf8'));
const app = parsed && parsed.app;
if (!app || typeof app.bundleName !== 'string' ||
    typeof app.versionName !== 'string' || !Number.isInteger(app.versionCode)) {
  process.exit(2);
}
if (!/^[A-Za-z0-9._-]+$/.test(app.bundleName) ||
    !/^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?$/.test(app.versionName) ||
    app.versionCode < 1) {
  process.exit(3);
}
process.stdout.write(`${app.bundleName}\t${app.versionName}\t${app.versionCode}`);
NODE
)" || fail "AppScope/app.json5 has invalid release metadata"
IFS=$'\t' read -r bundle_name version_name version_code <<< "$app_metadata"
[[ -n "$bundle_name" && -n "$version_name" && -n "$version_code" ]] || fail "release metadata is incomplete"
pass "application metadata is $bundle_name $version_name ($version_code)"

# Public store/contact declarations are compiled only into the isolated release
# source. They are deliberately required here rather than inherited from a
# debug source file, so a formal package cannot ship blank or placeholder
# links. Reachability is checked again by release_preflight.sh.
require_public_text HNA_OPERATOR_NAME "release operator name"
require_public_https_url HNA_PRIVACY_URL "privacy policy"
require_public_https_url HNA_PRIVACY_URL_EN "English privacy policy"
require_public_https_url HNA_USER_AGREEMENT_URL "user agreement"
require_public_https_url HNA_USER_AGREEMENT_URL_EN "English user agreement"
require_public_https_url HNA_SUPPORT_URL "support site"
require_public_https_url HNA_CORRESPONDING_SOURCE_URL "GPL corresponding source"
require_public_email
if ! python3 - "${HNA_CORRESPONDING_SOURCE_URL}" "$git_commit" "$version_name" <<'PY' >/dev/null 2>&1
import re
import sys
from urllib.parse import urlsplit

url, commit, version = sys.argv[1:]
if commit in url:
    raise SystemExit(0)
path_query = urlsplit(url).path + '?' + urlsplit(url).query
escaped = re.escape(version)
tag = rf'(?:^|/)(?:tag|tags)/(?:v)?{escaped}(?:$|[/?#])'
archive = rf'(?:^|/)(?:archive/)?(?:refs/)?tags/(?:v)?{escaped}(?:$|[/?#.])'
query = rf'(?:[?&](?:ref|tag|version)=)(?:v)?{escaped}(?:$|&)'
if not (re.search(tag, path_query) or re.search(archive, path_query) or re.search(query, path_query)):
    raise SystemExit(1)
PY
then
  fail "GPL corresponding source URL must contain this full Git commit or a version tag"
fi
pass "public operator, legal, support, and exact-source declarations are complete"

# A release always builds from the exact committed Git HEAD archive, never by
# copying the worktree. This excludes ignored signing keys, private profiles,
# generated files and any unexpected local paths by construction.
verify_root="$(mktemp -d /tmp/hna-release-verify.XXXXXX)"
register_temp "$verify_root"
build_root="$(mktemp -d /tmp/hna-release-build.XXXXXX)"
register_temp "$build_root"
git archive --format=tar "$git_commit" | tar -x -C "$build_root"
[[ ! -e "$build_root/.git" ]] || fail "isolated release source must not contain Git metadata"
if find "$build_root" -type d \( -name '.signing' -o -name 'signing-private' \) -print -quit | grep -q .; then
  fail "isolated release source unexpectedly contains signing material"
fi

# Bind the signed package to the exact approved bytes already served at every
# language-specific policy URL. The verifier pins each DNS resolution to public
# addresses, follows HTTPS-only redirects, enforces MIME/size limits, and
# compares the downloaded body byte-for-byte with the local approved copy.
policy_bindings="$verify_root/policy-bindings.json"
if ! python3 "$build_root/scripts/release_content_gate.py" verify-policies \
    --privacy-zh-file "${HNA_PRIVACY_POLICY_ZH:-}" --privacy-zh-url "$HNA_PRIVACY_URL" \
    --privacy-en-file "${HNA_PRIVACY_POLICY_EN:-}" --privacy-en-url "$HNA_PRIVACY_URL_EN" \
    --agreement-zh-file "${HNA_USER_AGREEMENT_ZH:-}" --agreement-zh-url "$HNA_USER_AGREEMENT_URL" \
    --agreement-en-file "${HNA_USER_AGREEMENT_EN:-}" --agreement-en-url "$HNA_USER_AGREEMENT_URL_EN" \
    > "$policy_bindings" 2>/dev/null; then
  fail "published policy bodies do not exactly match the four reviewed local UTF-8 documents"
fi
pass "Chinese/English privacy policies and user agreements exactly match their published HTTPS bodies"

# The GPL corresponding source is generated deterministically from the same
# immutable commit used for the application build. It includes all tracked app
# source, vendored sing-box/gVisor/OHOS-Go source, patches, locks, build scripts,
# and licenses, while excluding ignored signing material. Formal packaging is
# blocked until the declared public URL serves these exact archive bytes.
source_artifact_name="HarmonyOS-Network-Assistant-source-${version_name}-${git_commit}.tar.gz"
source_archive="$verify_root/$source_artifact_name"
source_local_metadata="$verify_root/source-local.json"
source_published_metadata="$verify_root/source-published.json"
source_binding="$verify_root/source-binding.json"
if ! python3 "$build_root/scripts/release_content_gate.py" create-source \
    --repo "$project_root" --commit "$git_commit" --version "$version_name" \
    --output "$source_archive" > "$source_local_metadata" 2>/dev/null; then
  fail "deterministic complete corresponding-source archive could not be generated"
fi
if ! python3 "$build_root/scripts/release_content_gate.py" verify-url \
    --kind source --url "$HNA_CORRESPONDING_SOURCE_URL" \
    --expected-file "$source_archive" > "$source_published_metadata" 2>/dev/null; then
  fail "published GPL corresponding source is not the exact deterministic archive for this commit"
fi
python3 - "$source_local_metadata" "$source_published_metadata" \
  "$HNA_CORRESPONDING_SOURCE_URL" "$source_binding" <<'PY'
import json
import pathlib
import sys

local = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
published = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
if local.get("sha256") != published.get("sha256") or local.get("sizeBytes") != published.get("sizeBytes"):
    raise SystemExit("published corresponding source differs from deterministic archive")
binding = {
    "file": local["file"],
    "url": sys.argv[3],
    "resolvedUrl": published["resolvedUrl"],
    "redirectCount": published["redirectCount"],
    "sha256": local["sha256"],
    "sizeBytes": local["sizeBytes"],
    "contentType": published["contentType"],
    "format": local["format"],
}
pathlib.Path(sys.argv[4]).write_text(
    json.dumps(binding, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
PY
pass "public GPL source URL serves the deterministic complete source archive for this commit"

# Record every Git-tracked archive input before release metadata or build tools
# can touch it. The post-build verifier compares these bytes again and also
# asks Git to report any non-ignored new source file. Only the generated public
# release configuration and signed raw resources are permitted differences.
tracked_path_list="$verify_root/tracked-paths.z"
tracked_source_snapshot="$verify_root/tracked-source-sha256.json"
git ls-tree -rz --name-only "$git_commit" > "$tracked_path_list"
python3 - "$build_root" "$tracked_path_list" "$tracked_source_snapshot" <<'PY'
import hashlib
import json
import os
import pathlib
import sys

root = pathlib.Path(sys.argv[1]).resolve()
path_list = pathlib.Path(sys.argv[2]).read_bytes().split(b"\0")
output = pathlib.Path(sys.argv[3])
snapshot = []
for raw_path in path_list:
    if not raw_path:
        continue
    relative = os.fsdecode(raw_path)
    pure = pathlib.PurePosixPath(relative)
    if pure.is_absolute() or ".." in pure.parts:
        raise SystemExit("unsafe tracked archive path")
    path = root / relative
    if path.is_symlink():
        kind = "symlink"
        payload = os.readlink(path).encode("utf-8", "surrogateescape")
    elif path.is_file():
        kind = "file"
        payload = path.read_bytes()
    else:
        raise SystemExit("tracked archive input is missing or unsupported")
    snapshot.append({
        "path": relative,
        "kind": kind,
        "sha256": hashlib.sha256(payload).hexdigest(),
    })
output.write_text(json.dumps(snapshot, sort_keys=True, separators=(",", ":")), encoding="utf-8")
PY
pass "Git HEAD archive inputs were snapshotted before release injection"

# The only local inputs injected after archiving are the ignored build profile
# and the toolchain/core outputs rebuilt above. Signing keys remain outside the
# archive and are referenced by the operator's local release profile.
cp "$build_profile" "$build_root/build-profile.json5"
ohos_go_root="$core_build_root/third_party/ohos-golang-go-1.24"
for toolchain_output in bin pkg; do
  [[ -d "$ohos_go_root/$toolchain_output" ]] ||
    fail "fresh OpenHarmony Go output is missing: $toolchain_output"
  mkdir -p "$build_root/third_party/ohos-golang-go-1.24"
  cp -a "$ohos_go_root/$toolchain_output" \
    "$build_root/third_party/ohos-golang-go-1.24/$toolchain_output"
done
mkdir -p "$build_root/core/go"
cp -a "$core_build_root/core/go/out" "$build_root/core/go/out"
[[ -f "$build_root/core/go/out/libharmonycore.so" ]] ||
  fail "isolated release source did not receive the freshly rebuilt native core"
pass "using a Git HEAD archive with an explicit local-input allowlist"

# Generate the SBOM from the exact clean source graph and the freshly rebuilt
# ARM64 core BuildInfo. A separately produced scanner report is snapshotted and
# must carry a trusted Ed25519 signature covering these exact SBOM bytes. The
# repository default policy has no trusted keys, so a formal build remains
# blocked until the release owner supplies an explicitly reviewed policy/key.
sbom_artifact_name="HarmonyOS-Network-Assistant-${version_name}-${short_commit}.cdx.json"
security_report_artifact_name="HarmonyOS-Network-Assistant-${version_name}-${short_commit}.security-report.json"
security_policy_artifact_name="HarmonyOS-Network-Assistant-${version_name}-${short_commit}.security-policy.json"
security_verification_artifact_name="HarmonyOS-Network-Assistant-${version_name}-${short_commit}.security-verification.json"
sbom_path="$verify_root/$sbom_artifact_name"
security_report_source="${HNA_RELEASE_SECURITY_REPORT:-}"
security_policy="${HNA_RELEASE_SECURITY_POLICY:-$project_root/security/release-security-policy.json}"
[[ -s "$security_report_source" ]] || fail "HNA_RELEASE_SECURITY_REPORT must name a non-empty signed scan report"
[[ -s "$security_policy" ]] || fail "reviewed release security policy is missing"
security_report_snapshot="$verify_root/$security_report_artifact_name"
security_policy_snapshot="$verify_root/$security_policy_artifact_name"
security_verification="$verify_root/$security_verification_artifact_name"
cp "$security_report_source" "$security_report_snapshot"
cp "$security_policy" "$security_policy_snapshot"
if ! python3 "$build_root/scripts/generate_release_sbom.py" \
    --repo "$build_root" --core-binary "$build_root/core/go/out/libharmonycore.so" \
    --output "$sbom_path" >/dev/null 2>&1; then
  fail "deterministic release SBOM generation failed"
fi
if ! python3 "$build_root/scripts/verify_release_security.py" \
    --sbom "$sbom_path" --security-report "$security_report_snapshot" \
    --policy "$security_policy_snapshot" >"$security_verification" 2>/dev/null; then
  fail "signed vulnerability/license report does not cover the exact release SBOM"
fi
[[ -s "$security_verification" ]] || fail "release security verifier produced no evidence record"
security_binding="$verify_root/security-binding.json"
python3 - "$sbom_path" "$security_report_snapshot" "$security_policy_snapshot" \
  "$security_verification" "$security_binding" <<'PY'
import hashlib
import json
import pathlib
import sys

def item(path_text: str, format_name: str) -> dict[str, object]:
    path = pathlib.Path(path_text)
    payload = path.read_bytes()
    if not payload:
        raise SystemExit("empty release security evidence")
    return {
        "file": path.name,
        "sha256": hashlib.sha256(payload).hexdigest(),
        "sizeBytes": len(payload),
        "format": format_name,
    }

binding = {
    "schemaVersion": 1,
    "sbom": item(sys.argv[1], "cyclonedx-json-1.6"),
    "report": item(sys.argv[2], "hna-release-security-scan-v1"),
    "policy": item(sys.argv[3], "hna-release-security-policy-v1"),
    "verification": item(sys.argv[4], "hna-release-security-verification-v1"),
}
pathlib.Path(sys.argv[5]).write_text(
    json.dumps(binding, sort_keys=True, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
PY
pass "deterministic SBOM and trusted signed security report are bound to this release"

provenance_relative="entry/src/main/resources/rawfile/hna_release_provenance.json"
provenance_source="$project_root/$provenance_relative"
[[ ! -e "$provenance_source" ]] || fail "reserved release provenance resource already exists in the source tree"
release_rawfile_dir="$build_root/entry/src/main/resources/rawfile"
mkdir -p "$release_rawfile_dir"
release_config="$build_root/entry/src/main/ets/ui/ReleaseConfig.ts"
[[ -f "$release_config" ]] || fail "tracked ReleaseConfig.ts is missing from Git HEAD archive"
"$node_bin" - "$build_root/$provenance_relative" "$release_config" "$git_commit" "$core_lock" \
  "$build_root" "$core_lock_sha" "$build_toolchain_lock_sha" "$source_binding" "$policy_bindings" "$security_binding" \
  "$bundle_name" "$version_name" "$version_code" \
  "$built_core_sha" "$expected_release_cert_sha" "$redacted_build_profile_sha" \
  "$HNA_OPERATOR_NAME" "$HNA_PRIVACY_URL" "$HNA_PRIVACY_URL_EN" \
  "$HNA_USER_AGREEMENT_URL" "$HNA_USER_AGREEMENT_URL_EN" \
  "$HNA_SUPPORT_URL" "$HNA_SUPPORT_EMAIL" "$HNA_CORRESPONDING_SOURCE_URL" <<'NODE'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const [outputPath, releaseConfigPath, gitCommit, coreLockPath, sourceRoot, coreLockSha256,
  buildToolchainLockSha256, sourceBindingPath, policyBindingsPath, securityBindingPath,
  bundleName, versionName, versionCodeText, builtCoreSha256,
  releaseCertSha256, buildProfileRedactedSha256,
  operatorName, privacyUrl, privacyUrlEn, userAgreementUrl, userAgreementUrlEn,
  supportUrl, supportEmail, correspondingSourceUrl] = process.argv.slice(2);
const lock = JSON.parse(fs.readFileSync(coreLockPath, 'utf8'));
const correspondingArchive = JSON.parse(fs.readFileSync(sourceBindingPath, 'utf8'));
const policyBindings = JSON.parse(fs.readFileSync(policyBindingsPath, 'utf8'));
const securityEvidence = JSON.parse(fs.readFileSync(securityBindingPath, 'utf8'));
if (policyBindings.schemaVersion !== 1 || !Array.isArray(policyBindings.documents) ||
    policyBindings.documents.length !== 4) {
  throw new Error('invalid reviewed policy bindings');
}
const distributionLicenses = [
  ['hna_gpl_v3.txt', 'LICENSE'],
  ['hna_third_party_notices.md', 'THIRD_PARTY_NOTICES.md'],
  ['hna_sing_box_gpl_v3.txt', 'third_party/sing-box/LICENSE'],
  ['hna_gvisor_apache2.txt', 'third_party/gvisor/LICENSE'],
  ['hna_go_license.txt', 'third_party/ohos-golang-go-1.24/LICENSE'],
  ['hna_go_patents.txt', 'third_party/ohos-golang-go-1.24/PATENTS'],
].map(([resource, sourcePath]) => ({
  resource,
  sourcePath,
  sha256: crypto.createHash('sha256').update(fs.readFileSync(path.join(sourceRoot, sourcePath))).digest('hex'),
}));
const publicInfo = {
  operatorName,
  privacyUrl,
  privacyUrlEn,
  userAgreementUrl,
  userAgreementUrlEn,
  supportUrl,
  supportEmail,
  correspondingSourceUrl,
};
const provenance = {
  schemaVersion: 1,
  source: { gitCommit, treeClean: true, correspondingArchive },
  application: {
    bundleName,
    versionName,
    versionCode: Number(versionCodeText),
    targetApi: 26,
  },
  nativeCore: {
    delivery: 'signed-app-update-only',
    runtimeCodeDownload: false,
    coreLockSha256,
    singBoxVersion: lock.sing_box.version,
    singBoxCommit: lock.sing_box.commit,
    vendorTreeSha256: lock.sing_box.vendor_tree_sha256,
    patchSha256: lock.sing_box.patch_sha256,
    freshlyBuiltUnstrippedSha256: builtCoreSha256,
  },
  signing: {
    approvedLeafCertificateSha256: releaseCertSha256,
    buildProfileRedactedSha256,
  },
  buildInputs: { buildToolchainLockSha256 },
  publicInfo,
  policyDocuments: policyBindings.documents,
  securityEvidence,
  distributionLicenses,
};
fs.writeFileSync(outputPath, `${JSON.stringify(provenance, null, 2)}\n`, {
  encoding: 'utf8',
  mode: 0o444,
});
const config = `/** Generated only inside a signed formal release build. */\n` +
  `export interface ReleasePublicInfo {\n` +
  `  operatorName: string\n  privacyUrl: string\n  privacyUrlEn: string\n` +
  `  userAgreementUrl: string\n  userAgreementUrlEn: string\n` +
  `  supportUrl: string\n  supportEmail: string\n  correspondingSourceUrl: string\n}\n\n` +
  `export const RELEASE_PUBLIC_INFO: ReleasePublicInfo = ${JSON.stringify(publicInfo, null, 2)}\n`;
fs.writeFileSync(releaseConfigPath, config, { encoding: 'utf8', mode: 0o444 });
NODE
embedded_provenance_sha="$(shasum -a 256 "$build_root/$provenance_relative" | awk '{print $1}')"
[[ "$embedded_provenance_sha" =~ ^[0-9a-f]{64}$ ]] || fail "embedded provenance digest is invalid"
pass "signed-package provenance resource was generated from the clean source and core lock"

# Bundle the exact distribution licenses/notices as signed raw resources. The
# UI also exposes these texts, while the raw copies make package-level audit
# independent from ArkTS bytecode inspection.
cp "$build_root/LICENSE" "$release_rawfile_dir/hna_gpl_v3.txt"
cp "$build_root/THIRD_PARTY_NOTICES.md" "$release_rawfile_dir/hna_third_party_notices.md"
cp "$build_root/third_party/sing-box/LICENSE" "$release_rawfile_dir/hna_sing_box_gpl_v3.txt"
cp "$build_root/third_party/gvisor/LICENSE" "$release_rawfile_dir/hna_gvisor_apache2.txt"
cp "$build_root/third_party/ohos-golang-go-1.24/LICENSE" "$release_rawfile_dir/hna_go_license.txt"
cp "$build_root/third_party/ohos-golang-go-1.24/PATENTS" "$release_rawfile_dir/hna_go_patents.txt"
pass "complete distribution license texts were staged as signed package resources"

build_log="$verify_root/build.log"

export PATH="$deveco_contents/tools/node/bin:$deveco_contents/tools/ohpm/bin:$deveco_contents/tools/hvigor/bin:$sdk_root/openharmony/toolchains:$PATH"
export DEVECO_SDK_HOME="$deveco_contents/sdk"
export HARMONYOS_SDK_HOME="$sdk_root"

# Raw build output is deliberately kept out of the terminal because local
# signing integrations may include sensitive paths or diagnostics. The log is
# held only in the guarded temporary directory and removed on exit.
if ! (
  cd "$build_root"
  "$ohpm_bin" install
  "$hvigor_bin" clean --no-daemon
  "$hvigor_bin" assembleApp -m project -p product=default -p buildMode=release --no-daemon
) </dev/null >"$build_log" 2>&1; then
  fail "release App Pack build failed; inspect the DevEco release-signing configuration locally"
fi
pass "Hvigor assembleApp release build succeeded"

python3 - "$build_root" "$tracked_source_snapshot" <<'PY'
import hashlib
import json
import os
import pathlib
import sys

root = pathlib.Path(sys.argv[1]).resolve()
snapshot = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
allowed_modified = {"entry/src/main/ets/ui/ReleaseConfig.ts"}
for item in snapshot:
    relative = item["path"]
    if relative in allowed_modified:
        continue
    path = root / relative
    if item["kind"] == "symlink" and path.is_symlink():
        payload = os.readlink(path).encode("utf-8", "surrogateescape")
    elif item["kind"] == "file" and path.is_file() and not path.is_symlink():
        payload = path.read_bytes()
    else:
        raise SystemExit("tracked release input type or presence changed")
    if hashlib.sha256(payload).hexdigest() != item["sha256"]:
        raise SystemExit("tracked release input content changed")
PY

isolated_status="$verify_root/isolated-source-status.txt"
isolated_index="$verify_root/isolated-index"
GIT_INDEX_FILE="$isolated_index" git --git-dir="$project_root/.git" read-tree "$git_commit"
GIT_INDEX_FILE="$isolated_index" git --git-dir="$project_root/.git" --work-tree="$build_root" \
  status --porcelain=v1 --untracked-files=all > "$isolated_status"
python3 - "$isolated_status" <<'PY'
import pathlib
import sys

actual = {line for line in pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines() if line}
allowed = {
    " M entry/src/main/ets/ui/ReleaseConfig.ts",
    "?? entry/src/main/resources/rawfile/hna_release_provenance.json",
    "?? entry/src/main/resources/rawfile/hna_gpl_v3.txt",
    "?? entry/src/main/resources/rawfile/hna_third_party_notices.md",
    "?? entry/src/main/resources/rawfile/hna_sing_box_gpl_v3.txt",
    "?? entry/src/main/resources/rawfile/hna_gvisor_apache2.txt",
    "?? entry/src/main/resources/rawfile/hna_go_license.txt",
    "?? entry/src/main/resources/rawfile/hna_go_patents.txt",
}
if actual != allowed:
    raise SystemExit("isolated release source differs from the explicit generated-file allowlist")
PY
pass "isolated build preserved every tracked input and added only signed release resources"

app_candidates="$verify_root/app-candidates.txt"
find "$build_root" -type f -name '*.app' \
  ! -path "$build_root/artifacts/*" \
  ! -path "$build_root/.git/*" \
  -print > "$app_candidates"
app_count="$(wc -l < "$app_candidates" | tr -d ' ')"
[[ "$app_count" == "1" ]] || fail "expected exactly one generated .app App Pack, found $app_count"
source_app="$(sed -n '1p' "$app_candidates")"
[[ -f "$source_app" ]] || fail "generated App Pack is missing"
if ! python3 "$build_root/scripts/verify_release_package.py" app \
    --app "$source_app" --app-json "$app_json" \
    --module-json "$build_root/entry/src/main/module.json5" >/dev/null 2>&1; then
  fail "generated App Pack failed strict ZIP, pack.info, and signed-module semantic validation"
fi
pass "generated App Pack contains exactly the expected release HAP and reviewed metadata"

extract_root="$verify_root/app"
mkdir -p "$extract_root"
if ! "$java_bin" -jar "$unpacking_tool" --mode app --app-path "$source_app" \
    --out-path "$extract_root" --force true >/dev/null 2>&1; then
  fail "official App Pack unpacking tool rejected the generated package"
fi
[[ -f "$extract_root/pack.info" ]] || fail "generated App Pack does not contain root pack.info"

hap_list="$verify_root/hap-list.txt"
find "$extract_root" -type f -name '*.hap' -print > "$hap_list"
hap_count="$(wc -l < "$hap_list" | tr -d ' ')"
[[ "$hap_count" == "1" ]] || fail "generated App Pack must contain exactly one HAP module"
pass "App Pack contains pack.info and $hap_count HAP module(s)"

hap_metadata="$verify_root/hap-metadata.tsv"
: > "$hap_metadata"
module_index=0
core_found=0
packaged_core_sha=""
embedded_provenance_found=0
embedded_license_set_found=0
while IFS= read -r hap_file; do
  [[ -n "$hap_file" ]] || continue
  module_index=$((module_index + 1))
  unzip -tqq "$hap_file" >/dev/null 2>&1 || fail "HAP module $module_index is not a readable archive"
  if unzip -l "$hap_file" | grep -q 'libs/arm64-v8a/libharmonycore\.so'; then
    core_found=1
    packaged_core="$verify_root/packaged-core-$module_index.so"
    unzip -p "$hap_file" 'libs/arm64-v8a/libharmonycore.so' > "$packaged_core"
    if ! file "$packaged_core" | grep -Eq 'ELF 64-bit.*ARM aarch64|ELF 64-bit.*ARM64'; then
      fail "packaged native core is not an ARM64 shared library"
    fi
    current_packaged_core_sha="$(shasum -a 256 "$packaged_core" | awk '{print $1}')"
    if [[ -n "$packaged_core_sha" && "$packaged_core_sha" != "$current_packaged_core_sha" ]]; then
      fail "multiple HAP modules contain different native core binaries"
    fi
    packaged_core_sha="$current_packaged_core_sha"
  fi

  verify_log="$verify_root/verify-$module_index.log"
  if ! "$java_bin" -jar "$sign_tool" verify-app \
      -inFile "$hap_file" \
      -outCertChain "$verify_root/cert-$module_index.cer" \
      -outProfile "$verify_root/profile-$module_index.p7b" \
      >"$verify_log" 2>&1; then
    fail "HAP module $module_index failed signature verification"
  fi
  if grep -Fq 'profile type is: debug' "$verify_log"; then
    fail "HAP module $module_index uses a debug profile; a release profile is mandatory"
  fi
  if ! grep -Fq 'profile type is: release' "$verify_log" ||
    ! grep -Fq 'verify-app success' "$verify_log"; then
    fail "HAP module $module_index could not be proven to use a valid release profile"
  fi

  leaf_der="$verify_root/leaf-$module_index.der"
  if ! openssl x509 -in "$verify_root/cert-$module_index.cer" -outform DER \
      -out "$leaf_der" >/dev/null 2>&1; then
    fail "HAP module $module_index signing leaf certificate could not be decoded"
  fi
  actual_release_cert_sha="$(shasum -a 256 "$leaf_der" | awk '{print $1}')"
  if [[ "$actual_release_cert_sha" != "$expected_release_cert_sha" ]]; then
    fail "HAP module $module_index is not signed by the approved release certificate"
  fi

  provenance_entries="$verify_root/provenance-entries-$module_index.txt"
  zipinfo -1 "$hap_file" | grep -E '(^|/)hna_release_provenance\.json$' \
    > "$provenance_entries" || true
  provenance_entry_count="$(wc -l < "$provenance_entries" | tr -d ' ')"
  if [[ "$provenance_entry_count" -gt 1 ]]; then
    fail "HAP module $module_index contains duplicate release provenance resources"
  elif [[ "$provenance_entry_count" == "1" ]]; then
    embedded_provenance_found=$((embedded_provenance_found + 1))
    provenance_entry="$(sed -n '1p' "$provenance_entries")"
    extracted_provenance="$verify_root/embedded-provenance-$module_index.json"
    unzip -p "$hap_file" "$provenance_entry" > "$extracted_provenance"
    actual_provenance_sha="$(shasum -a 256 "$extracted_provenance" | awk '{print $1}')"
    [[ "$actual_provenance_sha" == "$embedded_provenance_sha" ]] ||
      fail "signed HAP provenance differs from the clean build input"
  fi

  license_entry_count=0
  for license_name in hna_gpl_v3.txt hna_third_party_notices.md \
    hna_sing_box_gpl_v3.txt hna_gvisor_apache2.txt hna_go_license.txt \
    hna_go_patents.txt; do
    current_count="$(zipinfo -1 "$hap_file" | grep -Ec "(^|/)${license_name}$" || true)"
    [[ "$current_count" -le 1 ]] || fail "HAP module $module_index contains duplicate $license_name resources"
    license_entry_count=$((license_entry_count + current_count))
  done
  if [[ "$license_entry_count" -ne 6 ]]; then
    fail "HAP module $module_index contains an incomplete signed license resource set"
  else
    embedded_license_set_found=$((embedded_license_set_found + 1))
    while IFS=$'\t' read -r license_name source_path; do
      license_entry="$(zipinfo -1 "$hap_file" | grep -E "(^|/)${license_name}$")"
      extracted_license="$verify_root/$module_index-$license_name"
      unzip -p "$hap_file" "$license_entry" > "$extracted_license"
      [[ "$(shasum -a 256 "$extracted_license" | awk '{print $1}')" == \
        "$(shasum -a 256 "$project_root/$source_path" | awk '{print $1}')" ]] ||
        fail "signed $license_name differs from the reviewed source-tree license"
    done <<'LICENSE_MAP'
hna_gpl_v3.txt	LICENSE
hna_third_party_notices.md	THIRD_PARTY_NOTICES.md
hna_sing_box_gpl_v3.txt	third_party/sing-box/LICENSE
hna_gvisor_apache2.txt	third_party/gvisor/LICENSE
hna_go_license.txt	third_party/ohos-golang-go-1.24/LICENSE
hna_go_patents.txt	third_party/ohos-golang-go-1.24/PATENTS
LICENSE_MAP
  fi

  relative_hap="${hap_file#"$extract_root"/}"
  hap_sha="$(shasum -a 256 "$hap_file" | awk '{print $1}')"
  printf '%s\t%s\trelease\n' "$relative_hap" "$hap_sha" >> "$hap_metadata"
done < "$hap_list"
[[ "$core_found" -eq 1 ]] || fail "App Pack does not contain ARM64 libharmonycore.so"
[[ "$packaged_core_sha" =~ ^[0-9a-f]{64}$ ]] || fail "packaged native core digest is invalid"
[[ "$embedded_provenance_found" -eq 1 ]] ||
  fail "App Pack must contain exactly one signed release provenance resource"
[[ "$embedded_license_set_found" -eq "$hap_count" ]] ||
  fail "every HAP must contain one complete signed license resource set"

stripped_candidates="$verify_root/stripped-core-candidates.txt"
find "$build_root/entry/build" -type f \
  -path '*/stripped_native_libs/*/arm64-v8a/libharmonycore.so' -print > "$stripped_candidates"
stripped_count="$(wc -l < "$stripped_candidates" | tr -d ' ')"
[[ "$stripped_count" == "1" ]] || fail "expected one freshly stripped native core, found $stripped_count"
stripped_core="$(sed -n '1p' "$stripped_candidates")"
stripped_core_sha="$(shasum -a 256 "$stripped_core" | awk '{print $1}')"
[[ "$packaged_core_sha" == "$stripped_core_sha" ]] ||
  fail "packaged native core differs from this release build's stripped output"
pass "every HAP uses the approved release certificate; signed provenance and core match this locked build"

app_sha="$(shasum -a 256 "$source_app" | awk '{print $1}')"
if app_size="$(stat -f '%z' "$source_app" 2>/dev/null)"; then
  :
else
  app_size="$(stat -c '%s' "$source_app")"
fi
[[ "$app_sha" =~ ^[0-9a-f]{64}$ && "$app_size" =~ ^[0-9]+$ ]] || fail "App Pack digest metadata is invalid"

target_name="${version_name}-${short_commit}"
target_dir="$release_root/$target_name"
[[ ! -e "$target_dir" ]] || fail "release output already exists: $target_dir"
mkdir -p "$release_root"
stage_dir="$(mktemp -d "$release_root/.staging.XXXXXX")"
register_temp "$stage_dir"
artifact_name="HarmonyOS-Network-Assistant-${version_name}-${short_commit}.app"
cp "$source_app" "$stage_dir/$artifact_name"
copied_sha="$(shasum -a 256 "$stage_dir/$artifact_name" | awk '{print $1}')"
[[ "$copied_sha" == "$app_sha" ]] || fail "App Pack digest changed while staging"
cp "$source_archive" "$stage_dir/$source_artifact_name"
source_archive_sha="$(shasum -a 256 "$source_archive" | awk '{print $1}')"
copied_source_sha="$(shasum -a 256 "$stage_dir/$source_artifact_name" | awk '{print $1}')"
[[ "$copied_source_sha" == "$source_archive_sha" ]] ||
  fail "corresponding source digest changed while staging"
for security_artifact in "$sbom_path" "$security_report_snapshot" \
  "$security_policy_snapshot" "$security_verification"; do
  security_artifact_name="$(basename "$security_artifact")"
  cp "$security_artifact" "$stage_dir/$security_artifact_name"
  [[ "$(shasum -a 256 "$security_artifact" | awk '{print $1}')" == \
     "$(shasum -a 256 "$stage_dir/$security_artifact_name" | awk '{print $1}')" ]] ||
    fail "release security artifact digest changed while staging"
done

generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
manifest_path="$stage_dir/release-manifest.json"
"$node_bin" - "$app_json" "$core_lock" "$hap_metadata" "$manifest_path" \
  "$git_commit" "$bundle_name" "$version_name" "$version_code" \
  "$artifact_name" "$app_sha" "$app_size" "$generated_at" \
  "$source_binding" "$policy_bindings" "$security_binding" \
  "$sdk_api" "$sdk_version" "$sdk_release_type" \
  "$built_core_sha" "$packaged_core_sha" "$core_lock_sha" \
  "$build_toolchain_lock_sha" "$embedded_provenance_sha" "$expected_release_cert_sha" "$redacted_build_profile_sha" \
  "$ohos_go_version" "$bootstrap_go_version" \
  "$HNA_OPERATOR_NAME" "$HNA_PRIVACY_URL" "$HNA_PRIVACY_URL_EN" \
  "$HNA_USER_AGREEMENT_URL" "$HNA_USER_AGREEMENT_URL_EN" \
  "$HNA_SUPPORT_URL" "$HNA_SUPPORT_EMAIL" "$HNA_CORRESPONDING_SOURCE_URL" <<'NODE'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const [appJsonPath, coreLockPath, hapMetadataPath, outputPath,
  gitCommit, bundleName, versionName, versionCodeText,
  artifactName, appSha256, appSizeText, generatedAt,
  sourceBindingPath, policyBindingsPath, securityBindingPath,
  sdkApiText, sdkVersion, sdkReleaseType,
  builtCoreSha256, packagedCoreSha256, coreLockSha256, buildToolchainLockSha256,
  embeddedProvenanceSha256, releaseCertSha256,
  buildProfileRedactedSha256, ohosGoVersion, bootstrapGoVersion,
  operatorName, privacyUrl, privacyUrlEn, userAgreementUrl, userAgreementUrlEn,
  supportUrl, supportEmail,
  correspondingSourceUrl] = process.argv.slice(2);
const coreLock = JSON.parse(fs.readFileSync(coreLockPath, 'utf8'));
const correspondingArchive = JSON.parse(fs.readFileSync(sourceBindingPath, 'utf8'));
const policyBindings = JSON.parse(fs.readFileSync(policyBindingsPath, 'utf8'));
const securityEvidence = JSON.parse(fs.readFileSync(securityBindingPath, 'utf8'));
if (policyBindings.schemaVersion !== 1 || !Array.isArray(policyBindings.documents) ||
    policyBindings.documents.length !== 4) {
  throw new Error('invalid reviewed policy bindings');
}
const sourceRoot = path.resolve(path.dirname(coreLockPath), '..');
const distributionLicenses = [
  ['hna_gpl_v3.txt', 'LICENSE'],
  ['hna_third_party_notices.md', 'THIRD_PARTY_NOTICES.md'],
  ['hna_sing_box_gpl_v3.txt', 'third_party/sing-box/LICENSE'],
  ['hna_gvisor_apache2.txt', 'third_party/gvisor/LICENSE'],
  ['hna_go_license.txt', 'third_party/ohos-golang-go-1.24/LICENSE'],
  ['hna_go_patents.txt', 'third_party/ohos-golang-go-1.24/PATENTS'],
].map(([resource, sourcePath]) => ({
  resource,
  sourcePath,
  sha256: crypto.createHash('sha256').update(fs.readFileSync(path.join(sourceRoot, sourcePath))).digest('hex'),
}));
const haps = fs.readFileSync(hapMetadataPath, 'utf8')
  .split('\n')
  .filter(Boolean)
  .map((line) => {
    const [path, sha256, profileType] = line.split('\t');
    if (!path || !/^[0-9a-f]{64}$/.test(sha256) || profileType !== 'release') {
      throw new Error('invalid verified HAP metadata');
    }
    return { path, sha256, profileType };
  });
const manifest = {
  schemaVersion: 1,
  generatedAt,
  source: {
    gitCommit,
    treeClean: true,
    correspondingArchive,
  },
  application: {
    bundleName,
    versionName,
    versionCode: Number(versionCodeText),
    targetApi: 26,
  },
  nativeCore: {
    delivery: 'signed-app-update-only',
    runtimeCodeDownload: false,
    singBoxVersion: coreLock.sing_box.version,
    singBoxCommit: coreLock.sing_box.commit,
    upstreamTree: coreLock.sing_box.upstream_tree,
    vendorTreeSha256: coreLock.sing_box.vendor_tree_sha256,
    patchSha256: coreLock.sing_box.patch_sha256,
    freshlyBuiltUnstrippedSha256: builtCoreSha256,
    packagedStrippedSha256: packagedCoreSha256,
    coreLockSha256,
    embeddedProvenanceSha256,
  },
  signing: {
    profileType: 'release',
    approvedLeafCertificateSha256: releaseCertSha256,
    buildProfileRedactedSha256,
  },
  publicInfo: {
    operatorName,
    privacyUrl,
    privacyUrlEn,
    userAgreementUrl,
    userAgreementUrlEn,
    supportUrl,
    supportEmail,
    correspondingSourceUrl,
  },
  policyDocuments: policyBindings.documents,
  securityEvidence,
  distributionLicenses,
  build: {
    task: 'assembleApp',
    mode: 'project',
    product: 'default',
    buildMode: 'release',
    sdk: {
      api: Number(sdkApiText),
      version: sdkVersion,
      releaseType: sdkReleaseType,
    },
    toolchain: {
      openHarmonyGoVersion: ohosGoVersion,
      bootstrapGoVersion,
      lockSha256: buildToolchainLockSha256,
    },
  },
  appPack: {
    file: artifactName,
    sha256: appSha256,
    sizeBytes: Number(appSizeText),
    containsPackInfo: true,
    allHapsUseReleaseProfile: true,
    haps,
  },
};
fs.writeFileSync(outputPath, `${JSON.stringify(manifest, null, 2)}\n`, {
  encoding: 'utf8',
  mode: 0o644,
});
NODE

if ! python3 "$build_root/scripts/verify_release_package.py" app \
    --app "$source_app" --release-manifest "$manifest_path" \
    --app-json "$app_json" --module-json "$build_root/entry/src/main/module.json5" \
    >/dev/null 2>&1; then
  fail "App Pack metadata is not exactly bound to the generated release manifest"
fi
pass "pack.info, signed HAP manifest, and release manifest are semantically consistent"

manifest_sha="$(shasum -a 256 "$manifest_path" | awk '{print $1}')"
sbom_sha="$(shasum -a 256 "$stage_dir/$sbom_artifact_name" | awk '{print $1}')"
security_report_sha="$(shasum -a 256 "$stage_dir/$security_report_artifact_name" | awk '{print $1}')"
security_policy_sha="$(shasum -a 256 "$stage_dir/$security_policy_artifact_name" | awk '{print $1}')"
security_verification_sha="$(shasum -a 256 "$stage_dir/$security_verification_artifact_name" | awk '{print $1}')"
printf '%s  %s\n%s  %s\n%s  %s\n%s  %s\n%s  %s\n%s  %s\n%s  %s\n' \
  "$app_sha" "$artifact_name" \
  "$source_archive_sha" "$source_artifact_name" \
  "$sbom_sha" "$sbom_artifact_name" \
  "$security_report_sha" "$security_report_artifact_name" \
  "$security_policy_sha" "$security_policy_artifact_name" \
  "$security_verification_sha" "$security_verification_artifact_name" \
  "$manifest_sha" "release-manifest.json" > "$stage_dir/SHA256SUMS"

# The build may take several minutes. Refuse promotion if HEAD, the index, or
# any tracked/untracked source changed after the immutable archives were made.
# All build/package helpers used above came from build_root, so this final gate
# also prevents a concurrent worktree edit from being reported as this commit.
[[ "$(git rev-parse HEAD)" == "$git_commit" ]] ||
  fail "Git HEAD changed during the release build"
git diff --quiet && git diff --cached --quiet &&
  [[ -z "$(git ls-files --others --exclude-standard)" ]] ||
  fail "Git worktree changed during the release build"
mv "$stage_dir" "$target_dir"

echo
echo "BUILT   $target_dir/$artifact_name"
echo "SOURCE  $target_dir/$source_artifact_name"
echo "SBOM    $target_dir/$sbom_artifact_name"
echo "SECURITY $target_dir/$security_report_artifact_name"
echo "POLICY  $target_dir/$security_policy_artifact_name"
echo "MANIFEST $target_dir/release-manifest.json"
echo "SHA256  $app_sha"
echo "PENDING obtain an external signed release approval for these fixed bytes"
echo "READY   build gate passed; run scripts/release_preflight.sh with approval inputs next"
