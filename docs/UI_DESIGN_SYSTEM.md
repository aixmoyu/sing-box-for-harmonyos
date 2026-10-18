# HarmonyOS 网络助手 UI 设计系统

> 状态：**Frozen baseline / 冻结基线**
> 版本：1.0
> 日期：2026-08-12
> 技术基线：HarmonyOS / ArkUI，`compileSdkVersion` / `targetSdkVersion` 为 `26.0.0`，`compatibleSdkVersion` 为 `6.0.2(22)`
> 适用范围：首页、订阅、诊断、设置，以及这些页面共用的导航、卡片、表单和状态反馈。

本文档是项目 UI/UX 的实现与验收合同。它不替代业务状态机，也不允许用“界面可见”代替“功能可用”。任何可交互控件都必须有真实状态源、执行路径、忙碌态、结果反馈和失败回滚。

## 1. 设计目标

### 1.1 产品气质

项目采用 HarmonyOS 当前的“空间感 + 沉浸光感”语言，而不是复刻某个 iOS 页面，也不是给所有区域统一套玻璃效果。

- **可信**：连接状态、节点策略、测速和诊断结果必须一眼可判读。
- **轻盈**：交互层悬浮，内容层保持安静；减少厚重边框和大面积实色按钮。
- **精确**：开关、选择、命令、导航各用正确控件语义。
- **连续**：深浅色、中文英文、窗口尺寸变化时，任务和选择不丢失。
- **可上架**：文本清晰、状态不只靠颜色、触控区域足够、禁用能力不伪装成可用能力。

### 1.2 非目标

- 不把每张卡片都做成高模糊玻璃。
- 不用 Emoji、Unicode 几何字符或混搭的实体/线性图片模拟系统图标。
- 不把互斥选项做成多个布尔开关。
- 不把异步 VPN 生命周期做成会乐观跳变的装饰开关。
- 不用无法执行的入口、假测速、假系统代理或固定演示数据填满页面。

## 2. HarmonyOS 空间与沉浸光感原则

华为最新设计说明将沉浸光感视作一种同时包含光学行为、空间属性和交互响应的“界面物质”，并将其用于标题栏、悬浮页签、底部导航和核心互动区域。项目据此采用三个视觉层级：

1. **环境层**：页面基色、低透明度渐变和柔和光斑。只负责空间氛围，不承载操作。
2. **内容层**：状态、节点、订阅、诊断结果。以高可读性的实底或低透卡片为主。
3. **交互层**：悬浮底栏、主连接控制、上下文工具。使用 API 22 可用的组件级背景模糊、透明语义底色、边框和阴影表达空间层级。

材质使用规则：

- 一个视图内最多保留一个主要悬浮导航面和少量高频交互材质面。
- 材质背后必须有可感知但不喧宾夺主的环境层，否则模糊没有空间依据。
- 重要正文不得直接压在变化剧烈的高透明材质上。
- 材质不是状态色。连接成功、警告和失败仍由文字、图标和语义色共同表达。
- 低算力设备由系统自动降级。不得为了强制玻璃效果关闭系统自适应。
- 同一浮层使用 `backgroundBlurStyle` 时，只叠加一层低透明度语义背景、一条边界和一个阴影；不堆叠多层模糊或高不透明色。

## 3. 基础视觉系统

### 3.1 间距、尺寸与圆角

采用 4vp 基础网格，常用值如下：

| 令牌 | 值 | 用途 |
| --- | ---: | --- |
| `space.xs` | 4vp | 图标与极短标签 |
| `space.sm` | 8vp | 行内元素、紧凑分组 |
| `space.md` | 12vp | 卡片内部相邻控件 |
| `space.lg` | 16vp | 手机页边距、卡片内边距 |
| `space.xl` | 24vp | 页面区块间距、宽屏页边距 |
| `space.2xl` | 32vp | 大标题与首个内容区 |
| `target.minimum` | 48vp | 所有主要触控热区最小宽/高 |
| `radius.control` | 12vp | 输入框、分段控件、小按钮 |
| `radius.card` | 20vp | 内容卡片 |
| `radius.hero` | 28vp | 连接主卡、悬浮材质容器 |
| `radius.pill` | 999vp | 状态标签、胶囊选择器 |

约束：

- 手机左右页边距默认 16vp；宽屏 24–32vp。
- 卡片之间优先使用留白，不用连续粗分割线。
- Switch 自身视觉尺寸可以小于 48vp，但必须放进至少 48vp 高的可点击 Row。
- 底部悬浮栏必须避开系统安全区，页面滚动内容必须预留底栏高度和额外间距。

### 3.2 字体与信息层级

默认使用系统字体/HarmonyOS Sans，不在功能界面使用书法字体、装饰字体或伪手写字体。

| 层级 | 建议字号 | 字重 | 典型用途 |
| --- | ---: | --- | --- |
| Display | 30–32fp | Bold | 首页连接状态，仅一处 |
| Title L | 24fp | Bold | 页面标题 |
| Title M | 20fp | Bold/Medium | 卡片标题 |
| Body L | 16fp | Regular/Medium | 主要说明、列表标题 |
| Body M | 14fp | Regular | 正文、设置项说明 |
| Caption | 12fp | Regular/Medium | 时间、协议、次要元数据 |

排版规则：

- 正文行高不少于字号的 1.35 倍。
- 不用全大写英文制造层级。
- 中文与英文共用语义层级，但英文要预留约 30% 的横向扩展空间。
- 控件标题不硬编码固定宽度；长文本允许换行或合理省略，并提供完整可访问名称。
- 数值与单位之间保持一致格式，例如 `24 ms`、`12.4 MB/s`。

### 3.3 语义颜色与深浅色

页面代码只消费语义角色，不直接散落浅色/深色十六进制值。

| 语义角色 | 浅色职责 | 深色职责 |
| --- | --- | --- |
| `pageBackground` | 低饱和冷白环境底 | 深海军蓝/近黑环境底 |
| `surfacePrimary` | 主要内容卡片 | 抬升后的深色内容卡片 |
| `surfaceSecondary` | 次级分组、输入背景 | 次级分组、输入背景 |
| `surfaceFloating` | 系统材质降级底色 | 系统材质降级底色 |
| `textPrimary` | 高对比正文 | 高对比正文 |
| `textSecondary` | 辅助信息 | 辅助信息 |
| `textTertiary` | 提示、占位 | 提示、占位 |
| `accent` | 主品牌青绿/蓝绿 | 提亮后的品牌青绿 |
| `success` | 已连接、通过 | 已连接、通过 |
| `warning` | 部分可用、需注意 | 部分可用、需注意 |
| `danger` | 失败、破坏性动作 | 失败、破坏性动作 |
| `divider` | 低对比分隔 | 低对比分隔 |
| `focusRing` | 键盘/外设焦点 | 键盘/外设焦点 |

实现约束：

- 基础资源放在 `resources/base/element/color.json`，深色覆盖放在 `resources/dark/element/color.json`。
- 默认跟随系统主题；如果提供“浅色/深色/跟随系统”，它是三选一设置，使用单选/分段/Select，而不是三个开关。
- 文字和状态不得只依赖颜色。例如失败必须同时有失败图标或“失败”文本。
- 项目验收基线采用 WCAG 2.2：普通文字至少 4.5:1，大号文字至少 3:1，关键图标、焦点边界和控件状态至少 3:1。
- 材质背景会随壁纸、页面内容、系统沉浸强度和设备算力变化，必须在真机上分别测量浅色、深色以及最亮/最暗背景；静态设计稿的对比度不算最终通过。

## 4. 控件语义矩阵

| 业务意图 | 正确控件 | 权威状态源 | 正确行为 | 禁止做法 |
| --- | --- | --- | --- | --- |
| 开启/关闭 IPv6 | `ToggleType.Switch` | 已持久化且已应用的运行配置 | 修改时应用或重载运行配置；失败回滚并说明 | 大号 Button 显示“已开启/已关闭” |
| 连接/断开 TUN/VPN | Switch 或主连接控制 | VPN 生命周期状态机 | `idle → starting → connected → stopping → idle`；忙碌期禁用；失败回真实状态 | 点击后先把 UI 伪装成已连接 |
| 系统代理 | 禁用 Switch + 平台说明 | 系统能力探测 | 无权限时始终禁用，说明“平台不支持全局系统代理” | 做一个可点击但无逻辑的开关 |
| 规则/全局/直连 | Segment/单选 | 当前路由模式 | 互斥选择；连接中变更须真实热更新或明确重启 | 三个独立 Switch |
| 手动/自动优选/故障转移 | Segment/单选 | 当前节点策略 | 策略切换后更新真实 outbound 选择逻辑 | 三个看似可选的普通 Button |
| 手动节点选择 | 可选择列表/Select | 核心当前 selector | 连接中允许安全切换并读取回当前节点 | 只改变列表高亮 |
| 添加订阅 | 表单 + 主 Button | 表单草稿/保存结果 | 名称与 URL 可编辑；校验、保存、解析有独立反馈 | 自动创建“未命名订阅”且不可改名 |
| 更新订阅 | 命令 Button | 后台任务状态 | 显示更新中、成功时间、失败原因；旧配置失败保护 | 用 Switch 表示一次性命令 |
| 测速/可用性检查 | 命令 Button | 真实探测任务 | 可取消、逐项出结果；区分超时/DNS/TLS/HTTP | 固定延迟或假数据 |
| 诊断子页面 | 固定 Segment/Tabs | 当前子页索引 | 位置和宽度稳定，内容变化不移动 Tab | 每页用不同宽度的 Button 组 |
| 删除订阅/清空日志 | 危险 Button + 确认 | 数据层结果 | 明确对象和后果；成功后再移除 UI | 用 Switch 或无确认图标 |
| 底部一级导航 | `Tabs`/TabBar | 当前页面索引 | 图标、文字、焦点、选中态一致 | Emoji/Unicode 字符混合模拟图标 |
| 不可用能力 | 禁用控件 + 简短原因 | 能力/权限/状态探测 | 保留可理解性，必要时提供帮助入口 | 隐藏全部上下文或仍允许点击 |

### 4.1 所有交互控件的完成定义

一个控件只有同时满足以下条件才算“已实现”：

1. 有明确、单一的权威状态源。
2. 点击/切换会调用真实业务逻辑。
3. 运行中有可见忙碌态，并阻止重复提交。
4. 成功后从业务层读回状态，而不是只保留本地高亮。
5. 失败时回滚到真实状态，并显示可操作的错误原因。
6. 页面切换、应用重进、配置重载后状态仍正确。
7. 有单元/合同测试或真机验收证据。

## 5. Symbol 统一方案

### 5.1 一级导航映射

所有一级导航使用 HarmonyOS Symbol 的 regular/line 风格；不混用填充图标和线性图标。选中态通过品牌色、字重和圆角背板表达，不靠切换为 `_fill` 版本表达。

| 页面 | Symbol 资源 | 中文 | English |
| --- | --- | --- | --- |
| 首页 | `$r('sys.symbol.house')` | 首页 | Home |
| 订阅 | `$r('sys.symbol.externaldrive')` | 订阅 | Profiles |
| 诊断 | `$r('sys.symbol.line_viewfinder')` | 诊断 | Diagnostics |
| 设置 | `$r('sys.symbol.gearshape')` | 设置 | Settings |

当前 API 26 本地资源解析表和 ArkTS 编译已确认上述四个名称；品牌相关界面还可使用 `$r('sys.symbol.paperplane')` 或 `$r('sys.symbol.paperplane_right_fill')`。启动器图标必须继续使用应用自有图标资源，不能把运行时 `sys.symbol` 当作 launcher icon。API 22 系统资源完整性仍必须在最低版本真机上核对。

建议 ArkTS 形态：

```ts
@Builder
private navigationItem(symbol: Resource, label: ResourceStr, active: boolean) {
  Column({ space: 4 }) {
    SymbolGlyph(symbol)
      .fontSize(22)
      .fontWeight(FontWeight.Medium)
      .fontColor([active ? this.accentColor : this.secondaryTextColor])
      .effectStrategy(SymbolEffectStrategy.SCALE)

    Text(label)
      .fontSize(12)
      .fontWeight(active ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(active ? this.accentColor : this.secondaryTextColor)
  }
  .constraintSize({ minWidth: 48, minHeight: 48 })
}
```

规则：

- 同一导航栏统一 `fontSize`、`fontWeight` 和 rendering strategy。
- 选中、未选中都必须有文字标签；不让用户猜图标。
- 动态状态图标可使用 SymbolEffect，但不得为静态页面入口循环播放动画。
- 若新加 Symbol，先在当前 SDK `id_defined.json`/`sysResource.js` 与真实编译中确认资源名，并加入 API 22 真机资源回归，不能仅凭视觉猜名称。

## 6. API 22 模糊浮层实现合同

### 6.1 局部模糊材质

```ts
Column() {
  // 高频交互内容
}
.backgroundColor(this.palette().surfaceGlass)
.backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
.border({ width: 1, color: this.palette().border })
.borderRadius(28)
.shadow({ radius: 20, color: this.palette().shadow, offsetY: 8 })
```

`BlurStyle.COMPONENT_ULTRA_THIN` / `COMPONENT_THIN` 和 `backgroundBlurStyle` 的起始版本早于 API 22。悬浮底栏使用 `COMPONENT_ULTRA_THIN`，顶栏使用 `COMPONENT_THIN`；深浅主题通过语义色提供稳定的降级底色和对比度。

### 6.2 悬浮底栏与安全区

底栏是固定宽度的 `Row`，使用 API 22 背景模糊并展开底部系统安全区。页面索引继续由单一状态源绑定，滚动容器底部必须保留底栏高度与额外间距。API 26-only 的 `Tabs.barFloatingStyle`、`uiMaterial` 和 `systemMaterial` 不进入本项目源码。

### 6.3 模糊材质的兼容方案

其他无需交互光感的旧式浮层可以使用：

```ts
.backgroundColor('#33FFFFFF')
.backgroundBlurStyle(
  BlurStyle.COMPONENT_ULTRA_THIN,
  {
    colorMode: ThemeColorMode.SYSTEM,
    adaptiveColor: AdaptiveColor.DEFAULT,
    policy: BlurStyleActivePolicy.ALWAYS_ACTIVE,
    inactiveColor: '#F2F5F7'
  }
)
.shadow(ShadowStyle.OUTER_FLOATING_SM)
```

不要设置 `disableSystemAdaptation: true` 强行绕过系统降级。

### 6.4 环境渐变

渐变只放在页面 `Stack` 的环境层：

```ts
.linearGradient({
  angle: 135,
  colors: [
    ['#0F61FFD6', 0.0],
    ['#121875FF', 0.55],
    ['#06000000', 1.0]
  ]
})
```

`colors` 的 stop 必须在 `0.0 ... 1.0` 且按升序。深浅色使用不同资源/透明度，不允许直接把浅色渐变反相作为深色方案。

## 7. Toggle 与异步状态

### 7.1 普通配置开关

```ts
Toggle({ type: ToggleType.Switch, isOn: this.ipv6Enabled })
  .selectedColor(this.accentColor)
  .switchPointColor(Color.White)
  .switchStyle({
    pointRadius: 10,
    trackBorderRadius: 14,
    unselectedColor: this.switchTrackColor,
    pointColor: Color.White
  })
  .enabled(this.runtimeConfigurationEditable())
  .onChange((value: boolean) => {
    if (value !== this.ipv6Enabled) {
      this.toggleIpv6Enabled()
    }
  })
```

### 7.2 VPN/TUN 生命周期开关

开关显示值必须来自连接状态机，而非手势瞬间产生的值：

```ts
Toggle({
  type: ToggleType.Switch,
  isOn: this.connectionPhase === 'connected'
})
.enabled(this.connectionActionEnabled())
.onChange((requested: boolean) => {
  const connected = this.connectionPhase === 'connected'
  if (requested !== connected) {
    this.tryConnect()
  }
})
```

验收要求：

- `starting` / `stopping` / 配置重载期间禁用重复操作并显示 Progress。
- 启动失败后自动回到关闭状态，错误信息保留到用户可读。
- 停止失败不能假装已断开。
- 应用重进后从 runtime 读回连接状态。
- 连接中允许的节点切换、测速和诊断不能被整个页面一刀切禁用。

## 8. 响应式布局

### 8.1 断点合同

项目采用组件宽度断点，避免分屏/折叠屏中只看整窗宽度：

| 区间 | 宽度 | 建议布局 |
| --- | --- | --- |
| `xs` | `< 400vp` | 单列、紧凑标题、底部导航 |
| `sm` | `400–599vp` | 单列为主，部分双列快捷项 |
| `md` | `600–839vp` | 双列卡片、内容宽度约束 |
| `lg` | `840–1023vp` | 8/12 栅格，多列仪表区 |
| `xl` | `1024–1439vp` | 最大内容宽度 + 更大留白 |
| `xxl` | `≥ 1440vp` | 最大内容宽度，不无限拉伸卡片 |

### 8.2 ArkUI GridRow 形态

```ts
GridRow({
  columns: { xs: 4, sm: 4, md: 8, lg: 12, xl: 12, xxl: 12 },
  gutter: 12,
  breakpoints: {
    value: ['400vp', '600vp', '840vp', '1024vp', '1440vp'],
    reference: BreakpointsReference.ComponentSize
  }
}) {
  GridCol({
    span: { xs: 4, sm: 2, md: 4, lg: 4, xl: 4, xxl: 4 }
  }) {
    // card
  }
}
.onBreakpointChange((breakpoint: string) => {
  this.currentBreakpoint = breakpoint
})
```

规则：

- 所需断点的 `columns` 和 `span` 全部显式声明，避免继承规则造成意外布局。
- `ComponentSize` 下不要在 `onBreakpointChange` 回调中动态改 GridRow 自身 padding/margin，避免断点震荡。
- 窗口改变、折叠/展开、横竖屏切换只改变布局，不重置当前 Tab、表单、连接状态、节点和滚动任务。
- 小屏不得通过缩小字体硬塞内容；先换行、折行布局或隐藏低优先级装饰。

## 9. 页面信息架构

### 9.1 首页

首页只承载高频操作与实时状态，顺序如下：

1. 连接状态与 VPN/TUN 主控制；
2. 当前订阅、当前策略、当前节点；
3. 路由模式（规则/全局/直连）；
4. 节点策略（手动/自动优选/故障转移）；
5. 节点选择与延迟；
6. 实时上下行和必要的连接摘要。

系统代理若平台不支持，显示为禁用设置项并说明原因；不能占据首页主操作位。

### 9.2 订阅

订阅页负责配置生命周期，不承担日常节点切换。必须支持：名称、URL、更新、编辑、删除、最后更新时间、节点数、解析错误。新增时名称字段可编辑。

### 9.3 诊断

诊断页顶部子 Tab 固定位置、固定顺序、等宽或稳定自适应。建议划分为：网络可用性、核心诊断、日志。切换内容不能让 Tab 横向跳动。

### 9.4 设置

设置页按语义分组：

- 网络：IPv6、DNS、局域网相关能力；
- 外观：主题、语言；
- 行为：测速 URL、超时、自动更新等；
- 隐私与诊断：日志、导出诊断信息；
- 关于：版本、sing-box 版本、许可。

一次性动作使用 Button/列表入口，布尔偏好使用 Switch，多选一使用 Select/Segment/Radio。

## 10. 动效与交互反馈

华为设计强调自然、流畅和物理连续性。本项目采用克制的项目级时长基线；这些数值是本项目约定，不冒充系统固定常量。

| 场景 | 时长建议 | 动效 |
| --- | ---: | --- |
| 按压/高亮 | 80–140ms | 轻微透明度/缩放，不位移布局 |
| Switch/Segment 选择 | 140–200ms | 状态背板平滑移动/淡入 |
| 卡片展开、子 Tab 切换 | 180–260ms | 淡入 + 小范围位移 |
| 页面级过渡 | 240–360ms | 使用系统导航/容器默认优先 |
| 异步等待 | 不固定 | Progress + 状态文本，不伪造完成进度 |

规则：

- 优先使用系统控件默认动效和 `interactive` 材质反馈。
- 动画只解释状态变化，不作为装饰循环播放。
- 列表批量测速时逐项更新，不让整屏持续抖动或重排。
- 错误反馈出现时不遮挡用户需要读取的原状态和修复入口。
- 在系统减少动态效果场景下，非必要缩放、位移和循环动效应关闭；功能反馈保留为颜色、图标和文字变化。
- 60fps 是普通滚动与微交互验收目标；长列表使用懒加载/分批渲染，不通过减少可读性换性能。

## 11. 可访问性与国际化

### 11.1 可访问性

- 所有图标按钮提供可访问名称；状态图标同时说明“已连接/未连接/失败”。
- 选中态和焦点态是不同状态，键盘/遥控/触控板焦点必须可见。
- 禁用控件仍保留可理解标签，并在邻近文本说明禁用原因。
- 最小热区 48 × 48vp；相邻热区之间保留足够间距。
- 支持系统字体缩放；标题和设置行不得因放大后裁切关键文字。
- 图表和速度曲线必须有对应数值文本，不以图形作为唯一信息源。
- Toast 不能成为错误信息的唯一载体；关键错误在页面内持久显示到状态改变或用户关闭。

### 11.2 中英文

- UI 文案全部通过资源文件提供中文和英文，不在页面逻辑中拼接完整句子。
- 英文标签采用自然产品语言：`Home`、`Profiles`、`Diagnostics`、`Settings`。
- 中文“订阅”在英文界面优先使用 `Profiles` 或 `Subscription profiles`，避免把订阅 URL 与付费订阅含义混淆。
- 数字、日期、单位、复数和错误模板使用本地化格式。
- 英文状态和错误文案允许换行；不得用缩小到不可读来适配。

## 12. API 22 兼容能力与证据

项目用 API 26 SDK 编译，单包最低兼容 `6.0.2(22)`。以下起始版本由本机 API 26 SDK d.ts 中的 `@since` 元数据核对，并由 `api22-compatibility.test.ts` 防止已知高版本符号回流。

| 能力 | API 起始版本 | 精确入口 | 本地 SDK 证据 |
| --- | --- | --- | --- |
| Switch | 8；`switchStyle` 12 | `Toggle({ type: ToggleType.Switch, isOn })` | `openharmony/ets/component/toggle.d.ts` |
| Symbol 组件 | 早于 22 | `SymbolGlyph($r('sys.symbol.*'))` | `symbolglyph.d.ts`；具体系统 Symbol 名须在 API 22 真机验证 |
| 背景模糊 | 9 | `backgroundBlurStyle(...)` | `openharmony/ets/component/common.d.ts` |
| 组件模糊样式 | 11 | `BlurStyle.COMPONENT_ULTRA_THIN/COMPONENT_THIN` | `openharmony/ets/component/common.d.ts` |
| 预置阴影 | 10 | `ShadowStyle.OUTER_FLOATING_SM/MD` | `openharmony/ets/component/common.d.ts` |
| 线性渐变 | 7 | `linearGradient({ angle, colors })` | `openharmony/ets/component/common.d.ts` |
| 响应式栅格 | 9 | `GridRow` / `GridCol` / `onBreakpointChange` | `grid_row.d.ts`、`grid_col.d.ts` |

已在本地 API 26 资源映射中核对、但仍需 API 22 真机回归的 Symbol：

- `gearshape`
- `house`
- `paperplane`
- `externaldrive`
- `line_viewfinder`
- `paperplane_right_fill`

注意：这里的“SDK 可用”表示当前编译 SDK 声明/资源存在且 ArkTS 编译通过，不等于 API 22 设备已完成运行时资源、材质和视觉验收。

## 13. 真机 UI/UX 验收清单

每次 UI 里程碑必须保留设备型号、系统版本、应用版本/commit、主题、语言、窗口形态和截图/录屏。以下项目全部通过，才能称为“UI 可用版本”。

### 13.1 导航与布局

- [ ] 四个底部 Tab 的 Symbol 来自同一风格族，无 Emoji/Unicode 图形。
- [ ] 每个 Tab 同时有图标和文字，选中态清楚但不过度发光。
- [ ] 底栏悬浮时正确避让手势区，最后一项内容不被遮挡。
- [ ] 诊断三个子 Tab 在加载、结果更新和语言切换时不移动、不变宽跳动。
- [ ] 320–399vp 紧凑宽度没有横向溢出或关键裁切。
- [ ] 400–599vp 正常手机宽度留白一致。
- [ ] 600vp 以上分屏/折叠展开后布局重排，业务状态不重置。
- [ ] 横竖屏/折叠切换后当前页、节点、输入草稿和滚动任务连续。

### 13.2 深浅色与材质

- [ ] 浅色模式所有正文、辅助文字、禁用态均可读。
- [ ] 深色模式无纯黑大块压迫、无灰字淹没、无过亮描边。
- [ ] 系统主题动态切换后无需重启，图标、文字、状态色和材质同步更新。
- [ ] 最亮和最暗背景下，悬浮底栏内容都达到对比度基线。
- [ ] API 22 与 API 26 系统模糊降级下没有透明到不可读或厚重到像实色板。
- [ ] 低算力/省电场景的材质降级仍有明确边界和可读内容。
- [ ] 同一材质节点没有重复背景、边框或阴影造成脏边。

### 13.3 控件语义与真实状态

- [ ] IPv6 使用 Switch；切换后核心真实生效，失败回滚。
- [ ] VPN/TUN 显示真实 lifecycle，starting/stopping 期间不能重复触发。
- [ ] VPN 启动失败后开关回到关闭，页面显示可理解错误。
- [ ] VPN 已连接时可以执行被允许的测速、诊断和节点切换。
- [ ] 连接中切换节点后，从核心读回当前节点，不只是 UI 变色。
- [ ] 系统代理无平台能力时为禁用状态，并给出明确说明。
- [ ] 规则/全局/直连是互斥控件，不是三个 Switch。
- [ ] 手动/自动优选/故障转移是互斥控件，并驱动真实策略。
- [ ] 添加订阅可输入名称；保存、解析、更新失败不会生成不可管理的假条目。
- [ ] 所有 Button 都执行一次性动作；所有 Switch 都代表持续布尔状态。

### 13.4 国际化与可访问性

- [ ] 中文、英文四个主页面无硬编码漏翻。
- [ ] 英文长标签、错误信息和订阅名称不遮挡操作。
- [ ] 1.0×、1.3×、最大可用系统字体下关键文字不裁切。
- [ ] TalkBack/屏幕朗读可读出控件名称、状态和禁用原因。
- [ ] 不看颜色仍能区分连接、警告、失败和选中状态。
- [ ] 键盘/触控板遍历顺序与视觉顺序一致，焦点清晰。
- [ ] 所有主要控件触控热区至少 48 × 48vp。

### 13.5 动效与性能

- [ ] 按压、Switch、Segment、Tab 切换无明显卡顿或布局跳动。
- [ ] 长节点列表滚动稳定；首屏不因一次性渲染全部节点冻结。
- [ ] 批量测速逐项更新，不触发整页高频重建。
- [ ] 无非必要无限动画、呼吸光或大面积持续模糊重绘。
- [ ] 系统减少动态效果时，非必要位移/缩放被移除。

## 14. 官方参考

- [HarmonyOS 设计总览：空间感与沉浸光感](https://developer.huawei.com/consumer/cn/design/?catalogVersion=V1)
- [HarmonyOS 6.0/6.1 新能力：沉浸光感组件与悬浮页签](https://developer.huawei.com/consumer/cn/features/6-1)
- [HarmonyOS 设计入门](https://developer.huawei.com/consumer/cn/design/devstart/)
- [沉浸光感开发指导](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense)
- [Tabs ArkTS API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-tabs)
- [HarmonyOS Symbol 官方图标库](https://developer.huawei.com/consumer/en/design/harmonyos-symbol/)
- [ArkUI 响应式栅格布局](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-layout-development-grid-layout)
- [深浅色模式适配](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-dark-light-color-adaptation)
- [HarmonyOS 设备兼容要求](https://developer.huawei.com/consumer/cn/doc/doccenter-architecture/device-compatible)
- [焦点导航规范](https://developer.huawei.com/consumer/cn/doc/design-guides/hmi-focus-0000001748650376)
- [WCAG 2.2 对比度要求](https://www.w3.org/TR/WCAG22/#contrast-minimum)

## 15. 变更治理

本文件是冻结基线。后续修改必须：

1. 说明要解决的真机问题或官方规范变化；
2. 给出 API/设计依据；
3. 列出受影响页面和回归范围；
4. 不降低控件语义、状态真实性、深浅色、国际化和可访问性标准；
5. 经单独评审后提升文档版本。
