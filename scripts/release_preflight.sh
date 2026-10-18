#!/usr/bin/env bash
set -euo pipefail

# Static and artifact release gate for the HarmonyOS Network Assistant.
#
# This script deliberately never reads signing passwords, subscription URLs,
# node credentials, or private keys. Legal evidence is supplied as local file
# paths or non-secret ticket identifiers by the release operator.

project_root="$(cd "$(dirname "$0")/.." && pwd)"
market="cn"
app_pack=""
skip_tests=0
allow_dirty=0
failures=0
warnings=0

usage() {
  cat <<'EOF'
Usage:
  scripts/release_preflight.sh --market <cn|overseas> --app /absolute/path/App.app [options]

Options:
  --market cn|overseas  Target distribution region (default: cn)
  --app PATH            Formal HarmonyOS .app App Pack produced by
                        build_release_app.sh; sibling release-manifest.json
                        and SHA256SUMS are mandatory
  --skip-tests          Diagnostic-only: inspect other gates but remain blocked
  --allow-dirty         Diagnostic-only: inspect other gates but remain blocked
  -h, --help            Show this help

Non-secret release declarations:
  HNA_PRIVACY_POLICY_ZH              Local path to Chinese privacy policy
  HNA_PRIVACY_POLICY_EN              Local path to English privacy policy
  HNA_USER_AGREEMENT_ZH              Local path to Chinese user agreement
  HNA_USER_AGREEMENT_EN              Local path to English user agreement
  HNA_OPERATOR_NAME                   Public legal operator name
  HNA_PRIVACY_URL                    Public Chinese privacy-policy URL
  HNA_PRIVACY_URL_EN                 Public English privacy-policy URL
  HNA_USER_AGREEMENT_URL             Public Chinese user-agreement URL
  HNA_USER_AGREEMENT_URL_EN          Public English user-agreement URL
  HNA_SUPPORT_URL                    Public https HTML/text support page URL
  HNA_SUPPORT_EMAIL                  Public support email
  HNA_CORRESPONDING_SOURCE_URL       Public https exact GPL source URL
  HNA_HUAWEI_VPN_REVIEW_TICKET       Public Huawei ticket/reference identifier
  HNA_HUAWEI_VPN_REVIEW_EVIDENCE     Huawei written VPN classification evidence file
  HNA_RELEASE_CERT_SHA256             Approved lowercase SHA-256 fingerprint of
                                      the leaf release certificate (DER form)
  HNA_RELEASE_APPROVAL                Git-external canonical signed approval JSON
  HNA_RELEASE_APPROVAL_SIGNATURE      Git-external detached signature envelope
  HNA_RELEASE_APPROVAL_TRUSTED_KEY    Explicitly trusted Ed25519 public-key JSON
  HNA_RELEASE_SECURITY_POLICY         Explicitly trusted security policy; its exact
                                      bytes must equal the sibling copy

Chinese-mainland evidence paths:
  HNA_CN_APP_FILING_EVIDENCE         APP filing evidence
  HNA_CN_COPYRIGHT_EVIDENCE          App copyright/agency proof
  HNA_CN_TELECOM_LEGAL_REVIEW        Written telecom/VPN legal classification

Overseas evidence:
  HNA_HUAWEI_OVERSEAS_PHONE_EVIDENCE Huawei written exception/eligibility file for
                                      HarmonyOS NEXT phone distribution overseas
  HNA_HUAWEI_OVERSEAS_PHONE_TICKET  Public Huawei overseas eligibility ticket/reference
  HNA_EXPORT_REVIEW_EVIDENCE         Encryption export-control classification

The evidence files may stay outside Git. Their contents are never printed.
The approval is created only after App Pack, manifest, policy documents,
corresponding source, SBOM and security report bytes are final. It is never
copied into the release directory, avoiding a manifest/approval hash cycle.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --market)
      [[ $# -ge 2 ]] || { echo "BLOCKED --market requires a value"; exit 2; }
      market="$2"
      shift 2
      ;;
    --app)
      [[ $# -ge 2 ]] || { echo "BLOCKED --app requires a value"; exit 2; }
      app_pack="$2"
      shift 2
      ;;
    --skip-tests)
      skip_tests=1
      shift
      ;;
    --allow-dirty)
      allow_dirty=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "BLOCKED unknown argument: $1"
      usage
      exit 2
      ;;
  esac
done

if [[ "$market" != "cn" && "$market" != "overseas" ]]; then
  echo "BLOCKED --market must be cn or overseas"
  exit 2
fi

pass() {
  printf 'PASS    %s\n' "$1"
}

warn() {
  printf 'WARN    %s\n' "$1"
  warnings=$((warnings + 1))
}

fail() {
  printf 'BLOCKED %s\n' "$1"
  failures=$((failures + 1))
}

require_file() {
  local variable_name="$1"
  local label="$2"
  local value="${!variable_name:-}"
  if [[ -z "$value" ]]; then
    fail "$label is not declared ($variable_name)"
  elif [[ ! -f "$value" ]]; then
    fail "$label evidence file does not exist ($variable_name)"
  elif [[ ! -s "$value" ]]; then
    fail "$label evidence file is empty ($variable_name)"
  elif grep -Eiq 'HNA_LEGAL_TEMPLATE_DO_NOT_SUBMIT|\[TODO[^]]*\]|(^|[^[:alnum:]])(todo|tbd|placeholder|self-test)([^[:alnum:]]|$)' \
      "$value" 2>/dev/null; then
    fail "$label is still a do-not-submit template or contains TODO markers ($variable_name)"
  else
    pass "$label evidence is present"
  fi
}

require_git_external_file() {
  local variable_name="$1"
  local label="$2"
  local value="${!variable_name:-}"
  require_file "$variable_name" "$label"
  if [[ -f "$value" ]]; then
    if python3 - "$project_root" "$value" <<'PY' >/dev/null 2>&1
import pathlib
import subprocess
import sys

root = pathlib.Path(sys.argv[1]).resolve()
target = pathlib.Path(sys.argv[2]).resolve()
tracked = subprocess.check_output(
    ["git", "-C", str(root), "ls-files", "-z"],
).split(b"\0")
for relative in tracked:
    if relative and (root / relative.decode("utf-8", "surrogateescape")).resolve() == target:
        raise SystemExit(1)
PY
    then
      pass "$label is outside the Git-tracked release source"
    else
      fail "$label must not be tracked by Git ($variable_name)"
    fi
  fi
}

require_non_secret_value() {
  local variable_name="$1"
  local label="$2"
  local value="${!variable_name:-}"
  if [[ -z "$value" ]]; then
    fail "$label is not declared ($variable_name)"
  elif printf '%s' "$value" | grep -Eiq '(^|[^[:alnum:]])(todo|tbd|placeholder|self-test)([^[:alnum:]]|$)|[\[\]]'; then
    fail "$label is still a placeholder ($variable_name)"
  else
    pass "$label is declared"
  fi
}

require_https_url() {
  local variable_name="$1"
  local label="$2"
  local value="${!variable_name:-}"
  if [[ -n "$value" ]] && python3 scripts/release_content_gate.py probe-url \
      --url "$value" >/dev/null 2>&1; then
    pass "$label is a bounded public HTTPS page with a safe 2xx response"
  else
    fail "$label must return a bounded HTML/text HTTPS 2xx response through a DNS-pinned public redirect chain ($variable_name)"
  fi
}

echo "HarmonyOS Network Assistant release preflight"
echo "Market: $market"
echo

cd "$project_root"

for required_command in python3 shasum unzip zipinfo find git openssl cmp; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    fail "required release-preflight command is missing: $required_command"
  fi
done

if [[ -d .git ]]; then
  if [[ -z "$(git status --porcelain)" ]]; then
    pass "Git worktree is clean"
  elif [[ "$allow_dirty" -eq 1 ]]; then
    fail "Git worktree is dirty; --allow-dirty is diagnostic-only and cannot pass release"
  else
    fail "Git worktree is dirty; release artifacts would not be reproducible"
  fi
else
  fail "project is not a Git worktree"
fi
current_git_commit="$(git rev-parse HEAD 2>/dev/null || true)"

expected_release_cert_sha="${HNA_RELEASE_CERT_SHA256:-}"
if [[ "$expected_release_cert_sha" =~ ^[0-9a-f]{64}$ ]]; then
  pass "approved release certificate fingerprint is declared"
else
  fail "HNA_RELEASE_CERT_SHA256 must contain the approved lowercase leaf release certificate SHA-256"
fi

if grep -Eq '"bundleName"[[:space:]]*:[[:space:]]*"com\.harmonynet\.assistant"' AppScope/app.json5; then
  pass "bundle name is explicit"
else
  fail "unexpected or missing bundle name"
fi

if grep -Eq '"versionCode"[[:space:]]*:[[:space:]]*[1-9][0-9]*' AppScope/app.json5 &&
  grep -Eq '"versionName"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+' AppScope/app.json5; then
  pass "versionCode and semantic versionName are present"
else
  fail "versionCode/versionName is missing or invalid"
fi

if grep -Eq "(compileSdkVersion|\"compileSdkVersion\")[[:space:]]*:[[:space:]]*['\"]26\.0\.0['\"]" build-profile.example.json5 &&
  grep -Eq "(targetSdkVersion|\"targetSdkVersion\")[[:space:]]*:[[:space:]]*['\"]26\.0\.0['\"]" build-profile.example.json5 &&
  grep -Eq "(compatibleSdkVersion|\"compatibleSdkVersion\")[[:space:]]*:[[:space:]]*['\"]6\.0\.2\(22\)['\"]" build-profile.example.json5; then
  pass "compile/target SDK are API 26 and minimum compatible SDK is API 22"
else
  fail "API 26 compile/target or API 22 minimum is not locked in the shareable build profile"
fi

if grep -Eq '"type"[[:space:]]*:[[:space:]]*"vpn"' entry/src/main/module.json5 &&
  grep -Eq '"exported"[[:space:]]*:[[:space:]]*false' entry/src/main/module.json5; then
  pass "VPN Extension is declared and not exported"
else
  fail "VPN Extension declaration is missing or exported"
fi

permission_names="$(grep -Eo 'ohos\.permission\.[A-Z0-9_]+' entry/src/main/module.json5 | sort -u || true)"
expected_permission_names=$'ohos.permission.GET_BUNDLE_INFO\nohos.permission.GET_NETWORK_INFO\nohos.permission.INTERNET'
if [[ "$permission_names" == "$expected_permission_names" ]]; then
  pass "permission surface is exactly INTERNET, GET_NETWORK_INFO and GET_BUNDLE_INFO"
else
  fail "permission surface changed; perform a least-privilege and privacy review"
fi

if grep -Eq '"deviceTypes"' entry/src/main/module.json5 &&
  grep -Eq '"phone"' entry/src/main/module.json5; then
  pass "declared device type includes phone"
else
  fail "phone device type is not declared"
fi

if find AppScope/resources entry/src/main/resources -type d \( -name 'en_US' -o -name 'en_GB' -o -name 'en' \) -print -quit | grep -q .; then
  pass "English resource qualifier exists"
else
  fail "English localized resources are missing"
fi

if rg -q "private t\(zh: string, en: string\)" entry/src/main/ets/pages/Index.ets &&
  rg -q "setAppPreferredLanguage\(preference === 'system' \? 'default' : language\)" entry/src/main/ets/pages/Index.ets &&
  rg -q 'localizedRuntimeText' entry/src/main/ets/pages/Index.ets &&
  [[ -f tooling/tests/ui-resources.test.ts ]] &&
  [[ -f tooling/tests/index-ui-contract.test.ts ]]; then
  pass "Chinese/English UI, runtime fallback, resource parity, and UI contracts are present"
else
  fail "Chinese/English UI implementation or its localization contract tests are incomplete"
fi

if grep -Fq 'writeAtomicText(this.storePath, JSON.stringify(state))' \
    entry/src/main/ets/repositories/SubscriptionRepository.ts; then
  fail "subscription URLs and node credentials are still persisted as plaintext JSON"
else
  pass "subscription repository no longer uses the known plaintext write path"
fi

if grep -Fq 'writeAtomicText(this.configPath, configJson)' \
    entry/src/main/ets/services/VpnRuntimeConfigStore.ts; then
  fail "runtime sing-box credentials are still persisted as plaintext JSON"
else
  pass "runtime configuration no longer uses the known plaintext write path"
fi

if rg -q '(AssetStoreKit|UniversalKeystoreKit|@ohos\.security\.asset|huks|Huks)' \
    entry/src/main/ets entry/src/main/cpp 2>/dev/null; then
  pass "HarmonyOS secure storage/keystore integration is present"
else
  fail "no Asset Store or HUKS secure-storage integration was found"
fi

tracked_signing_secret=0
if git grep -En '"(keyPassword|storePassword)"[[:space:]]*:[[:space:]]*"[^"$]+' \
    -- ':!third_party/**' ':!docs/**' >/dev/null 2>&1; then
  tracked_signing_secret=1
fi
if [[ "$tracked_signing_secret" -eq 0 ]]; then
  pass "no obvious signing password is tracked by Git"
else
  fail "a signing password appears to be tracked by Git"
fi

ignore_rules_ok=1
for ignored_secret in build-profile.json5 build-profile.local.json5 \
  .signing/example signing-private/example; do
  if git check-ignore -q "$ignored_secret" 2>/dev/null; then
    :
  else
    fail "$ignored_secret is not protected by .gitignore"
    ignore_rules_ok=0
  fi
done
if [[ "$ignore_rules_ok" -eq 1 ]]; then
  pass "local signing material paths are ignored"
fi

for license_file in third_party/sing-box/LICENSE third_party/gvisor/LICENSE \
  third_party/ohos-golang-go-1.24/LICENSE; do
  if [[ -f "$license_file" ]]; then
    pass "vendored license is present: $license_file"
  else
    fail "vendored license is missing: $license_file"
  fi
done

if [[ -f LICENSE ]] && grep -Fq 'GNU GENERAL PUBLIC LICENSE' LICENSE &&
  grep -Fq 'END OF TERMS AND CONDITIONS' LICENSE; then
  pass "complete GPLv3 distribution LICENSE is present"
else
  fail "complete GPLv3 distribution LICENSE is missing"
fi
notice_file="THIRD_PARTY_NOTICES.md"
if [[ -s "$notice_file" ]] &&
  ! grep -Eiq 'not yet a final|HNA_LEGAL_TEMPLATE_DO_NOT_SUBMIT|\[TODO[^]]*\]' "$notice_file"; then
  pass "final distribution NOTICE/open-source notices are present"
elif [[ -s "$notice_file" ]]; then
  fail "distribution NOTICE/open-source notices are explicitly preliminary"
else
  fail "the exact bundled THIRD_PARTY_NOTICES.md is missing or empty"
fi
if [[ -s "$notice_file" ]] && python3 scripts/verify_open_source_notice.py \
    "$notice_file" entry/src/main/ets/ui/OpenSourceTexts.ts \
    third_party/core-lock.json >/dev/null 2>&1; then
  pass "in-app notice, THIRD_PARTY_NOTICES.md, and core lock exactly agree"
else
  fail "in-app notice, THIRD_PARTY_NOTICES.md, or core lock differs"
fi
require_non_secret_value HNA_OPERATOR_NAME "release operator name"
current_version_name="$(sed -nE 's/^[[:space:]]*"versionName"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' AppScope/app.json5 | head -n 1)"
current_version_code="$(sed -nE 's/^[[:space:]]*"versionCode"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' AppScope/app.json5 | head -n 1)"
current_bundle_name="$(sed -nE 's/^[[:space:]]*"bundleName"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' AppScope/app.json5 | head -n 1)"
if [[ -z "$current_version_name" ]] || ! python3 - "${HNA_CORRESPONDING_SOURCE_URL:-}" \
    "$current_git_commit" "$current_version_name" <<'PY' >/dev/null 2>&1
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
else
  pass "GPL corresponding source names this exact release"
fi

require_file HNA_PRIVACY_POLICY_ZH "Chinese privacy policy"
require_file HNA_PRIVACY_POLICY_EN "English privacy policy"
require_file HNA_USER_AGREEMENT_ZH "Chinese user agreement"
require_file HNA_USER_AGREEMENT_EN "English user agreement"
require_git_external_file HNA_RELEASE_APPROVAL "signed release approval"
require_git_external_file HNA_RELEASE_APPROVAL_SIGNATURE "release approval detached signature"
require_git_external_file HNA_RELEASE_APPROVAL_TRUSTED_KEY "release approval trusted public key"
require_file HNA_RELEASE_SECURITY_POLICY "explicitly trusted release security policy"
require_https_url HNA_SUPPORT_URL "support site"

if python3 - "${HNA_SUPPORT_EMAIL:-}" <<'PY' >/dev/null 2>&1
import re
import sys

value = sys.argv[1].strip()
lower = value.lower()
if any(token in lower for token in ("todo", "tbd", "placeholder", "example.com", "example.org", "example.net")):
    raise SystemExit(1)
if not re.fullmatch(r"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+", value):
    raise SystemExit(1)
PY
then
  pass "support email is declared"
else
  fail "valid support email is missing (HNA_SUPPORT_EMAIL)"
fi

require_file HNA_HUAWEI_VPN_REVIEW_EVIDENCE \
  "Huawei VPN/proxy category review"
require_non_secret_value HNA_HUAWEI_VPN_REVIEW_TICKET \
  "Huawei VPN/proxy category review ticket"

if [[ "$market" == "cn" ]]; then
  require_file HNA_CN_APP_FILING_EVIDENCE "Chinese-mainland APP filing"
  require_file HNA_CN_COPYRIGHT_EVIDENCE "Chinese-mainland app copyright proof"
  require_file HNA_CN_TELECOM_LEGAL_REVIEW "Chinese-mainland telecom/VPN legal review"
else
  # Huawei's 2026-05-27 HarmonyOS 5+ release-region documentation states
  # that HarmonyOS NEXT apps are currently global only on smart watches;
  # other device types are available only in the Chinese mainland.
  require_file HNA_HUAWEI_OVERSEAS_PHONE_EVIDENCE \
    "Huawei overseas HarmonyOS NEXT phone eligibility confirmation"
  require_non_secret_value HNA_HUAWEI_OVERSEAS_PHONE_TICKET \
    "Huawei overseas HarmonyOS NEXT phone eligibility ticket"
  require_file HNA_EXPORT_REVIEW_EVIDENCE "encryption export-control review"
fi

tmp_dir=""
cleanup_tmp() {
  if [[ -n "$tmp_dir" && -d "$tmp_dir" && "$tmp_dir" == /tmp/hna-release-preflight.* ]]; then
    find "$tmp_dir" -depth -delete
  fi
}
trap cleanup_tmp EXIT

if [[ -z "$app_pack" ]]; then
  fail "formal .app App Pack was not supplied (--app)"
elif [[ "$app_pack" != *.app ]]; then
  fail "formal submission artifact must be a .app App Pack, not a debug HAP"
elif [[ ! -f "$app_pack" ]]; then
  fail "App Pack does not exist"
else
  release_directory="$(cd "$(dirname "$app_pack")" && pwd)"
  release_manifest="$release_directory/release-manifest.json"
  release_checksums="$release_directory/SHA256SUMS"
  release_security_policy=""
  release_sbom=""
  release_security_report=""
  release_security_verification=""
  tmp_dir="$(mktemp -d /tmp/hna-release-preflight.XXXXXX)"
  mkdir -p "$tmp_dir/app"

  policy_bindings="$tmp_dir/policy-bindings.json"
  if python3 scripts/release_content_gate.py verify-policies \
      --privacy-zh-file "${HNA_PRIVACY_POLICY_ZH:-}" --privacy-zh-url "${HNA_PRIVACY_URL:-}" \
      --privacy-en-file "${HNA_PRIVACY_POLICY_EN:-}" --privacy-en-url "${HNA_PRIVACY_URL_EN:-}" \
      --agreement-zh-file "${HNA_USER_AGREEMENT_ZH:-}" --agreement-zh-url "${HNA_USER_AGREEMENT_URL:-}" \
      --agreement-en-file "${HNA_USER_AGREEMENT_EN:-}" --agreement-en-url "${HNA_USER_AGREEMENT_URL_EN:-}" \
      > "$policy_bindings" 2>/dev/null; then
    pass "all published Chinese/English policy bodies exactly match the reviewed local bytes"
  else
    fail "published policy bodies do not exactly match the four reviewed local UTF-8 documents"
  fi

  source_artifact_name="HarmonyOS-Network-Assistant-source-${current_version_name}-${current_git_commit}.tar.gz"
  release_source_archive="$release_directory/$source_artifact_name"
  reproduced_source_archive="$tmp_dir/$source_artifact_name"
  source_local_metadata="$tmp_dir/source-local.json"
  source_published_metadata="$tmp_dir/source-published.json"
  if python3 scripts/release_content_gate.py create-source \
      --repo "$project_root" --commit "$current_git_commit" --version "$current_version_name" \
      --output "$reproduced_source_archive" > "$source_local_metadata" 2>/dev/null &&
      [[ -f "$release_source_archive" ]] &&
      [[ "$(shasum -a 256 "$reproduced_source_archive" | awk '{print $1}')" == \
         "$(shasum -a 256 "$release_source_archive" | awk '{print $1}')" ]]; then
    pass "sibling GPL source archive deterministically reproduces from the current Git commit"
  else
    fail "sibling GPL source archive is missing or differs from the deterministic current-commit archive"
  fi
  if [[ -f "$release_source_archive" ]] &&
      python3 scripts/release_content_gate.py verify-url \
        --kind source --url "${HNA_CORRESPONDING_SOURCE_URL:-}" \
        --expected-file "$release_source_archive" > "$source_published_metadata" 2>/dev/null; then
    pass "published GPL source URL serves the exact deterministic sibling archive"
  else
    fail "published GPL source URL does not serve the exact deterministic sibling archive"
  fi

  # Resolve security artifact names only from the manifest after constraining
  # them to plain sibling filenames. These bytes are later checked against the
  # manifest, SHA256SUMS, regenerated SBOM and signed package provenance.
  security_paths="$tmp_dir/security-paths.txt"
  if [[ -s "$release_manifest" ]] && python3 - "$release_manifest" "$release_directory" \
      > "$security_paths" <<'PY'
import json
import pathlib
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
directory = pathlib.Path(sys.argv[2]).resolve()
security = manifest.get("securityEvidence")
if not isinstance(security, dict) or set(security) != {"schemaVersion", "sbom", "report", "policy", "verification"}:
    raise SystemExit(1)
if security.get("schemaVersion") != 1:
    raise SystemExit(1)
for name in ("sbom", "report", "policy", "verification"):
    item = security.get(name)
    filename = item.get("file") if isinstance(item, dict) else None
    if not isinstance(filename, str) or pathlib.PurePosixPath(filename).name != filename or filename in {"", ".", ".."}:
        raise SystemExit(1)
    path = (directory / filename).resolve()
    if path.parent != directory:
        raise SystemExit(1)
    print(path)
PY
  then
    if [[ "$(wc -l < "$security_paths" | tr -d ' ')" == "4" ]]; then
      release_sbom="$(sed -n '1p' "$security_paths")"
      release_security_report="$(sed -n '2p' "$security_paths")"
      release_security_policy="$(sed -n '3p' "$security_paths")"
      release_security_verification="$(sed -n '4p' "$security_paths")"
    else
      fail "release manifest security artifact set is incomplete"
    fi
  else
    fail "release manifest has no strict sibling security evidence bindings"
  fi

  security_siblings_ok=1
  for security_sibling in "$release_sbom" "$release_security_report" \
    "$release_security_policy" "$release_security_verification"; do
    if [[ -z "$security_sibling" || ! -s "$security_sibling" ]]; then
      security_siblings_ok=0
    fi
  done
  if [[ "$security_siblings_ok" -eq 1 ]]; then
    pass "SBOM, security report, policy, and verifier record are present beside the App Pack"
  else
    fail "one or more sibling release security artifacts are missing or empty"
  fi
  if [[ -s "$release_security_policy" && -s "${HNA_RELEASE_SECURITY_POLICY:-}" ]] &&
      cmp -s "$release_security_policy" "$HNA_RELEASE_SECURITY_POLICY"; then
    pass "explicit release security policy exactly matches the sibling policy bytes"
  else
    fail "HNA_RELEASE_SECURITY_POLICY differs from the sibling policy bound by the release"
  fi

  strict_package_ok=0
  if [[ -s "$release_manifest" && -s "$release_checksums" ]] && \
      python3 scripts/verify_release_package.py app --app "$app_pack" \
        --release-manifest "$release_manifest" --app-json AppScope/app.json5 \
        --module-json entry/src/main/module.json5 >/dev/null 2>&1; then
    strict_package_ok=1
    pass "App Pack contains exactly one reviewed release HAP and no unexpected payloads"
  else
    fail "App Pack failed strict ZIP, payload, pack.info, or signed HAP manifest validation"
  fi

  sign_tool="${HNA_HAP_SIGN_TOOL:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar}"
  java_bin="${HNA_JAVA_BIN:-/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin/java}"
  unpacking_tool="$(dirname "$sign_tool")/app_unpacking_tool.jar"
  official_unpack_ok=0
  if [[ "$strict_package_ok" -eq 1 && -f "$unpacking_tool" && -x "$java_bin" ]]; then
    if "$java_bin" -jar "$unpacking_tool" --mode app --app-path "$app_pack" \
        --out-path "$tmp_dir/app" --force true >/dev/null 2>&1; then
      official_unpack_ok=1
      pass "official HarmonyOS unpacking tool accepted the App Pack"
    else
      fail "official HarmonyOS unpacking tool rejected the App Pack"
    fi
  elif [[ "$strict_package_ok" -eq 1 ]]; then
    fail "official HarmonyOS unpacking tool is required for formal release validation"
  fi

  # Recreate the SBOM from the core inside the officially unpacked, structurally
  # validated App Pack. Go BuildInfo survives stripping, so this proves that the
  # signed report covers the dependency graph of the actual packaged core, not
  # merely an unrelated local build output.
  security_gate_ok=0
  preflight_toolchain_ok=0
  preflight_ohos_go="$project_root/third_party/ohos-golang-go-1.24/bin/go"
  if scripts/build_ohos_go.sh >/dev/null 2>&1 && [[ -x "$preflight_ohos_go" ]]; then
    preflight_toolchain_ok=1
    pass "locked OpenHarmony Go toolchain was rebuilt for independent SBOM verification"
  else
    fail "locked OpenHarmony Go toolchain could not be rebuilt for SBOM verification"
  fi
  packaged_core_for_sbom="$tmp_dir/packaged-core-for-sbom.so"
  reproduced_sbom="$tmp_dir/reproduced-release.cdx.json"
  packaged_hap_for_sbom=""
  if [[ "$official_unpack_ok" -eq 1 ]]; then
    packaged_hap_for_sbom="$(find "$tmp_dir/app" -type f -name '*.hap' -print | sed -n '1p')"
  fi
  if [[ "$official_unpack_ok" -eq 1 && "$security_siblings_ok" -eq 1 && \
        "$preflight_toolchain_ok" -eq 1 && \
        -n "$packaged_hap_for_sbom" && \
        "$(find "$tmp_dir/app" -type f -name '*.hap' -print | wc -l | tr -d ' ')" == "1" ]] &&
      unzip -p "$packaged_hap_for_sbom" 'libs/arm64-v8a/libharmonycore.so' \
        > "$packaged_core_for_sbom" 2>/dev/null &&
      [[ -s "$packaged_core_for_sbom" ]] &&
      python3 scripts/generate_release_sbom.py --repo "$project_root" \
        --core-binary "$packaged_core_for_sbom" --go-tool "$preflight_ohos_go" \
        --output "$reproduced_sbom" >/dev/null 2>&1 &&
      cmp -s "$reproduced_sbom" "$release_sbom" &&
      python3 scripts/verify_release_security.py --sbom "$release_sbom" \
        --security-report "$release_security_report" --policy "$release_security_policy" \
        > "$tmp_dir/security-verification.json" 2>/dev/null &&
      cmp -s "$tmp_dir/security-verification.json" "$release_security_verification"; then
    security_gate_ok=1
    pass "packaged-core SBOM reproduces and its trusted signed security report remains valid"
  else
    fail "packaged-core SBOM/security report/policy cannot be independently reproduced and verified"
  fi

  if [[ "$official_unpack_ok" -ne 1 ]]; then
    fail "officially unpacked App Pack contents are unavailable for provenance and signature checks"
  elif [[ ! -s "$release_manifest" ]]; then
    fail "release-manifest.json is missing beside the App Pack"
  elif [[ ! -s "$release_checksums" ]]; then
    fail "SHA256SUMS is missing beside the App Pack"
  elif ! python3 - "$app_pack" "$release_manifest" "$release_checksums" \
      "$tmp_dir/app" "$project_root/third_party/core-lock.json" \
      "$project_root/third_party/build-toolchain-lock.json" \
      "$project_root/AppScope/app.json5" "$current_git_commit" \
      "$expected_release_cert_sha" "${HNA_OPERATOR_NAME:-}" "${HNA_PRIVACY_URL:-}" \
      "${HNA_PRIVACY_URL_EN:-}" "${HNA_USER_AGREEMENT_URL:-}" \
      "${HNA_USER_AGREEMENT_URL_EN:-}" "${HNA_SUPPORT_URL:-}" "${HNA_SUPPORT_EMAIL:-}" \
      "${HNA_CORRESPONDING_SOURCE_URL:-}" "$policy_bindings" \
      "$release_source_archive" "$source_published_metadata" \
      "$release_sbom" "$release_security_report" "$release_security_policy" \
      "$release_security_verification" <<'PY'
import hashlib
import json
import pathlib
import sys
import zipfile

app_path = pathlib.Path(sys.argv[1]).resolve()
manifest_path = pathlib.Path(sys.argv[2]).resolve()
checksums_path = pathlib.Path(sys.argv[3]).resolve()
extract_root = pathlib.Path(sys.argv[4]).resolve()
core_lock_path = pathlib.Path(sys.argv[5]).resolve()
build_toolchain_lock_path = pathlib.Path(sys.argv[6]).resolve()
app_json_path = pathlib.Path(sys.argv[7]).resolve()
git_commit = sys.argv[8]
expected_release_cert_sha = sys.argv[9]
expected_public_info = {
    "operatorName": sys.argv[10],
    "privacyUrl": sys.argv[11],
    "privacyUrlEn": sys.argv[12],
    "userAgreementUrl": sys.argv[13],
    "userAgreementUrlEn": sys.argv[14],
    "supportUrl": sys.argv[15],
    "supportEmail": sys.argv[16],
    "correspondingSourceUrl": sys.argv[17],
}
policy_bindings_path = pathlib.Path(sys.argv[18]).resolve()
source_archive_path = pathlib.Path(sys.argv[19]).resolve()
source_published_metadata_path = pathlib.Path(sys.argv[20]).resolve()
security_paths = {
    "sbom": pathlib.Path(sys.argv[21]).resolve(),
    "report": pathlib.Path(sys.argv[22]).resolve(),
    "policy": pathlib.Path(sys.argv[23]).resolve(),
    "verification": pathlib.Path(sys.argv[24]).resolve(),
}

sha_pattern = set("0123456789abcdef")
def digest(path: pathlib.Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()

def require_sha(value: object) -> str:
    if not isinstance(value, str) or len(value) != 64 or any(ch not in sha_pattern for ch in value):
        raise ValueError("invalid sha256")
    return value

manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
core_lock = json.loads(core_lock_path.read_text(encoding="utf-8"))
app_json = json.loads(app_json_path.read_text(encoding="utf-8"))["app"]
if manifest.get("schemaVersion") != 1:
    raise ValueError("release manifest schema mismatch")
source = manifest.get("source", {})
if source.get("gitCommit") != git_commit or source.get("treeClean") is not True:
    raise ValueError("release source commit mismatch")
policy_bindings = json.loads(policy_bindings_path.read_text(encoding="utf-8"))
source_published = json.loads(source_published_metadata_path.read_text(encoding="utf-8"))
expected_corresponding_archive = {
    "file": source_archive_path.name,
    "url": expected_public_info["correspondingSourceUrl"],
    "resolvedUrl": source_published["resolvedUrl"],
    "redirectCount": source_published["redirectCount"],
    "sha256": digest(source_archive_path),
    "sizeBytes": source_archive_path.stat().st_size,
    "contentType": source_published["contentType"],
    "format": "tar+gzip",
}
if source.get("correspondingArchive") != expected_corresponding_archive:
    raise ValueError("release corresponding-source binding mismatch")
application = manifest.get("application", {})
if (application.get("bundleName") != app_json.get("bundleName") or
    application.get("versionName") != app_json.get("versionName") or
    application.get("versionCode") != app_json.get("versionCode") or
    application.get("targetApi") != 26):
    raise ValueError("release application metadata mismatch")
native = manifest.get("nativeCore", {})
sing_box = core_lock["sing_box"]
if (native.get("delivery") != "signed-app-update-only" or
    native.get("runtimeCodeDownload") is not False or
    native.get("singBoxVersion") != sing_box.get("version") or
    native.get("singBoxCommit") != sing_box.get("commit") or
    native.get("upstreamTree") != sing_box.get("upstream_tree") or
    native.get("vendorTreeSha256") != sing_box.get("vendor_tree_sha256") or
    native.get("patchSha256") != sing_box.get("patch_sha256") or
    require_sha(native.get("coreLockSha256")) != digest(core_lock_path)):
    raise ValueError("release core provenance mismatch")
packaged_core_sha = require_sha(native.get("packagedStrippedSha256"))
require_sha(native.get("freshlyBuiltUnstrippedSha256"))
embedded_provenance_sha = require_sha(native.get("embeddedProvenanceSha256"))
signing = manifest.get("signing", {})
if (signing.get("profileType") != "release" or
    require_sha(signing.get("approvedLeafCertificateSha256")) != expected_release_cert_sha):
    raise ValueError("release signing provenance mismatch")
redacted_build_profile_sha = require_sha(signing.get("buildProfileRedactedSha256"))
if manifest.get("publicInfo") != expected_public_info:
    raise ValueError("release public metadata mismatch")
if manifest.get("policyDocuments") != policy_bindings.get("documents"):
    raise ValueError("release policy-body binding mismatch")
security_formats = {
    "sbom": "cyclonedx-json-1.6",
    "report": "hna-release-security-scan-v1",
    "policy": "hna-release-security-policy-v1",
    "verification": "hna-release-security-verification-v1",
}
expected_security_evidence = {
    "schemaVersion": 1,
    **{
        name: {
            "file": path.name,
            "sha256": digest(path),
            "sizeBytes": path.stat().st_size,
            "format": security_formats[name],
        }
        for name, path in security_paths.items()
    },
}
if manifest.get("securityEvidence") != expected_security_evidence:
    raise ValueError("release security evidence binding mismatch")
build = manifest.get("build", {})
if (build.get("task") != "assembleApp" or build.get("buildMode") != "release" or
    build.get("sdk", {}).get("api") != 26 or
    str(build.get("sdk", {}).get("releaseType", "")).lower() != "release" or
    build.get("toolchain", {}).get("lockSha256") != digest(build_toolchain_lock_path)):
    raise ValueError("release build metadata mismatch")
app_pack = manifest.get("appPack", {})
actual_app_sha = digest(app_path)
if (app_pack.get("file") != app_path.name or
    require_sha(app_pack.get("sha256")) != actual_app_sha or
    app_pack.get("sizeBytes") != app_path.stat().st_size or
    app_pack.get("containsPackInfo") is not True or
    app_pack.get("allHapsUseReleaseProfile") is not True):
    raise ValueError("App Pack digest metadata mismatch")
checksum_lines = [line for line in checksums_path.read_text(encoding="utf-8").splitlines() if line]
if checksum_lines != [
    f"{actual_app_sha}  {app_path.name}",
    f"{digest(source_archive_path)}  {source_archive_path.name}",
    f"{digest(security_paths['sbom'])}  {security_paths['sbom'].name}",
    f"{digest(security_paths['report'])}  {security_paths['report'].name}",
    f"{digest(security_paths['policy'])}  {security_paths['policy'].name}",
    f"{digest(security_paths['verification'])}  {security_paths['verification'].name}",
    f"{digest(manifest_path)}  {manifest_path.name}",
]:
    raise ValueError("SHA256SUMS mismatch")

manifest_haps = app_pack.get("haps")
if not isinstance(manifest_haps, list) or len(manifest_haps) != 1:
    raise ValueError("release manifest must contain exactly one HAP provenance entry")
actual_haps = {str(path.relative_to(extract_root)) for path in extract_root.rglob("*.hap")}
declared_haps = set()
core_hashes = set()
embedded_provenance_payloads = []
license_source_paths = {
    "hna_gpl_v3.txt": core_lock_path.parent.parent / "LICENSE",
    "hna_third_party_notices.md": core_lock_path.parent.parent / "THIRD_PARTY_NOTICES.md",
    "hna_sing_box_gpl_v3.txt": core_lock_path.parent / "sing-box" / "LICENSE",
    "hna_gvisor_apache2.txt": core_lock_path.parent / "gvisor" / "LICENSE",
    "hna_go_license.txt": core_lock_path.parent / "ohos-golang-go-1.24" / "LICENSE",
    "hna_go_patents.txt": core_lock_path.parent / "ohos-golang-go-1.24" / "PATENTS",
}
if any(not source.is_file() for source in license_source_paths.values()):
    raise ValueError("reviewed source-tree license is missing")
expected_distribution_licenses = [
    {
        "resource": resource,
        "sourcePath": str(source_path.relative_to(core_lock_path.parent.parent)),
        "sha256": digest(source_path),
    }
    for resource, source_path in license_source_paths.items()
]
if manifest.get("distributionLicenses") != expected_distribution_licenses:
    raise ValueError("release distribution license manifest mismatch")
for item in manifest_haps:
    relative = item.get("path") if isinstance(item, dict) else None
    if not isinstance(relative, str) or pathlib.PurePosixPath(relative).is_absolute() or ".." in pathlib.PurePosixPath(relative).parts:
        raise ValueError("unsafe HAP path")
    hap_path = extract_root / relative
    if not hap_path.is_file() or item.get("profileType") != "release" or require_sha(item.get("sha256")) != digest(hap_path):
        raise ValueError("HAP digest metadata mismatch")
    declared_haps.add(relative)
    with zipfile.ZipFile(hap_path) as archive:
        core_names = [name for name in archive.namelist() if name == "libs/arm64-v8a/libharmonycore.so"]
        for name in core_names:
            core_hashes.add(hashlib.sha256(archive.read(name)).hexdigest())
        provenance_names = [name for name in archive.namelist() if pathlib.PurePosixPath(name).name == "hna_release_provenance.json"]
        if len(provenance_names) > 1:
            raise ValueError("duplicate embedded release provenance")
        for name in provenance_names:
            payload = archive.read(name)
            if hashlib.sha256(payload).hexdigest() != embedded_provenance_sha:
                raise ValueError("embedded release provenance digest mismatch")
            embedded_provenance_payloads.append(payload)
        license_entries = {}
        for name in archive.namelist():
            basename = pathlib.PurePosixPath(name).name
            if basename in license_source_paths:
                license_entries.setdefault(basename, []).append(name)
        if set(license_entries) != set(license_source_paths) or any(len(entries) != 1 for entries in license_entries.values()):
            raise ValueError("HAP signed license resource set is incomplete or duplicated")
        for basename, source_path in license_source_paths.items():
            if hashlib.sha256(archive.read(license_entries[basename][0])).hexdigest() != digest(source_path):
                raise ValueError("HAP signed license resource differs from source tree")
if declared_haps != actual_haps or core_hashes != {packaged_core_sha}:
    raise ValueError("packaged HAP/core provenance mismatch")
if len(embedded_provenance_payloads) != 1:
    raise ValueError("exactly one signed release provenance resource is required")
embedded = json.loads(embedded_provenance_payloads[0].decode("utf-8"))
if (embedded.get("schemaVersion") != 1 or
    embedded.get("source") != source or
    embedded.get("application") != {
        "bundleName": app_json.get("bundleName"),
        "versionName": app_json.get("versionName"),
        "versionCode": app_json.get("versionCode"),
        "targetApi": 26,
    } or
    embedded.get("signing", {}).get("approvedLeafCertificateSha256") != expected_release_cert_sha or
    embedded.get("signing", {}).get("buildProfileRedactedSha256") != redacted_build_profile_sha):
    raise ValueError("signed release provenance metadata mismatch")
if embedded.get("publicInfo") != expected_public_info:
    raise ValueError("signed release public metadata mismatch")
if embedded.get("policyDocuments") != policy_bindings.get("documents"):
    raise ValueError("signed release policy-body binding mismatch")
if embedded.get("securityEvidence") != expected_security_evidence:
    raise ValueError("signed release security evidence binding mismatch")
if embedded.get("buildInputs") != {
    "buildToolchainLockSha256": digest(build_toolchain_lock_path),
}:
    raise ValueError("signed build toolchain provenance mismatch")
if embedded.get("distributionLicenses") != expected_distribution_licenses:
    raise ValueError("signed release distribution license metadata mismatch")
embedded_native = embedded.get("nativeCore", {})
if (embedded_native.get("delivery") != "signed-app-update-only" or
    embedded_native.get("runtimeCodeDownload") is not False or
    embedded_native.get("coreLockSha256") != digest(core_lock_path) or
    embedded_native.get("singBoxVersion") != sing_box.get("version") or
    embedded_native.get("singBoxCommit") != sing_box.get("commit") or
    embedded_native.get("vendorTreeSha256") != sing_box.get("vendor_tree_sha256") or
    embedded_native.get("patchSha256") != sing_box.get("patch_sha256") or
    embedded_native.get("freshlyBuiltUnstrippedSha256") != native.get("freshlyBuiltUnstrippedSha256")):
    raise ValueError("signed native-core provenance mismatch")
PY
  then
    fail "App Pack provenance does not match its manifest, checksums, current Git commit, or core lock"
  else
    pass "App Pack is cryptographically bound to its release manifest, current source commit, and core lock"
  fi

  if [[ "$official_unpack_ok" -eq 1 && -f "$tmp_dir/app/pack.info" ]]; then
    pass "App Pack contains pack.info"
  else
    fail "App Pack does not contain pack.info"
  fi

  hap_list_file="$tmp_dir/hap-list.txt"
  if [[ "$official_unpack_ok" -eq 1 ]]; then
    find "$tmp_dir/app" -type f -name '*.hap' -print > "$hap_list_file"
  else
    : > "$hap_list_file"
  fi
  if [[ ! -s "$hap_list_file" ]]; then
    fail "App Pack contains no HAP"
  else
    hap_count="$(wc -l < "$hap_list_file" | tr -d ' ')"
    pass "App Pack contains $hap_count HAP module(s)"
  fi

  arm64_core_found=0
  while IFS= read -r hap_file; do
    [[ -n "$hap_file" ]] || continue
    if unzip -l "$hap_file" | grep -q 'libs/arm64-v8a/libharmonycore\.so'; then
      arm64_core_found=1
    fi
  done < "$hap_list_file"
  if [[ "$arm64_core_found" -eq 1 ]]; then
    pass "App Pack contains the ARM64 sing-box core"
  else
    fail "ARM64 libharmonycore.so is missing from the App Pack"
  fi

  sign_tool="${HNA_HAP_SIGN_TOOL:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar}"
  java_bin="${HNA_JAVA_BIN:-/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin/java}"
  if [[ ! -f "$sign_tool" || ! -x "$java_bin" ]]; then
    fail "DevEco hap-sign-tool or Java runtime is unavailable"
  else
    module_index=0
    while IFS= read -r hap_file; do
      [[ -n "$hap_file" ]] || continue
      module_index=$((module_index + 1))
      verify_log="$tmp_dir/verify-$module_index.log"
      if "$java_bin" -jar "$sign_tool" verify-app \
          -inFile "$hap_file" \
          -outCertChain "$tmp_dir/cert-$module_index.cer" \
          -outProfile "$tmp_dir/profile-$module_index.p7b" \
          >"$verify_log" 2>&1; then
        if grep -Fq 'profile type is: release' "$verify_log"; then
          leaf_der="$tmp_dir/leaf-$module_index.der"
          if ! openssl x509 -in "$tmp_dir/cert-$module_index.cer" -outform DER \
              -out "$leaf_der" >/dev/null 2>&1; then
            fail "HAP $module_index release certificate could not be decoded"
          elif [[ "$(shasum -a 256 "$leaf_der" | awk '{print $1}')" != "$expected_release_cert_sha" ]]; then
            fail "HAP $module_index is not signed by the approved release certificate"
          else
            pass "HAP $module_index has the approved release signature/profile"
          fi
        elif grep -Fq 'profile type is: debug' "$verify_log"; then
          fail "HAP $module_index is debug-signed, not release-signed"
        else
          fail "HAP $module_index signature profile type could not be proven release"
        fi
      else
        fail "HAP $module_index signature verification failed"
      fi
    done < "$hap_list_file"
  fi

  # The signed approval is intentionally last in the artifact gate. It binds
  # the already-fixed App Pack and manifest (plus policies, source, SBOM,
  # security report and exact market evidence), so neither the manifest nor
  # SHA256SUMS ever needs to include the approval and no hash cycle exists.
  approval_inputs_ok=1
  for approval_input in \
    "${HNA_RELEASE_APPROVAL:-}" \
    "${HNA_RELEASE_APPROVAL_SIGNATURE:-}" \
    "${HNA_RELEASE_APPROVAL_TRUSTED_KEY:-}" \
    "${HNA_PRIVACY_POLICY_ZH:-}" "${HNA_PRIVACY_POLICY_EN:-}" \
    "${HNA_USER_AGREEMENT_ZH:-}" "${HNA_USER_AGREEMENT_EN:-}" \
    "$release_source_archive" "$release_sbom" "$release_security_report" \
    "${HNA_HUAWEI_VPN_REVIEW_EVIDENCE:-}"; do
    [[ -n "$approval_input" && -s "$approval_input" ]] || approval_inputs_ok=0
  done
  approval_evidence_args=(
    --evidence "huawei-vpn-category-review=${HNA_HUAWEI_VPN_REVIEW_EVIDENCE:-}"
  )
  if [[ "$market" == "cn" ]]; then
    for approval_input in "${HNA_CN_APP_FILING_EVIDENCE:-}" \
      "${HNA_CN_COPYRIGHT_EVIDENCE:-}" "${HNA_CN_TELECOM_LEGAL_REVIEW:-}"; do
      [[ -n "$approval_input" && -s "$approval_input" ]] || approval_inputs_ok=0
    done
    approval_evidence_args+=(
      --evidence "cn-app-filing=${HNA_CN_APP_FILING_EVIDENCE:-}"
      --evidence "cn-app-copyright=${HNA_CN_COPYRIGHT_EVIDENCE:-}"
      --evidence "cn-telecom-vpn-legal-review=${HNA_CN_TELECOM_LEGAL_REVIEW:-}"
    )
  else
    for approval_input in "${HNA_HUAWEI_OVERSEAS_PHONE_EVIDENCE:-}" \
      "${HNA_EXPORT_REVIEW_EVIDENCE:-}"; do
      [[ -n "$approval_input" && -s "$approval_input" ]] || approval_inputs_ok=0
    done
    approval_evidence_args+=(
      --evidence "huawei-overseas-phone-eligibility=${HNA_HUAWEI_OVERSEAS_PHONE_EVIDENCE:-}"
      --evidence "encryption-export-control-review=${HNA_EXPORT_REVIEW_EVIDENCE:-}"
    )
  fi
  if [[ "$approval_inputs_ok" -eq 1 ]] &&
      python3 scripts/verify_release_approval.py \
        --approval "$HNA_RELEASE_APPROVAL" \
        --signature "$HNA_RELEASE_APPROVAL_SIGNATURE" \
        --trusted-key "$HNA_RELEASE_APPROVAL_TRUSTED_KEY" \
        --market "$market" --bundle "$current_bundle_name" \
        --version-code "$current_version_code" --version-name "$current_version_name" \
        --git-commit "$current_git_commit" --app "$app_pack" \
        --release-manifest "$release_manifest" \
        --privacy-policy-zh "$HNA_PRIVACY_POLICY_ZH" \
        --privacy-policy-en "$HNA_PRIVACY_POLICY_EN" \
        --user-agreement-zh "$HNA_USER_AGREEMENT_ZH" \
        --user-agreement-en "$HNA_USER_AGREEMENT_EN" \
        --corresponding-source "$release_source_archive" \
        --sbom "$release_sbom" --security-report "$release_security_report" \
        "${approval_evidence_args[@]}" > "$tmp_dir/approval-verification.json" 2>/dev/null &&
      [[ -s "$tmp_dir/approval-verification.json" ]]; then
    pass "Git-external Ed25519 approval binds this exact release and market evidence set"
  else
    fail "missing, invalid, stale, replayed, or mismatched signed release approval"
  fi
fi

if [[ "$skip_tests" -eq 1 ]]; then
  fail "local regression tests were skipped; --skip-tests is diagnostic-only"
else
  if scripts/run_domain_tests.sh >/dev/null 2>&1; then
    pass "ArkTS/domain regression tests pass"
  else
    fail "ArkTS/domain regression tests fail"
  fi

  if scripts/core_smoke_test.sh >/dev/null 2>&1; then
    pass "HarmonyOS sing-box/gVisor adaptation smoke tests pass"
  else
    fail "HarmonyOS sing-box/gVisor adaptation smoke tests fail"
  fi

  ohos_go="$project_root/third_party/ohos-golang-go-1.24/bin/go"
  if [[ -x "$ohos_go" ]]; then
    if (cd core/go && GOTOOLCHAIN=local "$ohos_go" test ./...) >/dev/null 2>&1; then
      pass "patched OpenHarmony Go/sing-box tests pass"
    else
      fail "patched OpenHarmony Go/sing-box tests fail"
    fi
  else
    fail "patched OpenHarmony Go toolchain is missing"
  fi
fi

echo
echo "Summary: $failures blocked, $warnings warning(s)"
if [[ "$failures" -ne 0 ]]; then
  echo "NOT READY for AppGallery submission"
  exit 1
fi

echo "STATIC GATE PASSED"
echo "This does not replace AppGallery integration/cloud tests, real-device acceptance,"
echo "legal approval, export classification, or Huawei manual review."
