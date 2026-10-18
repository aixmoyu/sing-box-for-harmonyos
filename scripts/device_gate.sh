#!/usr/bin/env bash
set -euo pipefail

hdc_bin="$(command -v hdc 2>/dev/null || true)"
if [[ -z "$hdc_bin" && -x "/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc" ]]; then
  hdc_bin="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
fi

if [[ -z "$hdc_bin" ]]; then
  echo "BLOCKED: hdc is unavailable. Install DevEco Studio with the API 26 build toolchain first."
  exit 1
fi

targets="$($hdc_bin list targets -v | tr -d '\r')"
if [[ -z "$targets" || "$targets" == "[Empty]" ]]; then
  echo "BLOCKED: no HarmonyOS device is connected."
  exit 1
fi

echo "Connected targets:"
echo "$targets"
echo
echo "Manual Phase 0 evidence still required:"
echo "1. API 22 minimum-device and API 26 target-device VPN authorization/system indicator"
echo "2. TUN fd duplication and deterministic close ownership"
echo "3. sing-box IPv4 TCP, UDP and DNS forwarding"
echo "4. public NetConn per-FD underlay binding prevents the core's outbound loop"
echo "5. Wi-Fi/cellular recovery and 30-minute fd/thread/goroutine stability"
echo
echo "This script only proves device visibility; it does not mark the VPN gate passed."
