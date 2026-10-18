#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
deveco_app="${HNA_DEVECO_HOME:-/Applications/DevEco-Studio.app}"
deveco_contents="$deveco_app/Contents"
node_dir="$deveco_contents/tools/node/bin"
ohpm_bin="$deveco_contents/tools/ohpm/bin/ohpm"
hvigor_bin="$deveco_contents/tools/hvigor/bin/hvigorw"
sdk_root="$deveco_contents/sdk/default"

for required in "$node_dir/node" "$ohpm_bin" "$hvigor_bin"; do
  if [[ ! -x "$required" ]]; then
    echo "BLOCKED: missing DevEco bundled tool: $required"
    exit 1
  fi
done

if [[ -n "${HNA_GOROOT_BOOTSTRAP:-}" ]]; then
  bootstrap_root="$HNA_GOROOT_BOOTSTRAP"
else
  bootstrap_root="$(go env GOROOT 2>/dev/null || true)"
fi
if [[ -z "$bootstrap_root" ]]; then
  echo "BLOCKED: bootstrap Go root could not be resolved"
  exit 1
fi
python3 "$project_root/scripts/verify_build_toolchain.py" all \
  --goroot "$bootstrap_root" --contents "$deveco_contents"
"$project_root/scripts/build_ohos_go.sh"
"$project_root/scripts/verify_core_vendor.sh"
"$project_root/scripts/core_smoke_test.sh"
"$project_root/scripts/build_core.sh"
rebuilt_core="$project_root/core/go/out/libharmonycore.so"
if [[ ! -f "$rebuilt_core" ]]; then
  echo "BLOCKED: native core rebuild did not produce libharmonycore.so"
  exit 1
fi
rebuilt_core_sha="$(shasum -a 256 "$rebuilt_core" | awk '{print $1}')"

build_root="$project_root"
temporary_root=""
if LC_ALL=C printf '%s' "$project_root" | grep -q '[^-A-Za-z0-9_./@() ]'; then
  temporary_root="$(mktemp -d /tmp/harmony-net-assistant-build.XXXXXX)"
  trap 'rm -rf "$temporary_root"' EXIT
  echo "INFO    Hvigor rejects the current non-ASCII project path."
  echo "INFO    Building an isolated copy at: $temporary_root"
  rsync -a \
    --exclude='.git/' \
    --exclude='.hvigor/' \
    --exclude='oh_modules/' \
    --exclude='entry/build/' \
    --exclude='artifacts/' \
    "$project_root/" "$temporary_root/"
  build_root="$temporary_root"
fi

export PATH="$node_dir:$deveco_contents/tools/ohpm/bin:$deveco_contents/tools/hvigor/bin:$sdk_root/openharmony/toolchains:$PATH"
export DEVECO_SDK_HOME="$deveco_contents/sdk"
export HARMONYOS_SDK_HOME="$sdk_root"

cd "$build_root"
"$ohpm_bin" install
"$hvigor_bin" clean --no-daemon
"$hvigor_bin" assembleHap \
  --mode module \
  -p product=default \
  -p module=entry@default \
  -p buildMode=debug \
  --analyze=normal \
  --parallel \
  --incremental \
  --no-daemon

output_dir="$build_root/entry/build/default/outputs/default"
if [[ -f "$output_dir/entry-default-signed.hap" ]]; then
  hap_path="$output_dir/entry-default-signed.hap"
elif [[ -f "$output_dir/entry-default-unsigned.hap" ]]; then
  hap_path="$output_dir/entry-default-unsigned.hap"
else
  echo "BLOCKED: Hvigor finished without an entry-default HAP in: $output_dir"
  exit 1
fi

packaged_core_entries="$(unzip -Z1 "$hap_path" | grep -c '^libs/arm64-v8a/libharmonycore\.so$' || true)"
if [[ "$packaged_core_entries" -ne 1 ]]; then
  echo "BLOCKED: debug HAP must contain exactly one ARM64 libharmonycore.so"
  exit 1
fi
staged_core_count="$(find "$build_root/entry/build/default/intermediates" \
  -path '*/libs/*/arm64-v8a/libharmonycore.so' -type f | wc -l | tr -d ' ')"
if [[ "$staged_core_count" -ne 1 ]]; then
  echo "BLOCKED: expected exactly one staged unstripped native core from this debug build"
  exit 1
fi
staged_core="$(find "$build_root/entry/build/default/intermediates" \
  -path '*/libs/*/arm64-v8a/libharmonycore.so' -type f | head -n 1)"
staged_core_sha="$(shasum -a 256 "$staged_core" | awk '{print $1}')"
if [[ "$rebuilt_core_sha" != "$staged_core_sha" ]]; then
  echo "BLOCKED: staged debug core differs from the freshly rebuilt native core"
  exit 1
fi
stripped_core_count="$(find "$build_root/entry/build/default/intermediates" \
  -path '*/stripped_native_libs/*/arm64-v8a/libharmonycore.so' -type f | wc -l | tr -d ' ')"
if [[ "$stripped_core_count" -ne 1 ]]; then
  echo "BLOCKED: expected exactly one stripped native core from this debug build"
  exit 1
fi
stripped_core="$(find "$build_root/entry/build/default/intermediates" \
  -path '*/stripped_native_libs/*/arm64-v8a/libharmonycore.so' -type f | head -n 1)"
packaged_core_sha="$(unzip -p "$hap_path" 'libs/arm64-v8a/libharmonycore.so' | shasum -a 256 | awk '{print $1}')"
stripped_core_sha="$(shasum -a 256 "$stripped_core" | awk '{print $1}')"
if [[ "$packaged_core_sha" != "$stripped_core_sha" ]]; then
  echo "BLOCKED: packaged debug core differs from this build's stripped native core"
  exit 1
fi

artifact_dir="$project_root/artifacts/debug"
mkdir -p "$artifact_dir"
artifact_path="$artifact_dir/$(basename "$hap_path")"
cp "$hap_path" "$artifact_path"
echo "BUILT   $artifact_path"
shasum -a 256 "$artifact_path"
echo "CORE    $packaged_core_sha"
if [[ "$artifact_path" == *-unsigned.hap ]]; then
  echo "NOTE    This artifact is unsigned; configure DevEco automatic signing before device installation."
fi
