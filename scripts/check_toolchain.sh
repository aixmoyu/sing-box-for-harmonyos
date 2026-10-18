#!/usr/bin/env bash
set -u

project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_missing=0
direct_build_blocked=0
core_missing=0

echo "HarmonyOS 网络助手工具链检查"
echo "编译/目标 SDK: API 26；最低兼容 SDK: API 22"

deveco_path=""
for candidate in \
  "/Applications/DevEco-Studio.app" \
  "/Applications/DevEco Studio.app" \
  "$HOME/Applications/DevEco-Studio.app" \
  "$HOME/Applications/DevEco Studio.app"; do
  if [[ -d "$candidate" ]]; then
    deveco_path="$candidate"
    break
  fi
done

if [[ -z "$deveco_path" ]]; then
  echo "MISSING DevEco Studio with API 26 SDK"
  app_missing=1
else
  deveco_contents="$deveco_path/Contents"
  node_bin="$deveco_contents/tools/node/bin/node"
  ohpm_bin="$deveco_contents/tools/ohpm/bin/ohpm"
  hvigor_bin="$deveco_contents/tools/hvigor/bin/hvigorw"
  hdc_bin="$deveco_contents/sdk/default/openharmony/toolchains/hdc"
  sdk_manifest="$deveco_contents/sdk/default/sdk-pkg.json"

  echo "OK      DevEco Studio: $deveco_path"
  for tool_path in "$node_bin" "$ohpm_bin" "$hvigor_bin" "$hdc_bin"; do
    if [[ -x "$tool_path" ]]; then
      echo "OK      bundled tool: $tool_path"
    else
      echo "MISSING bundled tool: $tool_path"
      app_missing=1
    fi
  done

  if [[ -x "$node_bin" && -f "$sdk_manifest" ]]; then
    sdk_info="$($node_bin -e 'const fs=require("fs");const p=process.argv[1];const d=JSON.parse(fs.readFileSync(p,"utf8")).data;process.stdout.write(`${d.displayName}; api=${d.apiVersion}; version=${d.version}; release=${d.releaseType}`)' "$sdk_manifest")"
    echo "OK      SDK: $sdk_info"
    if [[ "$sdk_info" != *"api=26"* ]]; then
      echo "MISSING API 26 SDK"
      app_missing=1
    fi
  else
    echo "MISSING SDK manifest: $sdk_manifest"
    app_missing=1
  fi
fi

if LC_ALL=C printf '%s' "$project_root" | grep -q '[^-A-Za-z0-9_./@() ]'; then
  echo "BLOCKED direct Hvigor build: project path contains unsupported characters: $project_root"
  echo "        Move/rename it to an ASCII path such as Documents/HarmonyOS-Network-Assistant."
  direct_build_blocked=1
else
  echo "OK      project path is accepted by Hvigor"
fi

if grep -q '"targetSdkVersion"[[:space:]]*:[[:space:]]*"26\.0\.0"' "$project_root/build-profile.json5" &&
  grep -q '"compatibleSdkVersion"[[:space:]]*:[[:space:]]*"6\.0\.2(22)"' "$project_root/build-profile.json5"; then
  echo "OK      build-profile target API 26 / minimum API 22"
else
  echo "MISSING API 26 target or API 22 minimum in build-profile.json5"
  app_missing=1
fi

ohos_go="$project_root/third_party/ohos-golang-go-1.24/bin/go"
core_library="$project_root/core/go/out/libharmonycore.so"
if [[ -x "$ohos_go" ]]; then
  echo "OK      OpenHarmony Go: $($ohos_go version)"
else
  echo "MISSING project OpenHarmony Go toolchain: $ohos_go"
  core_missing=1
fi

if [[ -f "$core_library" ]]; then
  echo "OK      sing-box OHOS core: $core_library"
else
  echo "MISSING sing-box OHOS core; run scripts/build_core.sh"
  core_missing=1
fi

if [[ "$app_missing" -ne 0 || "$direct_build_blocked" -ne 0 ]]; then
  echo "RESULT  APP BUILD BLOCKED"
  [[ "$core_missing" -eq 0 ]] || echo "RESULT  CORE BUILD BLOCKED"
  exit 1
fi

echo "RESULT  APP TOOLCHAIN READY"
[[ "$core_missing" -eq 0 ]] || echo "RESULT  CORE TOOLCHAIN INCOMPLETE"
