# sing-box for HarmonyOS

非官方 HarmonyOS 原生移植，界面参考 sing-box for Android。与 SagerNet 无官方关联，也不代表上游项目。

- 应用版本：0.2.5；内核：sing-box 1.14.3。
- 开发目标：Pura X，HarmonyOS 7.0.0.109；构建 SDK API 26，最低 API 22。
- 提供未签名 HAP，需要自行签名。覆盖安装须使用原有签名身份。

## 功能

VPN Extension 后台运行；本地/远程 sing-box JSON 配置；实时流量与活动连接；规则/直连/全局模式；折叠策略组与 URLTest 延迟；深浅色与原生模糊材质。

0.2.5 新增：顶部标题与系统栏沉浸式处理；安卓版三项添加配置菜单；相机/相册扫码；SSID 匹配切换模式；开源项目和本项目仓库入口。

扫码支持 `sing-box://import-remote-profile?url=<编码的 HTTPS URL>#<编码的名称>`，字段格式与 SFA/libbox 一致；也可读取完整 JSON。当前不支持动态 QRS、Clash YAML 或单节点 URI。扫描后须在编辑页保存，才下载远程配置。

“按需连接”在 VPN 已运行时，每约 5 秒读取 Wi-Fi SSID并切换直连/全局模式；可配置未匹配和移动网络的默认策略。SSID不可读取时保持当前模式。关闭 VPN 后不会自动重新启动。直连模式保留系统 VPN 通道，DNS设置沿用导入配置。

分应用代理通过系统 `trustedApplications` 设置生效，支持全部应用或仅所选鸿蒙包名。部分系统不向普通应用返回其他应用的枚举结果，此时需导入每行一个包名的应用清单或手动输入；当前未解决系统完整应用枚举权限限制。Android 容器内部应用不保证能独立分流。个人设备清单不属于本公开仓库。

## 验证范围

145 项 Node 检查通过；Release HAP 编译通过。前版0.2.2基础VPN连接得到使用者确认。0.2.5 的沉浸式布局、相机扫码、SSID后台切换和分应用范围尚未经过签名真机端到端验证；不宣称与安卓版完全一致。

## 构建

完整对应源码包包含 app、修改后的 sing-box、gVisor、OHOS Go 和 SFA参考源码。构建来源见 `BUILD-MANIFEST.json` / `LOCAL_BUILD_PROVENANCE.json`。

1. 安装 DevEco Studio / HarmonyOS SDK API 26。
2. 从 `third_party/ohos-go` 构建 OHOS Go 工具链，或使用与清单提交一致的工具链；普通上游 Go 无法直接替代。
3. 根据 `build-core.ps1` 指定 SDK和OHOS Go路径，构建 arm64 `core/go/out/libharmonycore.so`。所需Go模块必须可下载/已缓存。
4. 使用 DevEco Studio 打开工程，安装依赖，再构建 entry Release HAP。`build-hap.ps1`是当前构建环境脚本，异机需调整工具路径。
5. 使用自己的签名配置签名；签名文件和个人节点配置不得提交到仓库。

`core/go/go.mod` 在对应源码包中使用 `third_party` 相对路径。许可和上游来源见 `LICENSE`、`THIRD_PARTY_NOTICES.md`。HAP和完整对应源码应使用相同版本。

## 项目地址

https://github.com/being123321/sing-box-for-harmonyos
