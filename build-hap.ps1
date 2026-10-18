$ErrorActionPreference = 'Stop'
$devecoPath = 'C:\Users\Administrator\Documents\Codex\2026-10-04\new-chat\work\deveco-portable'
$env:JAVA_HOME = "$devecoPath\jbr"
$env:DEVECO_SDK_HOME = "$devecoPath\sdk"
$env:PATH = "$devecoPath\tools\node;$devecoPath\tools\node\bin;$devecoPath\tools\ohpm\bin;$env:JAVA_HOME\bin;$env:PATH"
$env:HVIGOR_USER_HOME = 'C:\Users\Administrator\Documents\Codex\2026-10-04\new-chat\work\build-user-cache\.hvigor'
Push-Location "$PSScriptRoot\HarmonyNet"
try {
  $cachedCli = "$env:HVIGOR_USER_HOME\project_caches\ec5cff68e1d01412b0bf73fdffd3a209\workspace\node_modules\@ohos\hvigor\bin\hvigor.js"
  node $cachedCli assembleHap --mode module -p product=default -p module=entry@default -p buildMode=release --no-daemon
  if ($LASTEXITCODE -ne 0) { throw "Hvigor failed: $LASTEXITCODE" }
} finally { Pop-Location }
