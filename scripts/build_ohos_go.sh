#!/usr/bin/env bash
set -euo pipefail

# Rebuild the ignored host binaries for the pinned OpenHarmony Go toolchain.
# This is the first step after a clean checkout; build_core.sh then performs the
# full source, vendor, binary-version, and patch verification gate.

project_root="$(cd "$(dirname "$0")/.." && pwd)"
toolchain_root="$project_root/third_party/ohos-golang-go-1.24"
source_root="$toolchain_root/src"

python3 "$project_root/scripts/core_vendor.py" verify-toolchain-source

if [[ ! -x "$source_root/make.bash" ]]; then
  echo "BLOCKED: pinned OHOS Go make.bash is missing or not executable"
  exit 1
fi

if [[ -n "${HNA_GOROOT_BOOTSTRAP:-}" ]]; then
  bootstrap_root="$HNA_GOROOT_BOOTSTRAP"
else
  bootstrap_go="$(command -v go || true)"
  if [[ -z "$bootstrap_go" ]]; then
    echo "BLOCKED: bootstrap Go is unavailable; install Go or set HNA_GOROOT_BOOTSTRAP"
    exit 1
  fi
  bootstrap_root="$(go env GOROOT)"
fi

if [[ ! -x "$bootstrap_root/bin/go" ]]; then
  echo "BLOCKED: HNA_GOROOT_BOOTSTRAP does not contain bin/go"
  exit 1
fi

expected_bootstrap_version="$(python3 "$project_root/scripts/core_vendor.py" field ohos_go.bootstrap_version)"
actual_bootstrap_version="$("$bootstrap_root/bin/go" version 2>/dev/null | awk '{print $3}')"
if [[ -z "$expected_bootstrap_version" || "$actual_bootstrap_version" != "$expected_bootstrap_version" ]]; then
  echo "BLOCKED: bootstrap Go version does not match third_party/core-lock.json"
  exit 1
fi

python3 "$project_root/scripts/verify_build_toolchain.py" bootstrap \
  --goroot "$bootstrap_root"

(
  cd "$source_root"
  GOROOT_BOOTSTRAP="$bootstrap_root" ./make.bash
)

python3 "$project_root/scripts/core_vendor.py" verify-local
echo "BUILT   $toolchain_root/bin/go"
"$toolchain_root/bin/go" version
