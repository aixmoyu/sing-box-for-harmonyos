#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/prepare_core_upgrade.sh reproduce <sing-box|gvisor|ohos-go> <new-directory>
  scripts/prepare_core_upgrade.sh candidate <sing-box|gvisor|ohos-go> <new-directory>
  scripts/prepare_core_upgrade.sh resolve-sing-box <tag>
  scripts/prepare_core_upgrade.sh resolve-gvisor <module-version>
  scripts/prepare_core_upgrade.sh resolve-ohos-go <tag>

`reproduce` downloads exactly one immutable component from core-lock.json,
verifies tag/commit/tree or module identities and patch hashes, applies its
checked-in patch, and requires the result to match the lock. The candidate is
built in a temporary sibling and atomically renamed. The destination must be a
new path outside the repository; this command never replaces third_party.

For a new upstream version, first use the resolve command, update a dedicated
branch's lock and patch, then use `candidate` for only the component being
upgraded. Review and pin its reported result digest, rerun `reproduce`, and
execute core_smoke_test.sh. No multi-component or in-repository staging exists.
USAGE
}

if [[ "$#" -lt 2 ]]; then
  usage
  exit 2
fi

project_root="$(cd "$(dirname "$0")/.." && pwd)"
command="$1"
value="$2"

case "$command" in
  reproduce)
    if [[ "$#" -ne 3 ]]; then
      usage
      exit 2
    fi
    python3 "$project_root/scripts/core_vendor.py" stage-component "$value" "$3"
    ;;
  candidate)
    if [[ "$#" -ne 3 ]]; then
      usage
      exit 2
    fi
    python3 "$project_root/scripts/core_vendor.py" stage-component \
      --allow-unpinned-result "$value" "$3"
    ;;
  resolve-sing-box)
    if [[ "$#" -ne 2 ]]; then
      usage
      exit 2
    fi
    python3 "$project_root/scripts/core_vendor.py" resolve-sing-box "$value"
    ;;
  resolve-gvisor)
    if [[ "$#" -ne 2 ]]; then
      usage
      exit 2
    fi
    python3 "$project_root/scripts/core_vendor.py" resolve-gvisor "$value"
    ;;
  resolve-ohos-go)
    if [[ "$#" -ne 2 ]]; then
      usage
      exit 2
    fi
    python3 "$project_root/scripts/core_vendor.py" resolve-ohos-go "$value"
    ;;
  *)
    usage
    exit 2
    ;;
esac
