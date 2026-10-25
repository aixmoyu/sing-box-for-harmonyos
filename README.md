# sing-box for HarmonyOS

非官方鸿蒙原生移植，界面参考 sing-box for Android。与 SagerNet 无官方关联。

- 稳定渠道：应用 **0.80**，上游正式内核 **1.14.4**。
- Beta 渠道：应用 **0.80-beta**，上游预发布内核 **1.15.0-alpha.13**。
- 渠道按上游内核区分，不能代表所有真机测试已经完成。
- 目标设备：Pura X / HarmonyOS 7.0.0.109；SDK API26，最低兼容 API22。
- 下载：[GitHub Releases](https://github.com/being123321/sing-box-for-harmonyos/releases)。HAP 未签名，需沿用原签名覆盖安装；不要卸载或清除数据。稳定版与 Beta 包名不同，分别保存数据。

## 本次更新

修复独立节点测速初始化与物理网络 DNS 选择；基础配置菜单展开后显示节点、分流模式；WebRTC 防护独立菜单和禁用 STUN 开关；GitHub 同渠道更新提示；保留原加密配置、节点和设置。

详见 [0.80 更新说明](docs/releases/0.80.md)。相关39项测试通过，完整测试仍有45项与原基线相同的历史失败；新包需完成签名后真机回归。原截图中的 IPv6 暴露尚未解决，不能把无候选或 IPv6 检测失败当作通过。研究记录见 [WebRTC 实现对照](docs/WebRTC-investigation.md)。

## 使用

工具／设置 → 基础配置 → 节点选择，可通过链接、二维码、订阅、手动表单和 sing-box JSON 导入节点；模式选择支持 GFW 与大陆以外分流。也可直接导入自己的完整 sing-box JSON。策略组选择与仪表盘直连／规则／全局模式会持久化。

按需连接命中排除 SSID 时停止代理内核并释放 TUN，优先于分应用代理；手动测速不自动恢复 VPN。完整应用列表依赖获批的 GET_BUNDLE_INFO_PRIVILEGED 签名授权，普通签名不保证枚举全部应用。

WebRTC 禁用 STUN 在规则／全局模式拦截可识别的 UDP STUN；直连模式、SSID 挂起及排除应用保留直连语义。浏览器本地候选和系统 IPv6 接管需另外验证。

## 构建与许可证

完整对应源码 ZIP 包含修改后的 sing-box、gVisor、OHOS Go 和 SFA 参考源码，来源及二进制哈希见 BUILD-MANIFEST.json。需要 DevEco SDK API26 和修改后的 OHOS Go 工具链；普通上游 Go 无法直接替代。core/go/go.mod 使用 third_party 相对路径。根据 BUILD-THIS-VERSION.md 配置工具路径，在 DevEco 安装依赖后构建 entry Release HAP。

GPL-3.0-or-later，第三方声明见 THIRD_PARTY_NOTICES.md。个人签名材料、订阅和设备报告不得提交。
