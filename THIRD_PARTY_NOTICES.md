# Third-party source notices

This is an unofficial HarmonyOS port, not endorsed by SagerNet. The application includes locally modified source; the accompanying corresponding-source archive contains those modifications, not merely upstream links.

| Component | Source/version | Notice |
| --- | --- | --- |
| sing-box core | https://github.com/SagerNet/sing-box — v1.14.3, 7054cac5124465ffdb145870d7c01885566711b1 | GPL-3.0-or-later and upstream additional naming/association terms; third_party/sing-box/LICENSE |
| Android SFA reference/icons | https://github.com/SagerNet/sing-box-for-android — ae93152f21457723af77d144f28c1f7be7362aec | Upstream license in third_party/sfa-for-android/LICENSE |
| App base | https://github.com/AI-Scarlett/HarmonyOS_VPN — b7a75930d2bfa82310ccaa486bb42480670d33d2 | Local derivative retained under repository LICENSE |
| gVisor fork | https://github.com/SagerNet/gvisor — e9989ea3436fa7e226f61a2bcd64f38fb42b23d4 | Apache-2.0; third_party/gvisor/LICENSE |
| OHOS Go port / Go | https://github.com/yourblacksky/ohos_golang_go — e7463379a44ed8573623117d4325dd95d0e2cd01; Go 1.25.12 | BSD-style license and PATENTS; third_party/ohos-go/LICENSE and PATENTS |

User-supplied research/visual references: https://github.com/tljk/FlClash-ohos and https://github.com/miramira8295/TelegramForHarmony. They are references, not the runtime UI framework of this port. Blur uses ArkUI native materials. HarmonyOS SDK / Scan Kit are provided by Huawei and are not redistributed in this source package.

Transitive Go dependencies and versions remain in core/go/go.mod and go.sum; each retains its upstream license. Exact build metadata and local runtime fix are recorded in BUILD-MANIFEST.json. No private device configurations, recordings, signing material, or application inventory are included in the corresponding-source distribution.
