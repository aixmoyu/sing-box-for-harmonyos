# AppGallery / HarmonyOS 发布合规与上架准备审计

> 审计日期：2026-08-12（Asia/Shanghai）
> 审计对象：`com.harmonynet.assistant`，HarmonyOS 手机应用，API 26 编译/目标、API 22 最低兼容，VPN Extension + sing-box 1.13.18
> 文档性质：工程发布门禁和风险清单，不替代中国或目标市场执业律师、出口管制顾问及华为审核团队的正式意见。

## 1. 结论先行

### 1.1 中国大陆

**当前版本不得提交中国大陆正式上架。** 这不是因为平台不支持 VPN，而是尚有监管分类、资质、隐私安全和正式发布包四类阻塞项：

1. 该产品允许用户导入任意订阅并形成全设备 VPN/TUN 代理。是否仅属于“用户自带服务的客户端”，还是构成提供/经营 VPN、互联网接入或跨境信道，不能由项目自行认定。发布前必须取得中国大陆电信合规律师书面意见，并通过 AppGallery 工单让华为确认应用分类和所需资质。
2. 如果开发者自己提供、租用、转售节点或跨境线路，风险会从“客户端分类待确认”上升为电信业务经营许可问题。工信部《电信业务分类目录》把国内互联网虚拟专用网业务列为 B13 第一类增值电信业务；2017 年通知明确，未经电信主管部门批准，不得以专线或 VPN 等信道开展跨境经营活动。
3. 中国大陆分发需要完成 APP 备案。是否还需 ICP 许可、B13 许可或其他前置审批，要依据实际主体、收费模式、服务器和网络资源重新判断，不能用 APP 备案替代经营许可。
4. 工程已完成 HUKS AES-256-GCM 设备绑定加密，覆盖订阅目录、网络设置与运行配置；实现包含候选文件验证、回滚、旧明文最后删除、跨进程文件锁及损坏密文拒绝。API 26 真机成功建立 VPN 已证明 UI 进程写入的加密运行配置可由 VPN Extension 跨进程解密并启动核心。现有自动测试以主机故障模型覆盖迁移提交边界，但尚未在真机逐个注入写候选、验证、移动旧文件和提升候选时的崩溃；这是正式验收证据边界，不再表述为安全存储功能尚未实现。
5. 当前仅有调试签名 HAP，没有正式发布证书签名的 Release App Pack、隐私政策、用户协议、版权材料和 AppGallery 隐私标签。

因此，中国大陆路径只有在“监管和华为分类确认通过”后才继续；不能通过改名、隐藏“VPN”字样或把按钮做成远程开关规避审核。

### 1.2 中国大陆以外

**当前 HarmonyOS NEXT 手机版本也不能直接走“海外 AppGallery 先上架”。** 华为在 2026-05-27 更新的 HarmonyOS 5+ 发布区域说明中写明：目前 HarmonyOS NEXT 应用只有智能手表可全球分发，其他设备仅在中国大陆可用，即使选择其他国家/地区也无法下载。该说明出现在 HarmonyOS 游戏发布文档中，但使用的是泛指 “HarmonyOS NEXT apps”；正式立项海外手机发布前，仍应向华为提交工单，确认普通工具应用是否存在单独白名单或更新后的开放计划。

可行的海外替代路径是：

- 保留本项目为 HarmonyOS NEXT 手机版，等待华为开放或取得书面例外；或者
- 另建 Android 版并走海外 Android AppGallery。Android 包、权限、VPN Service、签名和商店政策是另一套工程，不能把当前 HAP 直接当作 Android 海外包；或者
- 先做企业内部/定向测试，不把测试分发等同于正式公开上架。

海外开放后仍需逐国判断 VPN 合法性、隐私法和加密出口管制。AppGallery 通过审核不替代当地政府许可。

### 1.3 结论置信边界

| 结论 | 置信度 | 边界 |
| --- | --- | --- |
| 当前工程未达到正式上架条件 | 高 | 可由仓库直接证明：无正式 `.app`、缺最终隐私/许可发行材料；安全存储代码和真机跨进程运行链路已成立，但逐迁移崩溃点的破坏性真机注入尚未形成证据 |
| 中国大陆手机分发需要 APP 备案及应用版权材料 | 高 | 来自工信部和华为当前公开要求；实际提交仍以主体后台显示的材料清单为准 |
| 纯“用户自带订阅”的本地客户端是否必须取得 B13/其他 VPN 牌照 | 未知，必须人工确认 | 公开一手资料没有对本产品模型给出直接分类；必须取得中国电信合规律师书面意见和华为审核工单，本文不作许可证结论 |
| HarmonyOS NEXT 手机当前不能在海外公开分发 | 中高 | 华为 2026-05-27 官方说明明确“全球仅智能手表，其他设备仅中国大陆”，但页面位于游戏发布章节；普通工具应用仍需华为工单确认适用范围及是否存在例外 |
| API 22+ 提供本工程所需 VPN Extension 技术能力 | 中高 | 本机 API 26 d.ts 起始版本审计和 ArkTS 编译已通过；API 22 真机 VPN 全链路仍是发布门禁 |
| 加密出口分类 | 未知，逐国确认 | 取决于开发/出口主体、目标国、加密实现和分发方式；必须由专业顾问形成书面记录 |

## 2. 当前工程事实

| 检查项 | 当前状态 | 发布判断 |
| --- | --- | --- |
| SDK | `compileSdkVersion` / `targetSdkVersion` 为 `26.0.0`，`compatibleSdkVersion` 为 `6.0.2(22)`；当前本机 SDK 元数据为 `26.0.0.32 Beta2` | API 22 静态兼容门禁和 ArkTS 编译已通过，但最低系统真机尚未验收；Beta SDK 不得用于正式 AppGallery 包，安装官方 API 26 Release SDK 前仍是 P0 |
| 系统 VPN 能力 | 声明非导出的 `type: "vpn"` Extension；申请 `ohos.permission.INTERNET`、`ohos.permission.GET_NETWORK_INFO` 与 `ohos.permission.GET_BUNDLE_INFO` | 技术路径符合公开 VPN Extension API；应用白名单仅查询桌面可启动应用；商店是否接受该业务仍需审核确认 |
| 设备范围 | `deviceTypes` 仅 `phone` | 只能按手机产品申报，不能把它当作已适配平板/手表 |
| 原生 ABI | 当前调试 HAP 含 `arm64-v8a` 的 `libentry.so`、`libharmonycore.so` 和 `libc++_shared.so` | 64 位 ARM 真机链路已存在；仍需 Release 包云测覆盖目标机型 |
| 包格式 | 当前产物为调试签名 `.hap` | 正式上架基本单元应为 `.app` App Pack；不能提交现有调试 HAP 充当正式版本 |
| 版本 | `versionName: 0.1.0`，`versionCode: 1000000` | 可用于开发，但正式版本必须建立不可回退的递增规则和发布记录 |
| 本地化 | 四个主 Tab 已接入中文/英文、跟随系统语言以及明暗/跟随系统主题；静态资源有 `en_US` 与 `dark` qualifier，动态错误有英文安全回退 | 编译测试已通过，仍需中英与明暗四组合真机逐页视觉验收 |
| 权限 | `INTERNET` 用于用户主动触发的订阅、VPN/DNS 和诊断联网；`GET_NETWORK_INFO` 只读取网络承载类型；`GET_BUNDLE_INFO` 只在用户打开应用白名单管理时查询桌面可启动应用的名称和包名 | 三项均有实际调用和应用内中英用途说明；应用列表只在本机处理；新增任何权限都必须重新执行最小权限与隐私审查 |
| 凭据存储 | 订阅、运行配置以及含自定义 DoH URL 的网络设置已接入 HUKS AES-256-GCM、跨进程文件锁与候选/回滚式明文迁移；损坏密文拒绝回退 | API 26 真机 VPN 连接已证明 UI→VPN Extension 跨进程加解密运行链路；主机故障模型覆盖迁移边界，尚未执行逐边界破坏性真机故障注入，应在正式验收报告中保留该证据边界 |
| 隐私材料 | 应用内已有首次中英隐私选择、拒绝后的离线受限模式、撤回、数据清除和本地开发版用户协议 | 正式运营主体、公开隐私政策/用户协议 URL、客服渠道和 AppGallery 隐私标签仍为 P0 |
| 开源合规 | 根目录完整 GPLv3、vendored 许可证、应用内 GPL 全文和第三方摘要已建立 | `THIRD_PARTY_NOTICES.md` 仍明确为初步清单；正式传递依赖清单、精确版本对应源码 URL 和发行归档仍为 P0 |
| 正式签名 | 已建立 fail-closed 的 Release `.app` 构建/验签脚本；私钥配置正确地被 `.gitignore` 排除 | 本机仍没有正式发布证书/profile，不能生成可提交 `.app` |
| 审核可测试性 | 应用无自有登录，但主要功能依赖用户提供订阅 | 必须提供合法、稳定、限时的审核测试配置和不含私人凭据的操作说明 |

## 3. 中国大陆法规与资质判断

### 3.1 必须完成的基础材料

- **开发者主体实名认证**：建议企业主体提交。VPN/网络代理属于高风险网络能力，个人开发者是否会被接受没有可引用的公开保证，需华为确认。
- **APP 备案**：华为发布指引明确引用工信部 APP 备案要求；工信部说明新开展业务的 APP 应先备案再开展业务，分发平台不得为未备案 APP 提供分发。
- **版权材料**：华为 2026-06-25 的规则显示，包含中国大陆的手机应用，“应用版权证书或代理证书”为必选；不含中国大陆时为可选。
- **隐私政策 URL、用户协议、隐私标签**：内容必须与实际代码、开发者名称和商店应用名称一致。
- **客服联系方式**：应用内需有有效客服入口、邮箱/电话或在线支持渠道。不得只在商店后台填写而应用内无法找到。
- **年龄分级**：必须按 AppGallery 最新问卷如实填写。网络工具没有足够证据可直接断言某个等级；若允许用户导入任意第三方服务，也不能承诺第三方目的地内容适合儿童。

### 3.2 VPN、ICP 和跨境经营不能混为一谈

| 场景 | 初步判断 | 发布动作 |
| --- | --- | --- |
| 应用只在设备本地处理，用户自行提供合法的企业内网/自有服务器配置，开发者不提供节点、不转售线路 | 是否仍需特定 VPN 类资质，公开资料不足 | 中国律师书面分类 + AppGallery 工单确认；未取得前为阻塞 |
| 开发者提供、租用、聚合或销售国内 VPN 网络资源 | 可能落入 B13 国内互联网虚拟专用网业务 | 企业主体和相应增值电信许可评估；不能以“软件工具”规避 |
| 开发者提供、销售或运营跨境节点/线路 | 工信部 2017 通知明确存在批准要求 | 未取得主管部门批准不得发布/经营 |
| 免费提供公开信息服务 | APP 备案是底线；还要看是否构成非经营性互联网信息服务 | 由接入服务商/分发平台办理备案 |
| 付费会员、订阅聚合、账号云服务或其他经营性互联网信息服务 | 可能触发 ICP/其他增值电信许可及华为数字商品规则 | 上线收费前单独做牌照和支付合规审查 |

“机场订阅”“翻墙”“解锁 Google/ChatGPT”等表述不应出现在中国大陆商店文案或审核规避方案中。更重要的是，不能只换文案而保留未经确认的实际经营模式。

## 4. AppGallery 海外路径

### 4.1 当前平台限制

当前工程的 `deviceTypes` 是 `phone`。依据华为 2026-05-27 的发布区域说明，HarmonyOS NEXT 非手表设备目前只在中国大陆可下载。因此：

1. `--market overseas` 发布门禁默认失败。
2. 只有取得华为 AppGallery 工单书面确认，明确该包可以在指定海外地区向手机分发后，才能解除该平台阻塞。
3. AppGallery 宣传页所称“170+ 国家/地区”涵盖其整体应用分发生态，不能推翻 HarmonyOS NEXT 手机的具体限制，也不能与 Android AppGallery 混用。

### 4.2 若未来开放，最小上架路径

1. 确定开发者签约地区、AppGallery Connect 数据处理位置和目标国家清单，不选择“自动包含未来新增国家/地区”。
2. 每个目标市场做 VPN 合法性矩阵；先选择明确允许消费 VPN 且具备客服/隐私响应能力的市场。
3. 完成英文产品、隐私政策、用户协议、支持页面、商店介绍、截图和审核说明；目标市场需要当地语言时再增加对应本地化。
4. 完成 GDPR/英国 GDPR 等适用隐私评估。保持无账号、无广告、无遥测是降低第一版合规面的推荐方案；如果以后引入云同步、崩溃上报或分析 SDK，必须重新填隐私标签和取得合法基础。
5. 完成加密出口分类。VPN/代理显然包含强加密功能，不能假定“开源”或“商店发布”自动豁免。美国 BIS 对大众市场加密软件可能要求分类或年度自分类报告；欧盟 2021/821 也包含 Category 5 Part 2 和 Cryptography Note。应根据开发/出口主体、代码来源、分发地区和功能由专业顾问决定，不在 AGC 表单中自行猜测。
6. 使用正式 Release `.app`，通过 AppGallery 集成检查、兼容性/稳定性/性能/功耗/UX/隐私云测试，再走邀请测试、分阶段发布和正式审核。

## 5. 隐私与数据安全设计门禁

### 5.1 必须在隐私政策中逐项说明

- VPN 会在设备本地读取和转发全设备网络数据；开发者是否收集、上传或保留流量内容。
- 订阅 URL 可能在路径或查询参数中包含 token；节点可能包含用户名、UUID、密码、证书材料和服务器地址。
- 订阅下载会把用户 IP、时间和 User-Agent 暴露给用户选择的订阅服务商。
- 代理服务器、DNS 上游和网站诊断目标分别能看到哪些连接元数据；这些第三方并非由应用开发者当然控制。
- 网站可达性测试会主动访问 Apple、GitHub、Google、YouTube、ChatGPT 等端点；用户可单项执行或关闭，不应伪装成后台必要采集。
- `ohos.permission.INTERNET` 用于用户主动触发的订阅下载、VPN/DNS 和诊断联网；`ohos.permission.GET_NETWORK_INFO` 只读取当前网络承载类型，用于断开与升级恢复时确认 `BEARER_VPN` 已消失；`ohos.permission.GET_BUNDLE_INFO` 只在本机列出具有桌面入口的应用供 VPN 白名单选择，不上传应用清单，也不使用企业完整安装清单权限。
- 本地保存期限、删除订阅、清除配置、卸载后的数据处理、诊断导出和客服联系方式。
- 不收集的数据也应准确表述，例如第一版不做账号、广告、分析和云同步；以后增加能力时同步更新代码、隐私政策和 AppGallery 隐私标签。

### 5.2 当前实现与后续门禁

1. 当前实现使用 HUKS 生成应用作用域、设备绑定且不可导出的密钥，对订阅目录、网络设置和运行配置执行 AES-256-GCM 认证加密；API 22 兼容路径不依赖 API 26 才提供的显式 key-security-level 标签，也没有把超过 1 KB 的完整配置误存入 Asset Store。
2. 已实现从旧明文 schema 到加密 schema 的一次性迁移：候选密文写入并回读验证后才提升，旧明文最后删除，失败保留旧权威数据并支持 backup 恢复。主机故障模型覆盖提交边界；正式证据必须注明尚未逐边界执行破坏性真机注入。
3. sing-box 启动配置应尽可能只在内存或最短生命周期的受保护文件中存在；停止 VPN、切换订阅、异常退出和卸载时清理明文临时物。
4. UI、hilog、崩溃日志、测试报告和导出诊断只显示订阅主机的脱敏形式，不显示完整 URL、query、密码、UUID、私钥或节点认证材料。
5. 首次处理相关数据前展示中英文隐私摘要并允许拒绝；设置页在四次以内操作可访问完整政策、撤回同意和清除本地数据。VPN 系统授权弹窗不能替代隐私告知。
6. 保持最小权限。当前仅有 `INTERNET`、`GET_NETWORK_INFO` 与 `GET_BUNDLE_INFO`；后两者分别服务于 VPN bearer 消失确认和用户主动打开的应用白名单选择。不要申请企业完整安装清单、广泛存储或剪贴板权限。

## 6. sing-box GPL、品牌和图标

### 6.1 GPL 发布义务

项目直接链接并分发 sing-box GPL-3.0-or-later 代码，且 vendored 源码包含 HarmonyOS 适配。正式分发前至少完成：

- 根目录放置适用于整个分发物的 `LICENSE`，应用内“开源许可”页面提供 GPL 全文和第三方声明。
- 提供与每个发布二进制精确对应、可长期获取的完整对应源码 URL：应用源码、sing-box 精确版本、HarmonyOS 补丁、修改过的 Go 工具链、gVisor、构建脚本、依赖锁和重建说明。
- 保留上游版权声明和修改记录；源码标签与商店 `versionCode`、`.app` SHA-256 一一对应。
- 审核 AppGallery 开发者协议、最终用户许可与 GPL 是否存在附加限制冲突。该结论需要开源许可证律师确认，不能靠 README 自证。

当前 `third_party/sing-box/LICENSE` 明确写明：衍生作品未经事先同意不得使用该应用名称或暗示关联。因此应用名称、图标、商店描述不能让用户以为是 sing-box 官方产品。

### 6.2 纸飞机与 “HarmonyOS” 字样

- 可以保留“网络/路由/传输”的原创纸飞机视觉概念，但不得复制 sing-box 官方图形、轮廓、配色或组合方式，也不能在图标上写 sing-box。
- `HarmonyOS` 是华为商标。华为商标政策适用于在产品、标签和宣传材料中使用华为商标的第三方，并提供专门的商标授权申请入口。因此**正式商店图标不应直接叠加 “HarmonyOS” 字样或 HarmonyOS Logo，除非已经取得华为书面授权**。
- 推荐正式品牌方案：原创纸飞机 + 自有品牌名/字母（例如 HNA），在商店描述中以事实性语句写“适用于 HarmonyOS 7”，并按商标政策标注归属，不暗示华为背书。

## 7. 包、签名、兼容性和审核测试

### 7.1 正式包

- 调试 HAP 只用于设备调试。正式上架需要 Release 构建、发布证书/profile 和 `.app` App Pack。
- 构建 SDK 的 `releaseType` 必须是官方 `Release`；`Beta*` / Preview / Canary 只允许调试和邀请测试，不得通过修改 SDK 元数据伪装成正式包。当前已安装的 API 26 SDK 是 `Beta2`，因此正式构建会在签名前安全停止。
- 版本更新必须递增 `versionCode`。构建产物需记录 Git commit、sing-box commit、补丁清单、SHA-256、签名证书指纹和构建环境。当前发布脚本还会把这些 provenance 嵌入已签名 HAP，并要求证书指纹等于发布环境声明的批准值。
- 私钥、密码、证书/profile 不得提交 Git，不得写入脚本参数、CI 日志或文档。应使用 DevEco/AppGallery 的正式签名流程和受控密钥库。
- 首发 `.app` 必须只包含根目录 `pack.info` 和唯一 `entry-default.hap`：禁止 HSP、额外 payload、重复/绝对/跨目录路径、符号链接、特殊文件和超过展开上限的 ZIP。正式预检必须由 DevEco 官方 `app_unpacking_tool.jar` 接受 App Pack；工具缺失或拒绝时直接阻断，严格 ZIP 检查只是额外安全层，不能代替官方解包验收。
- 门禁解析真实 `pack.info` 和已签名 HAP 内 `module.json`，并与仓库 manifest / release manifest 交叉校验 bundle、版本、API 26 编译/目标、API 22 最低兼容、phone、唯一 VPN Extension、`exported=false`、`debug=false`，且权限恰好为 `INTERNET`、`GET_NETWORK_INFO` 和 `GET_BUNDLE_INFO`。
- 对唯一 HAP 做签名和代码签名验证；确认 profile 类型为 `release`，不是 `debug`。本地 `build-profile.json5` 还必须通过 JSON5 语义校验，它的密码、别名和本地路径不得记录；发布记录只保存经审阅语义及公开证书/profile 字节的 redacted SHA-256，并将其绑定到已签名 provenance。
- 正式构建额外要求中英隐私政策和中英用户协议各有独立公开 HTTPS URL；下载经过 DNS 公网地址、TLS、HTTPS-only 重定向、MIME、大小与超时限制，最终响应正文必须与本地批准稿按字节一致。
- 发布目录必须包含同 commit 确定性重建的 GPL 对应源码 `tar.gz`，它覆盖应用源码、sing-box、gVisor、OpenHarmony Go、补丁、锁、构建脚本和许可证。公开源码 URL 必须下载到与该归档相同的 SHA-256/大小，并同时写入 manifest 和已签名 HAP provenance。

### 7.2 64 位和设备兼容性

- 当前原生库只有 ARM64，且 manifest 仅声明 phone。这与当前产品目标一致，但不是“API 22 至 API 26 所有华为设备已适配”的证据。
- 首发设备矩阵至少覆盖直板机、折叠屏外/内屏、不同内存档位、Wi-Fi/蜂窝切换、深浅主题、中英语言、大字体、横竖屏/多窗和 VPN 与其他 VPN 冲突。
- 在 AGC 云测试上传正式 Release HAP/APP。华为 2026-07-03 的云测试说明要求发布证书和 release 编译模式，支持兼容性、稳定性、性能、功耗、UX 和隐私专项。
- 继续保留真实设备门禁：授权、连接、Google 204、浏览器 ChatGPT、节点热切换、DNS/IPv6 重配置、断开重连、30 分钟稳定性和泄漏检查。构建成功或 HAP 可安装不能替代这些结果。

### 7.3 审核测试资料

应用本身没有开发者账号登录，因此不需要虚构测试账号。但审核人员必须能验证主功能：

- 提供不含私人用户数据、合法且限时的审核专用订阅/配置；不能提交真实用户机场 URL。
- 附中英文步骤：隐私同意、导入配置、系统 VPN 授权、连接、测速、切换、关闭和清除数据。
- 测试端点应由开发者有权使用，至少一个端点可在审核地区稳定访问；不得把访问受地区限制的网站作为唯一成功判据。
- 写明哪些功能需要重启 VPN、哪些可热切换、系统代理为何不可用，避免审核员把平台限制误判为故障。
- 审核配置到期时间应覆盖全部审核期，提交后不要远程改变功能或禁用核心路径。

## 8. 提交前阻塞清单

### P0：不完成就不能提交

- [ ] 中国大陆：华为工单书面确认 VPN/代理应用分类和资质清单。
- [ ] 中国大陆：律师书面确认 APP 备案、ICP/B13/跨境经营许可边界；如需要，资质已经取得。
- [ ] 中国大陆：APP 备案和手机应用版权证明完成。
- [ ] 海外：华为确认 HarmonyOS NEXT 手机可在目标地区分发；否则改走 Android 或等待平台开放。
- [x] 订阅 URL、节点凭据、网络设置和运行配置已完成 HUKS 加密存储、候选/回滚式明文迁移、跨进程锁与清理实现；API 26 真机 VPN 连接已证明跨进程运行配置可用。
- [ ] 正式安全验收报告需归档现有主机故障模型结果，并明确尚未逐迁移崩溃点执行破坏性真机注入的证据边界。
- [ ] 中英文隐私政策、用户协议、首次告知、撤回和清除数据入口完成。
- [ ] AppGallery 隐私声明/隐私标签与实际代码一致。
- [ ] GPL 完整对应源码、LICENSE、NOTICE、应用内开源许可和版本标签完成。
- [ ] sing-box/HarmonyOS 品牌和图标不暗示官方关联；未授权则移除 HarmonyOS 字样。
- [ ] 正式 Release `.app` 使用发布证书签名，签名验证为 release。
- [ ] 使用官方 API 26 `Release` 通道 SDK 重建，包内 `pack.info.releaseType` 与 HAP `apiReleaseType` 均为 `Release`；当前 `Beta2` 调试工具链不可提审。
- [ ] 全部 UI 中英文本地化、深浅主题、无障碍和核心交互已完成真机验收。

### P1：提交审核前完成

- [ ] AppGallery 中英文名称、介绍、更新说明、关键词、截图、图标、分类和年龄分级。
- [ ] 有效的支持 URL、客服邮箱/电话和问题响应流程。
- [ ] 合法的审核专用配置和中英文审核步骤。
- [ ] AGC 集成检查以及兼容性、稳定性、性能、功耗、UX、隐私云测试无未解释的失败。
- [ ] SBOM、加密功能清单、目标国 VPN/出口管制/隐私矩阵和法律审批记录。
- [ ] Release SHA-256、Git tag、sing-box commit、补丁集、许可证源码 URL 和回滚计划归档。

## 9. 自动门禁

运行：

```bash
scripts/release_preflight.sh --market cn --app /absolute/path/to/HarmonyNet.app
scripts/release_preflight.sh --market overseas --app /absolute/path/to/HarmonyNet.app
```

正式构建与预检还要求 `HNA_RELEASE_CERT_SHA256` 为审核批准的 leaf release 证书
DER SHA-256。脚本不会读取或打印签名密码、订阅 URL 或节点凭据；它会校验
`.app`、真实 `pack.info`/签名 HAP manifest、`release-manifest.json`、`SHA256SUMS`、
确定性对应源码归档、公开 HTTPS 政策/源码正文、签名 HAP 内 provenance、redacted
build-profile digest、当前 Git 提交和 `core-lock` 的一致性。它还将从签名包中核心重生
CycloneDX SBOM，校验同级安全报告/策略/验证记录的精确字节，最后才检查 Git 外的
`HNA_RELEASE_APPROVAL`、脱离签名和显式受信公钥。批准精确绑定 market/bundle/version/commit/
App/manifest/四份政策/源码/SBOM/安全报告及市场证据，不在 manifest 中反向引用，因此
没有哈希循环。法律材料通过本地文件路径/非秘密工单号声明，建议只
在安全的发布环境配置，不提交证件原件到 Git。海外手机门禁默认失败，只有设置
华为书面确认工单号及完整证据文件后才解除平台限制。中国大陆必须提供
`HNA_HUAWEI_VPN_REVIEW_EVIDENCE`；海外另必须提供 `HNA_HUAWEI_OVERSEAS_PHONE_EVIDENCE`。

## 10. 官方与一手来源

以下日期为页面显示的最近更新时间或发布日；政策可能继续变化，正式提交当日需重新检查。

### 华为 / HarmonyOS / AppGallery

- 华为，**HarmonyOS 5+ 发布国家/地区配置**，更新 2026-05-27：明确 HarmonyOS NEXT 全球仅手表，其他设备仅中国大陆。
  <https://developer.huawei.com/consumer/en/doc/app/agc-help-release-game-area-0000002399129161>
- 华为，**在应用市场分发**（访问于 2026-08-12）：实名认证、包上传、隐私声明、资质、APP 备案、测试和发布流程。
  <https://developer.huawei.com/consumer/cn/appgallery/devstart/>
- 华为，**配置版权信息**，更新 2026-06-25：包含中国大陆的手机应用版权证明为必选，不含中国大陆为可选。
  <https://developer.huawei.com/consumer/cn/doc/App/agc-help-release-app-copyright-0000002278981450>
- 华为，**应用程序包术语**，更新 2026-06-16：`.app` App Pack 是上架基本单元。
  <https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/application-package-glossary>
- 华为，**应用安装卸载与更新开发指导**，更新 2026-04-29：应用更新需递增 `versionCode` 并重新发布。
  <https://developer.huawei.com/consumer/cn/doc/doccenter-getting-started/application-package-install-uninstall>
- 华为，**VPN Extension API**，更新 2025-03-17：公开三方 VPN API，自 API 11 支持。
  <https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-net-vpnextension-V5>
- 华为，**HarmonyOS 7 / API 26 发布资讯**（2026-06-18）。
  <https://developer.huawei.com/consumer/cn/information/releases>
- 华为，**应用隐私保护**，更新 2026-07-09：透明、最小化、控制、本地优先和加密存储。
  <https://developer.huawei.com/consumer/cn/doc/doccenter-architecture/bpta-app-privacy-protection>
- 华为，**选择和同意**，更新 2026-01-28：隐私政策入口、撤回同意、最小权限和用途告知。
  <https://developer.huawei.com/consumer/cn/doc/doccenter-architecture/standard-privacy-user-consent>
- 华为，**Asset Store Kit 简介**，更新 2025-03-17：短敏感数据安全存储及 1 KB 限制。
  <https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V14/asset-store-kit-overview-V14>
- 华为，**自定义云测试**，更新 2026-07-03：发布证书、Release 包、隐私标签和测试专项要求。
  <https://developer.huawei.com/consumer/cn/doc/doccenter-submission/agc-help-cloudtest-customizetest-0000002255036404>
- 华为，**AppGallery Review Guidelines - Developers' Behavior**，更新 2025-05-21：真实开发者信息、有效客服、受严格管制服务主体和可运行最新版本。
  <https://developer.huawei.com/consumer/en/doc/app/50104-11>
- 华为，**Policy Center**（访问于 2026-08-12）：审核、年龄分级、命名、版权和拒绝政策入口。
  <https://developer.huawei.com/consumer/en/policy-center/>
- 华为，**HUAWEI Trademark Policy**（访问于 2026-08-12）：HarmonyOS 属于华为商标，第三方商标使用规则。
  <https://consumer.huawei.com/en/legal/intellectual-property/huawei-trademark-policy/>
- 华为，**商标授权申请**（访问于 2026-08-12）：包含 HarmonyOS Logo 授权场景。
  <https://consumer.huawei.com/en/legal/intellectual-property/trademark-authorization/modify/>

### 中国大陆监管

- 工业和信息化部，**APP 备案通知解读**，2023-08-08。
  <https://www.miit.gov.cn/zwgk/zcjd/art/2023/art_39b4f1acc36745b98478e0ec3e07128d.html>
- 工业和信息化部/通信管理局，**电信业务分类目录**：B13 国内互联网虚拟专用网业务定义。
  <https://qhca.miit.gov.cn/zwgk/zcwj/flfg/art/2022/art_0a66ad8c82c94c77bf56d698a1f35d64.html>
- 工业和信息化部，**关于清理规范互联网网络接入服务市场的通知**，2017-01-22：跨境经营活动使用 VPN 等信道需批准。
  <https://www.miit.gov.cn/zwgk/zcwj/wjfb/tz/art/2017/art_a940645e940946e1a62cd6c90a4e994e.html>
- 工业和信息化主管部门，**互联网信息服务管理办法**，页面发布 2026-03-23：经营性许可、非经营性备案。
  <https://sdca.miit.gov.cn/zwgk/fgbz/art/2026/art_fea940f81f1d423e87101adf147ab979.html>

### 开源、品牌和出口管制

- SagerNet，**sing-box v1.13.18 LICENSE**：GPL-3.0-or-later 及不得暗示官方关联条款。
  <https://github.com/SagerNet/sing-box/blob/v1.13.18/LICENSE>
- SagerNet，**sing-box 1.13.18 发布记录**，commit `45ca32d`。
  <https://github.com/SagerNet/sing-box/releases/tag/v1.13.18>
- 美国商务部 BIS，**Mass market encryption / 740.17**（访问于 2026-08-12）：分类与报告要求概览。
  <https://www.bis.gov/learn-support/encryption-controls/mass-market>
- 欧盟，**Regulation (EU) 2021/821**：双用途物项及 Category 5 Part 2 Cryptography Note。
  <https://eur-lex.europa.eu/eli/reg/2021/821/oj/?locale=EN>
