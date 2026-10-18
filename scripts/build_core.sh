#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
source "$project_root/scripts/core_build_env.sh"
deveco_app="${HNA_DEVECO_HOME:-/Applications/DevEco-Studio.app}"
deveco_contents="$deveco_app/Contents"
ohos_go="$project_root/third_party/ohos-golang-go-1.24/bin/go"
ohos_clang="$deveco_contents/sdk/default/openharmony/native/llvm/bin/aarch64-unknown-linux-ohos-clang"
core_dir="$project_root/core/go"
output_path="$core_dir/out/libharmonycore.so"

"$project_root/scripts/verify_core_vendor.sh"
python3 "$project_root/scripts/verify_build_toolchain.py" deveco \
  --contents "$deveco_contents"

for required in "$ohos_go" "$ohos_clang"; do
  if [[ ! -x "$required" ]]; then
    echo "BLOCKED: missing executable: $required"
    exit 1
  fi
done

mkdir -p "$core_dir/out"
cd "$core_dir"

sing_box_version="$(python3 "$project_root/scripts/core_vendor.py" field sing_box.version)"
sing_box_ld_version="${sing_box_version#v}"

# Use the exact patched OHOS Go toolchain for host-side regression tests. This
# catches standard-library fork regressions (notably PEM/root-certificate
# loading) before they are embedded into the ARM64 shared library.
GOTOOLCHAIN=local GOFLAGS=-mod=readonly \
  "$ohos_go" test -tags "$HNA_CORE_BUILD_TAGS" ./...

GOTOOLCHAIN=local \
GOOS=openharmony \
GOARCH=arm64 \
CGO_ENABLED=1 \
CC="$ohos_clang" \
"$ohos_go" build \
  -p=1 \
  -mod=readonly \
  -buildmode=c-shared \
  -buildvcs=false \
  -trimpath \
  -tags "$HNA_CORE_BUILD_TAGS" \
  -ldflags "-X github.com/sagernet/sing-box/constant.Version=$sing_box_ld_version -s -w -buildid= -checklinkname=0" \
  -o "$output_path" \
  .

echo "BUILT   $output_path"
file "$output_path"
shasum -a 256 "$output_path"
