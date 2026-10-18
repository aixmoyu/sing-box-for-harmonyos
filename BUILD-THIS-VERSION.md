# sing-box for HarmonyOS

非官方 HarmonyOS 原生移植，界面参考 sing-box for Android。与 SagerNet 无官方关联，也不代表上游项目。

- 应用版本：0.2.10；内核：sing-box 1.14.3。
- 开发目标：Pura X，HarmonyOS 7.0.0.109；构建 SDK API 26，最低 API 22。
- 提供未签名 HAP，需要自行签名。覆盖安装须使用原有签名身份。

## 功能

VPN Extension 后台运行；本地/远程 sing-box JSON 配置；实时流量与活动连接；规则/直连/全局模式；折叠策略组与 URLTest 延迟；深浅色与原生模糊材质。

0.2.10 更新：修复手动选择节点仅保存在运行内存、挂起／重启后回到配置默认节点的问题。节点选择和规则／全局／直连模式按配置 ID 分别写入加密用户存储；操作成功后立即保存，启动和挂起恢复时将保存的选择应用到派生运行配置，不修改用户原始 JSON。保存文件位于持久用户目录，清理临时运行快照不会删除它。仪表盘卡片显隐、策略组折叠、日志筛选和系统应用过滤也会保存；原有外观、分应用和 SSID 设置继续保留。

保留 0.2.9 的新建 VPN 连接恢复流程：挂起时停止节点代理服务，销毁系统 VPN／TUN 并丢弃旧连接对象；恢复时新建连接和 TUN、复验配置并启动新代理服务实例。启动途中再次切网时清理并等待重试。

退到后台仍暂停界面刷新、自动测速和完整运行快照，后台轻量状态采样每 15 秒、心跳每 3 秒。系统可能缓存界面进程，因此不代表只有 Go 进程或界面内存归零。

网络切换改用物理 Wi-Fi／蜂窝事件，200 毫秒合并事件并在 1200 毫秒后复查；仅实际承载网络变化时调用内核 ResetNetwork，让后续连接使用新网络，避免普通切换重建 TUN。SSID 排除先于网络重置和分应用规则；恢复前等待有效物理网络。命令使用文件事件通知，保留 2 秒看门狗；文件事件不可用时回退到 250 毫秒轮询。

扫码支持 `sing-box://import-remote-profile?url=<编码的 HTTPS URL>#<编码的名称>`，字段格式与 SFA/libbox 一致；也可读取完整 JSON。当前不支持动态 QRS、Clash YAML 或单节点 URI。扫描后须在编辑页保存，才下载远程配置。

“按需连接”在会话已启动后，通过网络事件检查排除 SSID，并在事件就绪时每 30 秒兜底检查（事件不可用时每 5 秒）。连接排除 Wi-Fi 时停止代理内核并释放系统 TUN，界面显示“挂起中”；离开后由仍存活的 VPN Extension 重新建立 VPN 并恢复原模式。运行期间 SSID 读取失败或隐藏时保持当前状态；启动时若无法确认已配置的 SSID 规则，则停止启动，避免绕过排除策略。手动停止后不会自动重启。系统是否允许释放 TUN 后持续保留 Extension，以及跨网络恢复行为，仍需目标真机验证。原版直连 SSID 列表迁移为排除列表，旧代理列表和默认模式不再控制连接。

分应用规则在 SSID 未挂起时生效：关闭分应用或未选择应用时代理全部；普通模式仅代理勾选项（trustedApplications）；绕行模式排除勾选项（blockedApplications）。两种系统名单互斥；API23+ 最多 256 项。从分应用页返回时保存并重建 VPN，重建前再次判断 SSID；若命中排除，全部应用不代理。Android 容器内部应用不保证能独立分流。

## 应用列表与签名

完整列表使用手机可用的兼容 API `bundle.getAllApplicationInfo`，先检查 `GET_BUNDLE_INFO_PRIVILEGED`。该权限为 system_basic、system_grant，需获批的签名描述文件 ACL；普通 normal 签名、空 allowed-acls 无法读取。API26 的 `getInstalledBundleList` 在本 SDK 标为 enterprise/2in1 能力，未误用于手机。

默认 HAP 可用普通签名测试界面与路由；它不声称具备自动读取应用列表权限。另有 `requires-acl` HAP，增加必要权限声明，仅供已有获批描述文件的用户签名测试；声明权限本身不会获得权限，普通签名可能安装失败。界面明确报告缺失签名权限，不会将导入名单或缓存冒充系统扫描。详细说明见 `docs/permissions/README.md`。

## 验证范围

174 项相关 Node 检查通过，包含生产 Extension 方法的模拟 OS/内核生命周期测试；Release HAP 编译通过。更广的旧工具链/发布脚本测试受本机缺少命令和平台假设限制，未全部通过。本版原生二进制与 0.2.8 一致；此前原生快照和套接字选择契约测试通过。本版新增选择持久化、隔离配置、挂起后保持手动节点和界面设置恢复模拟检查。已在手机现有 0.2.6 上发起实际策略组 URLTest，代理节点返回 693–1205 毫秒；该结果不代表 0.2.10 真机验证。0.2.10 未经签名真机端到端验证或功耗／内存对比，尤其获批 ACL 后的真机应用枚举、分应用范围、释放 TUN 后的后台存活及自动恢复。普通签名缺少 ACL 是确定的阻塞，不能通过编译或模拟测试视为已解决。

覆盖更新需要沿用原签名身份，直接覆盖安装并保留应用数据。首次使用本版后重新选择一次节点以建立保存记录；旧版未保存且已经丢失的选择无法找回。本版尚未签名真机验证跨版本安装和设置恢复，本版为测试发布，仍需目标真机验证。

## 构建

完整对应源码包包含 app、修改后的 sing-box、gVisor、OHOS Go 和 SFA参考源码。构建来源见 `BUILD-MANIFEST.json` / `LOCAL_BUILD_PROVENANCE.json`。

1. 安装 DevEco Studio / HarmonyOS SDK API 26。
2. 从 `third_party/ohos-go` 构建 OHOS Go 工具链，或使用与清单提交一致的工具链；普通上游 Go 无法直接替代。
3. 根据 `build-core.ps1` 指定 SDK和OHOS Go路径，构建 arm64 `core/go/out/libharmonycore.so`。所需Go模块必须可下载/已缓存。
4. 使用 DevEco Studio 打开工程，安装依赖，再构建 entry Release HAP。`build-hap.ps1`是当前构建环境脚本，异机需调整工具路径。
5. 使用自己的签名配置签名；签名文件和个人节点配置不得提交到仓库。

`core/go/go.mod` 在对应源码包中使用 `third_party` 相对路径。许可和上游来源见 `LICENSE`、`THIRD_PARTY_NOTICES.md`。HAP和完整对应源码应使用相同版本。

更新说明见 [0.2.10 更新说明](docs/releases/0.2.10.md)。

## 项目地址

https://github.com/being123321/sing-box-for-harmonyos

