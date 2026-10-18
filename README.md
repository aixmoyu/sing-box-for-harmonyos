# sing-box for HarmonyOS

非官方 HarmonyOS 原生移植，界面参考 sing-box for Android。与 SagerNet 无官方关联，也不代表上游项目。

- 应用版本：0.2.7；内核：sing-box 1.14.3。
- 开发目标：Pura X，HarmonyOS 7.0.0.109；构建 SDK API 26，最低 API 22。
- 提供未签名 HAP，需要自行签名。覆盖安装须使用原有签名身份。

## 功能

VPN Extension 后台运行；本地/远程 sing-box JSON 配置；实时流量与活动连接；规则/直连/全局模式；折叠策略组与 URLTest 延迟；深浅色与原生模糊材质。

0.2.7 更新：分应用页参考 v2rayNG，提供启用开关、绕行模式、图标／名称／包名复选列表、搜索、全选／反选和系统应用过滤；首次启动和保存设置后重启均先判断 SSID 排除，挂起时不创建 TUN、不启动核心。完整应用枚举已接入真实接口，但仍需要获批的签名 ACL，未解决普通签名的权限限制。

扫码支持 `sing-box://import-remote-profile?url=<编码的 HTTPS URL>#<编码的名称>`，字段格式与 SFA/libbox 一致；也可读取完整 JSON。当前不支持动态 QRS、Clash YAML 或单节点 URI。扫描后须在编辑页保存，才下载远程配置。

“按需连接”在会话已启动后，每约 5 秒检查排除 SSID。连接排除 Wi-Fi 时停止代理内核并释放系统 TUN，界面显示“挂起中”；离开后由仍存活的 VPN Extension 重新建立 VPN 并恢复原模式。运行期间 SSID 读取失败或隐藏时保持当前状态；启动时若无法确认已配置的 SSID 规则，则停止启动，避免绕过排除策略。手动停止后不会自动重启。系统是否允许释放 TUN 后持续保留 Extension，以及跨网络恢复行为，仍需目标真机验证。原版直连 SSID 列表迁移为排除列表，旧代理列表和默认模式不再控制连接。

分应用规则在 SSID 未挂起时生效：关闭分应用或未选择应用时代理全部；普通模式仅代理勾选项（trustedApplications）；绕行模式排除勾选项（blockedApplications）。两种系统名单互斥；API23+ 最多 256 项。从分应用页返回时保存并重建 VPN，重建前再次判断 SSID；若命中排除，全部应用不代理。Android 容器内部应用不保证能独立分流。

## 应用列表与签名

完整列表使用手机可用的兼容 API `bundle.getAllApplicationInfo`，先检查 `GET_BUNDLE_INFO_PRIVILEGED`。该权限为 system_basic、system_grant，需获批的签名描述文件 ACL；普通 normal 签名、空 allowed-acls 无法读取。API26 的 `getInstalledBundleList` 在本 SDK 标为 enterprise/2in1 能力，未误用于手机。

默认 HAP 可用普通签名测试界面与路由；它不声称具备自动读取应用列表权限。另有 `requires-acl` HAP，增加必要权限声明，仅供已有获批描述文件的用户签名测试；声明权限本身不会获得权限，普通签名可能安装失败。界面明确报告缺失签名权限，不会将导入名单或缓存冒充系统扫描。详细说明见 `docs/permissions/README.md`。

## 验证范围

158 项相关 Node 检查通过，包含生产 Extension 方法的模拟 OS/内核生命周期测试；Release HAP 编译通过。更广的旧工具链/发布脚本测试受本机缺少命令和平台假设限制，未全部通过。0.2.7 未经签名真机端到端验证，尤其获批 ACL 后的真机应用枚举、分应用范围、释放 TUN 后的后台存活及自动恢复。普通签名缺少 ACL 是确定的阻塞，不能通过编译或模拟测试视为已解决。

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

