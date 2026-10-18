# sing-box for HarmonyOS

非官方 HarmonyOS 原生移植，界面参考 sing-box for Android。与 SagerNet 无官方关联，也不代表上游项目。

- 应用版本：0.2.6；内核：sing-box 1.14.3。
- 开发目标：Pura X，HarmonyOS 7.0.0.109；构建 SDK API 26，最低 API 22。
- 提供未签名 HAP，需要自行签名。覆盖安装须使用原有签名身份。

## 功能

VPN Extension 后台运行；本地/远程 sing-box JSON 配置；实时流量与活动连接；规则/直连/全局模式；折叠策略组与 URLTest 延迟；深浅色与原生模糊材质。

0.2.6 更新：加密配置使用完整写入、刷新和关闭后验证的候选文件流程，处理首次启动的配置读取问题；无效二维码使用中文“注意／确定”弹窗；按需运行改为排除 SSID 列表、居中添加弹窗、全选与删除；页眉、状态栏和悬浮底栏使用透明背景采样材质。

扫码支持 `sing-box://import-remote-profile?url=<编码的 HTTPS URL>#<编码的名称>`，字段格式与 SFA/libbox 一致；也可读取完整 JSON。当前不支持动态 QRS、Clash YAML 或单节点 URI。扫描后须在编辑页保存，才下载远程配置。

“按需连接”在会话已启动后，每约 5 秒检查排除 SSID。连接排除 Wi-Fi 时停止代理内核并释放系统 TUN，界面显示“挂起中”；离开后由仍存活的 VPN Extension 重新建立 VPN 并恢复原模式。SSID 读取失败或隐藏时保持当前状态。手动停止后不会自动重启。系统是否允许释放 TUN 后持续保留 Extension，以及跨网络恢复行为，仍需目标真机验证。原版直连 SSID 列表迁移为排除列表，旧代理列表和默认模式不再控制连接。

分应用代理通过系统 `trustedApplications` 设置生效，支持全部应用或仅所选鸿蒙包名。部分系统不向普通应用返回其他应用的枚举结果，此时需导入每行一个包名的应用清单或手动输入；当前未解决系统完整应用枚举权限限制。Android 容器内部应用不保证能独立分流。个人设备清单不属于本公开仓库。

## 验证范围

152 项相关 Node 检查通过，包含生产 Extension 方法的模拟 OS/内核生命周期测试；Release HAP 编译通过。更广的旧工具链/发布脚本测试受本机缺少命令和平台假设限制，未全部通过。0.2.6 未经签名真机端到端验证，尤其首次点击启动、释放 TUN 后的后台存活、自动恢复及玻璃观感。

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
