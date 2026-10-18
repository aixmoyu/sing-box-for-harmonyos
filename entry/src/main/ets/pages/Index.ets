import { CoreMetadataGateway } from '../core/CoreMetadataGateway'
import { picker } from '@kit.CoreFileKit'
import { readLocalDocument } from '../services/LocalDocumentReader'
import { prepareLocalConfig } from '../domain/LocalConfig'
import { LocalConfigStore } from '../services/LocalConfigStore'
import { common, ConfigurationConstant } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { i18n } from '@kit.LocalizationKit'
import type { CoreInfo, CoreStatus } from '../core/CoreGateway'
import {
  ConfigBuildResult,
  CoreLogLevel,
  NodeSelectionMode,
  NodeLatency,
  PolicyGroup,
  ProxyNode,
  RoutingRule,
  RunMode,
  SubscriptionBundle,
  SubscriptionRecord,
  SubscriptionStoreState
} from '../domain/Models.ts'
import {
  activeSubscription,
  emptySubscriptionStore,
  removeSubscription,
  renameSubscription,
  selectSubscriptionNode,
  setActiveSubscription,
  subscriptionDisplayName,
  upsertSubscription
} from '../domain/SubscriptionCatalog.ts'
import { SingBoxConfigBuilder } from '../domain/SingBoxConfigBuilder.ts'
import {
  EgressInfo,
  emptyEgressInfo,
  emptyWebsiteTestResults,
  WEBSITE_TEST_TARGETS,
  WebsiteTestResult,
  WebsiteTestTarget
} from '../domain/WebsiteTests.ts'
import {
  DnsPreset,
  DnsPresetId,
  DNS_PRESETS,
  defaultNetworkSettings,
  findDnsPreset,
  MAX_TRUSTED_APPLICATIONS,
  NetworkSettings,
  NETWORK_SETTINGS_SCHEMA,
  MAX_LOCAL_ROUTING_RULES,
  normalizeLocalRoutingRules,
  normalizeTrustedApplications,
  resolveDnsEndpoint,
  validateApplicationBundleName,
  validateDnsEndpoint,
  validateLocalRoutingRule,
  VpnApplicationMode,
  VpnApplicationScope,
  vpnApplicationScope
} from '../domain/NetworkSettings.ts'
import {
  planRuntimeReconfiguration,
  reconfigurationRecovery,
  RuntimeReconfigurationPlan
} from '../domain/RuntimeReconfiguration.ts'
import {
  classifyNodeLatency,
  compareNodeLatency,
  NodeLatencyQuality
} from '../domain/NodeLatencyQuality.ts'
import { NetworkSettingsRepository } from '../repositories/NetworkSettingsRepository'
import { SubscriptionRepository } from '../repositories/SubscriptionRepository'
import {
  ConnectionCoordinator,
  isConfirmedNoTunStartupError
} from '../services/ConnectionCoordinator'
import { NodeProbeService } from '../services/NodeProbeService'
import { SubscriptionService } from '../services/SubscriptionService'
import { WebsiteProbeService } from '../services/WebsiteProbeService'
import { VpnRuntimeConfigStore } from '../services/VpnRuntimeConfigStore'
import {
  ApplicationCatalogService,
  SelectableApplication
} from '../services/ApplicationCatalogService'
import {
  APP_TYPOGRAPHY,
  AppPalette,
  DARK_PALETTE,
  LIGHT_PALETTE,
  normalizedLanguagePreference,
  normalizedThemePreference,
  UI_LANGUAGE_KEY,
  UI_PREFERENCES_FILE,
  UI_PRIVACY_CONSENT_KEY,
  UI_THEME_KEY,
  UiLanguagePreference,
  UiThemePreference
} from '../ui/DesignSystem'
import { localizeRuntimeMessage } from '../ui/RuntimeMessages'
import { RELEASE_PUBLIC_INFO } from '../ui/ReleaseConfig'
import {
  APACHE_2_FULL_TEXT,
  GO_LICENSE_TEXT,
  GO_PATENTS_TEXT,
  GPL_V3_FULL_TEXT,
  SING_BOX_LICENSE_TEXT,
  THIRD_PARTY_NOTICE_TEXT
} from '../ui/OpenSourceTexts'

const NODE_RENDER_BATCH_SIZE: number = 50
const COMPACT_LAYOUT_MAX_WIDTH: number = 400

@Entry
@Component
struct Index {
  @StorageProp('colorMode') systemColorMode: ColorMode = ColorMode.DARK
  @StorageProp('languageCode') @Watch('onSystemLanguageCodeChanged') systemLanguageCode: string = 'zh'
  @State languagePreference: UiLanguagePreference = 'system'
  @State themePreference: UiThemePreference = 'system'
  @State effectiveLanguage: string = 'zh'
  @State appearanceReady: boolean = false
  @State currentTab: string = 'home'
  @State runMode: RunMode = 'global'
  @State nodeSelectionMode: NodeSelectionMode = 'manual'
  @State logLevel: CoreLogLevel = 'info'
  @State subscriptionUrl: string = ''
  @State newSubscriptionName: string = ''
  @State renamingSubscriptionId: string = ''
  @State renameSubscriptionDraft: string = ''
  @State subscriptionName: string = '尚未添加订阅'
  @State subscriptionFormat: string = '—'
  @State nodeCount: number = 0
  @State nodeFilter: string = ''
  @State nodeSortMode: string = 'default'
  @State nodeRenderLimit: number = NODE_RENDER_BATCH_SIZE
  @State viewportWidth: number = 360
  @State selectedNodeName: string = '未选择节点'
  @State runtimeSelectedNodeName: string = ''
  @State isImporting: boolean = false
  @State localConfigJson: string = ''
  @State localConfigDraft: string = ''
  @State localConfigMessage: string = '导入完整 sing-box JSON，无需订阅地址'
  @State localConfigLoading: boolean = false
  @State importMessage: string = '粘贴一个订阅地址，解析支持的节点、基础规则和 DNS'
  @State warningCount: number = 0
  @State latencyText: string = '— ms'
  @State proxyLatencyText: string = '— ms'
  @State isProxyTesting: boolean = false
  @State isProxyTestingAll: boolean = false
  @State proxyTestCompletedCount: number = 0
  @State proxyTestTotalCount: number = 0
  @State uploadSpeed: string = '暂未统计'
  @State downloadSpeed: string = '暂未统计'
  @State uploadRate: string = '0 B/s'
  @State downloadRate: string = '0 B/s'
  @State activeConnections: number = 0
  @State storeState: SubscriptionStoreState = emptySubscriptionStore()
  @State nodeLatencies: NodeLatency[] = []
  @State proxyNodeLatencies: NodeLatency[] = []
  @State probingNodeIds: string[] = []
  @State proxyTestingNodeIds: string[] = []
  @State isProbingAll: boolean = false
  @State isLoadingStore: boolean = true
  @State dnsPresetId: DnsPresetId = 'cloudflare'
  @State ipv6Enabled: boolean = true
  @State customDns: string = ''
  @State customDnsDraft: string = ''
  @State customDnsEditorOpen: boolean = false
  @State localRules: RoutingRule[] = []
  @State localRuleKind: string = 'domain'
  @State localRuleTarget: string = 'proxy'
  @State localRuleDraft: string = ''
  @State localRuleMessage: string = ''
  @State applicationMode: VpnApplicationMode = 'all'
  @State trustedApplications: string[] = []
  @State applicationCatalog: SelectableApplication[] = []
  @State applicationCatalogLoading: boolean = false
  @State applicationCatalogLoaded: boolean = false
  @State applicationEditorOpen: boolean = false
  @State applicationSearch: string = ''
  @State applicationBundleDraft: string = ''
  @State applicationMessage: string = ''
  @State dnsMessage: string = '默认使用加密 DNS；所有 DNS 请求由 TUN 交给 sing-box 处理'
  @State connectionPhase: string = 'checking'
  @State @Watch('recordConnectionEvent') connectionMessage: string = '正在检查 VPN 状态'
  @State settingsLoading: boolean = true
  @State configurationBusy: boolean = false
  @State activitySection: string = 'logs'
  @State connectionEvents: string[] = []
  @State reduceTransparency: boolean = false
  @State websiteTestResults: WebsiteTestResult[] = emptyWebsiteTestResults()
  @State isTestingWebsites: boolean = false
  @State egressInfo: EgressInfo = emptyEgressInfo()
  @State isTestingEgress: boolean = false
  @State revealEgressIp: boolean = false
  @State settingsDetail: string = ''
  @State clearingSensitiveData: boolean = false
  @State privacyConsent: string = 'unknown'
  @State privacyChangeBusy: boolean = false

  private subscriptionService: SubscriptionService = new SubscriptionService()
  private nodeProbeService: NodeProbeService = new NodeProbeService()
  private websiteProbeService: WebsiteProbeService = new WebsiteProbeService()
  private applicationCatalogService: ApplicationCatalogService = new ApplicationCatalogService()
  private configBuilder: SingBoxConfigBuilder = new SingBoxConfigBuilder()
  private subscriptionRepository: SubscriptionRepository | null = null
  private settingsRepository: NetworkSettingsRepository | null = null
  private connectionCoordinator: ConnectionCoordinator | null = null
  private coreInfo: CoreInfo = new CoreMetadataGateway().getInfo()
  private statusTimer: number = 0
  private previousStatsAt: number = 0
  private previousUploadBytes: number = 0
  private previousDownloadBytes: number = 0
  // Every runtime probe belongs to one concrete VPN session. Incrementing the
  // epoch makes late Promise completions from an older session harmless.
  private runtimeProbeEpoch: number = 0
  private runtimeWasRunning: boolean = false
  private runtimeSelectedOutboundTag: string = ''
  // TCP reachability probes are valid only while the app remains fully idle.
  // Starting a VPN increments this epoch so pending sockets cannot publish a
  // result measured across the TUN transition.
  private idleProbeEpoch: number = 0
  // Every connected reconfiguration owns one token. An explicit user stop
  // increments the epoch so stop always wins and a stale transaction can
  // never reconnect after the user asked to disconnect.
  private reconfigurationEpoch: number = 0
  private uiPreferences: preferences.Preferences | null = null

  aboutToAppear(): void {
    this.restoreAppearance()
    this.restoreSubscriptions()
    this.restoreSettingsAndRuntime()
    this.startStatusPolling()
  }

  private palette(): AppPalette {
    if (this.themePreference === 'dark') return DARK_PALETTE
    if (this.themePreference === 'light') return LIGHT_PALETTE
    return this.systemColorMode === ColorMode.DARK ? DARK_PALETTE : LIGHT_PALETTE
  }

  private onSystemLanguageCodeChanged(): void {
    if (this.languagePreference !== 'system') return
    this.effectiveLanguage = this.systemLanguageCode.toLowerCase().startsWith('en') ? 'en' : 'zh'
  }

  private t(zh: string, en: string): string {
    return this.effectiveLanguage === 'en' ? en : zh
  }

  private isEnglish(): boolean {
    return this.effectiveLanguage === 'en'
  }

  private runModeUiLabel(mode: RunMode): string {
    if (mode === 'rule') return this.t('规则', 'Rule')
    if (mode === 'global') return this.t('全局代理', 'Global')
    return this.t('直连', 'Direct')
  }

  private selectionModeUiLabel(mode: NodeSelectionMode): string {
    if (mode === 'manual') return this.t('手动', 'Manual')
    if (mode === 'auto') return this.t('自动优选', 'Auto')
    return this.t('周期故障', 'Failover')
  }

  private recordConnectionEvent(): void {
    const timestamp: string = new Date().toLocaleTimeString()
    this.connectionEvents = [`${timestamp}  ${this.localizedRuntimeText(this.connectionMessage)}`, ...this.connectionEvents].slice(0, 200)
  }

  private activitySectionUiLabel(section: string): string {
    if (section === 'logs') return this.t('连接事件', 'Events')
    if (section === 'overview') return this.t('运行数据', 'Runtime')
    if (section === 'rules') return this.t('配置预览', 'Rules')
    return this.t('可达性', 'Reachability')
  }

  private languagePreferenceUiLabel(preference: UiLanguagePreference): string {
    if (preference === 'system') return this.t('跟随系统', 'System')
    if (preference === 'zh') return this.t('中文', 'Chinese')
    return this.t('英文', 'English')
  }

  private themePreferenceUiLabel(preference: UiThemePreference): string {
    if (preference === 'system') return this.t('跟随系统', 'System')
    if (preference === 'light') return this.t('浅色', 'Light')
    return this.t('深色', 'Dark')
  }

  private primaryTabUiLabel(tab: string): string {
    if (tab === 'home') return this.t('仪表盘', 'Dashboard')
    if (tab === 'proxy') return this.t('代理', 'Proxies')
    if (tab === 'subscription') return this.t('配置', 'Profiles')
    if (tab === 'activity') return this.t('日志', 'Logs')
    return this.t('设置', 'Settings')
  }

  private releaseFieldUiLabel(field: string): string {
    if (field === 'operator') return this.t('运营主体', 'Operator')
    if (field === 'privacy') return this.t('隐私政策', 'Privacy policy')
    if (field === 'agreement') return this.t('用户协议', 'User agreement')
    if (field === 'support') return this.t('支持站点', 'Support site')
    if (field === 'email') return this.t('客服邮箱', 'Support email')
    return this.t('精确版本对应源码', 'Exact-version corresponding source')
  }

  private localLegalTitle(kind: string): string {
    if (kind === 'privacy') return this.t('隐私与数据详情', 'Privacy & data details')
    if (kind === 'agreement') return this.t('本地用户协议', 'Local user agreement')
    if (kind === 'gpl') return this.t('GNU GPL 第三版完整许可文本', 'GNU GPL version 3 · complete text')
    return this.t('sing-box 与第三方声明', 'sing-box & third-party notices')
  }

  private localLegalBody(kind: string): string {
    if (kind === 'privacy') return this.privacyDetails()
    if (kind === 'agreement') return this.userAgreementDetails()
    if (kind === 'gpl') return GPL_V3_FULL_TEXT
    return `${SING_BOX_LICENSE_TEXT}\n\n${THIRD_PARTY_NOTICE_TEXT}\n\n` +
      `===== Apache License 2.0 (gVisor) =====\n\n${APACHE_2_FULL_TEXT}\n\n` +
      `===== Go BSD-style License =====\n\n${GO_LICENSE_TEXT}\n\n` +
      `===== Go PATENTS notice =====\n\n${GO_PATENTS_TEXT}`
  }

  private localizedRuntimeText(value: string): string {
    return localizeRuntimeMessage(value, this.effectiveLanguage,
      this.dnsPresetDisplayName(findDnsPreset(this.dnsPresetId)))
  }

  private localizedSubscriptionName(value: string): string {
    return value === '尚未添加订阅' ? this.t('尚未添加订阅', 'No subscription yet') : value
  }

  private localizedNodeName(value: string): string {
    return value === '未选择节点' ? this.t('未选择节点', 'No node selected') : value
  }

  private applicationContext(): common.UIAbilityContext {
    const context: Object | undefined = this.getUIContext().getHostContext()
    if (!context) throw new Error('UI ability context unavailable')
    return context as common.UIAbilityContext
  }

  private async openReleaseLink(url: string): Promise<void> {
    const normalizedUrl: string = url.trim()
    if (!this.isReleaseHttps(url)) {
      this.showToast(this.t('正式发布链接尚未配置或格式无效',
        'The release link is not configured or is invalid.'))
      return
    }
    try {
      await this.applicationContext().openLink(normalizedUrl)
    } catch (_) {
      this.showToast(this.t('无法打开正式发布链接', 'Could not open the release link.'))
    }
  }

  private isReleaseHttps(value: string): boolean {
    const normalized: string = value.trim()
    return normalized.length === value.length && /^https:\/\/[^/\s]+(?:\/[^\s]*)?$/.test(normalized)
  }

  private isReleaseEmail(value: string): boolean {
    const normalized: string = value.trim()
    return normalized.length === value.length && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalized)
  }

  private releasePublicInfoReady(): boolean {
    return RELEASE_PUBLIC_INFO.operatorName.trim().length > 0 &&
      this.isReleaseHttps(RELEASE_PUBLIC_INFO.privacyUrl) &&
      this.isReleaseHttps(RELEASE_PUBLIC_INFO.privacyUrlEn) &&
      this.isReleaseHttps(RELEASE_PUBLIC_INFO.userAgreementUrl) &&
      this.isReleaseHttps(RELEASE_PUBLIC_INFO.userAgreementUrlEn) &&
      this.isReleaseHttps(RELEASE_PUBLIC_INFO.supportUrl) &&
      this.isReleaseEmail(RELEASE_PUBLIC_INFO.supportEmail) &&
      this.isReleaseHttps(RELEASE_PUBLIC_INFO.correspondingSourceUrl)
  }

  private releaseBlockedText(value: string): string {
    return value.trim().length > 0 ?
      this.t('配置无效 · 发布阻塞', 'Invalid configuration · Release blocked') :
      this.t('未配置 · 发布阻塞', 'Not configured · Release blocked')
  }

  private async restoreAppearance(): Promise<void> {
    try {
      const context: common.UIAbilityContext = this.applicationContext()
      this.uiPreferences = await preferences.getPreferences(context, UI_PREFERENCES_FILE)
      this.reduceTransparency = (await this.uiPreferences.get('reduce-transparency', false)) === true
      const language: string = `${this.uiPreferences.getSync(UI_LANGUAGE_KEY, 'system')}`
      const theme: string = `${this.uiPreferences.getSync(UI_THEME_KEY, 'system')}`
      this.languagePreference = normalizedLanguagePreference(language)
      this.themePreference = normalizedThemePreference(theme)
      const consent: string = `${this.uiPreferences.getSync(UI_PRIVACY_CONSENT_KEY, 'unknown')}`
      this.privacyConsent = consent === 'accepted' || consent === 'declined' ? consent : 'unknown'
      this.applyLanguagePreference(this.languagePreference)
      this.applyThemePreference(this.themePreference)
    } catch (_) {
      this.effectiveLanguage = i18n.System.getSystemLanguage().toLowerCase().startsWith('en') ? 'en' : 'zh'
    } finally {
      this.appearanceReady = true
    }
  }

  private applyLanguagePreference(preference: UiLanguagePreference): void {
    const systemLanguage: string = i18n.System.getSystemLanguage()
    const language: string = preference === 'system' ? systemLanguage : (preference === 'en' ? 'en-US' : 'zh-CN')
    this.effectiveLanguage = language.toLowerCase().startsWith('en') ? 'en' : 'zh'
    try {
      i18n.System.setAppPreferredLanguage(preference === 'system' ? 'default' : language)
      if (preference !== 'system') this.applicationContext().getApplicationContext().setLanguage(language)
    } catch (_) {
      // The in-page language state still updates when the application context is temporarily unavailable.
    }
  }

  private applyThemePreference(preference: UiThemePreference): void {
    const colorMode: ConfigurationConstant.ColorMode = preference === 'dark' ?
      ConfigurationConstant.ColorMode.COLOR_MODE_DARK : (preference === 'light' ?
        ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
    try {
      this.applicationContext().getApplicationContext().setColorMode(colorMode)
    } catch (_) {
      // The preference remains saved and will be restored on the next launch.
    }
  }

  private async selectLanguagePreference(preference: UiLanguagePreference): Promise<void> {
    if (this.languagePreference === preference) return
    this.languagePreference = preference
    this.applyLanguagePreference(preference)
    try {
      if (!this.uiPreferences) {
        this.uiPreferences = await preferences.getPreferences(this.applicationContext(), UI_PREFERENCES_FILE)
      }
      this.uiPreferences.putSync(UI_LANGUAGE_KEY, preference)
      this.uiPreferences.flushSync()
    } catch (_) {
      this.showToast(this.t('语言偏好未能保存', 'Language preference could not be saved'))
    }
  }

  private async selectThemePreference(preference: UiThemePreference): Promise<void> {
    if (this.themePreference === preference) return
    this.themePreference = preference
    this.applyThemePreference(preference)
    try {
      if (!this.uiPreferences) {
        this.uiPreferences = await preferences.getPreferences(this.applicationContext(), UI_PREFERENCES_FILE)
      }
      this.uiPreferences.putSync(UI_THEME_KEY, preference)
      this.uiPreferences.flushSync()
    } catch (_) {
      this.showToast(this.t('主题偏好未能保存', 'Theme preference could not be saved'))
    }
  }

  private async savePrivacyConsent(consent: string): Promise<boolean> {
    const nextConsent: string = consent === 'accepted' ? 'accepted' : 'declined'
    try {
      if (!this.uiPreferences) {
        this.uiPreferences = await preferences.getPreferences(this.applicationContext(), UI_PREFERENCES_FILE)
      }
      this.uiPreferences.putSync(UI_PRIVACY_CONSENT_KEY, nextConsent)
      this.uiPreferences.flushSync()
      // The feature gate changes only after durable local persistence. A failed
      // write must never make this process appear to have accepted consent.
      this.privacyConsent = nextConsent
      return true
    } catch (_) {
      this.showToast('隐私选择保存失败')
      return false
    }
  }

  private async declinePrivacyConsent(): Promise<void> {
    if (!await this.savePrivacyConsent('declined')) return
    // A previous app version may already own a live TUN before this consent
    // schema is introduced. Refusal takes effect immediately and triggers the
    // safest available teardown; it never starts or reconnects a session.
    if (this.connectionPhase === 'idle') return
    const coordinator: ConnectionCoordinator | null = this.connectionCoordinator
    if (!coordinator || this.isConnectionBusy()) return
    this.reconfigurationEpoch++
    this.invalidateRuntimeProbes()
    this.connectionPhase = 'stopping'
    this.connectionMessage = '正在停止核心并销毁 TUN…'
    try {
      const stopped: CoreStatus = await coordinator.disconnect()
      this.applyCoreStatus(stopped)
    } catch (error) {
      const message: string = error instanceof Error ? error.message : 'VPN 安全停止失败'
      this.connectionPhase = 'unknown'
      this.connectionMessage = `${message}；配置仍保持锁定`
      this.showToast(message)
    }
  }

  private networkConsentGranted(): boolean {
    if (this.privacyConsent === 'accepted') return true
    this.showToast('此功能需要先同意本机隐私摘要；当前为离线受限模式')
    this.currentTab = 'settings'
    return false
  }

  private privacyConsentSwitchEnabled(): boolean {
    if (this.privacyChangeBusy || this.configurationBusy || this.settingsLoading || this.isConnectionBusy()) return false
    if (this.privacyConsent === 'accepted') return this.connectionPhase === 'idle'
    return this.privacyConsent === 'declined'
  }

  private async setNetworkConsentEnabled(enabled: boolean): Promise<void> {
    if (enabled === (this.privacyConsent === 'accepted')) return
    if (enabled) {
      if (this.privacyConsent !== 'declined' || !this.privacyConsentSwitchEnabled()) return
      this.privacyChangeBusy = true
      try {
        if (await this.savePrivacyConsent('accepted')) {
          this.showToast(this.t('联网功能已启用', 'Network features enabled'))
        }
      } finally {
        this.privacyChangeBusy = false
      }
      return
    }
    this.confirmWithdrawPrivacyConsent()
  }

  private confirmWithdrawPrivacyConsent(): void {
    if (this.connectionPhase !== 'idle' || this.isConnectionBusy() || this.configurationBusy) {
      this.showToast('请先安全断开 VPN，再撤回隐私同意')
      return
    }
    if (this.privacyChangeBusy) return
    this.privacyChangeBusy = true
    try {
      this.getUIContext().getPromptAction().showDialog({
        title: this.t('撤回隐私同意', 'Withdraw privacy consent'),
        message: this.t('撤回后会进入离线受限模式：不能导入/更新订阅、连接 VPN 或执行联网诊断。已有本地数据不会自动删除，可另行使用“清除本地敏感数据”。',
          'After withdrawal, offline limited mode blocks profile import/update, VPN connection and network diagnostics. Existing local data is not deleted automatically; use Clear local sensitive data separately if needed.'),
        buttons: [
          { text: this.t('取消', 'Cancel'), color: this.palette().textSecondary },
          { text: this.t('撤回同意', 'Withdraw'), color: this.palette().danger }
        ]
      }).then((result) => {
        if (result.index === 1) this.withdrawPrivacyConsent()
        this.privacyChangeBusy = false
      }).catch(() => {
        this.privacyChangeBusy = false
        this.showToast('撤回确认窗口打开失败')
      })
    } catch (_) {
      this.privacyChangeBusy = false
      this.showToast('撤回确认窗口打开失败')
    }
  }

  private async withdrawPrivacyConsent(): Promise<void> {
    if (this.configurationBusy || this.isConnectionBusy() || this.connectionPhase !== 'idle') {
      this.showToast('请先安全断开 VPN，再撤回隐私同意')
      return
    }
    const coordinator: ConnectionCoordinator | null = this.connectionCoordinator
    if (!coordinator) {
      this.showToast('连接服务仍在初始化，请稍后重试')
      return
    }
    this.configurationBusy = true
    try {
      // The coordinator readback is authoritative. Holding configurationBusy
      // closes the race with a simultaneous connect request while consent is
      // being withdrawn.
      const status: CoreStatus = await coordinator.getStatus()
      if (this.connectionPhase !== 'idle' || status.running || status.lastError.length > 0) {
        this.showToast('请先安全断开 VPN，再撤回隐私同意')
        return
      }
      if (await this.savePrivacyConsent('declined')) {
        this.showToast('隐私同意已撤回；应用已进入离线受限模式')
      }
    } catch (_) {
      this.showToast('VPN 状态确认失败，未撤回隐私同意')
    } finally {
      this.configurationBusy = false
    }
  }

  aboutToDisappear(): void {
    if (this.statusTimer !== 0) {
      clearInterval(this.statusTimer)
      this.statusTimer = 0
    }
  }

  private startStatusPolling(): void {
    if (this.statusTimer !== 0) return
    this.statusTimer = setInterval(() => {
      if (!this.isConnectionBusy() && !this.configurationBusy) {
        this.syncConnectionStatus()
      }
    }, 2000)
  }

  private activeRecord(): SubscriptionRecord | undefined {
    return activeSubscription(this.storeState)
  }

  private isCompactLayout(): boolean {
    return this.viewportWidth > 0 && this.viewportWidth <= COMPACT_LAYOUT_MAX_WIDTH
  }

  private matchingNodes(): ProxyNode[] {
    const record: SubscriptionRecord | undefined = this.activeRecord()
    if (!record) return []
    const query: string = this.nodeFilter.trim().toLowerCase()
    const matched: ProxyNode[] = query.length === 0 ? record.bundle.nodes.slice() :
      record.bundle.nodes.filter((node: ProxyNode) =>
        node.name.toLowerCase().includes(query) || node.protocol.toLowerCase().includes(query))
    if (this.nodeSortMode !== 'latency') return matched
    // Stable insertion sort preserves the profile order among untested and
    // failed nodes while successful readings move ahead by ascending latency.
    for (let index: number = 1; index < matched.length; index++) {
      const candidate: ProxyNode = matched[index]
      const candidateLatency: number | undefined = this.nodeLatencyResult(candidate.id)
      let insertAt: number = index
      while (insertAt > 0 && compareNodeLatency(candidateLatency,
        this.nodeLatencyResult(matched[insertAt - 1].id)) < 0) {
        matched[insertAt] = matched[insertAt - 1]
        insertAt--
      }
      matched[insertAt] = candidate
    }
    return matched
  }

  private visibleNodes(): ProxyNode[] {
    return this.matchingNodes().slice(0, this.nodeRenderLimit)
  }

  private resetNodeWindow(clearFilter: boolean): void {
    this.nodeRenderLimit = NODE_RENDER_BATCH_SIZE
    if (clearFilter) this.nodeFilter = ''
  }

  private updateNodeFilter(value: string): void {
    this.nodeFilter = value
    this.resetNodeWindow(false)
  }

  private setNodeSortMode(mode: string): void {
    if (mode !== 'default' && mode !== 'latency') return
    this.nodeSortMode = mode
    this.resetNodeWindow(false)
  }

  private loadMoreNodes(): void {
    this.nodeRenderLimit = Math.min(this.matchingNodes().length,
      this.nodeRenderLimit + NODE_RENDER_BATCH_SIZE)
  }

  private visibleRules(): RoutingRule[] {
    const record: SubscriptionRecord | undefined = this.activeRecord()
    return record ? record.bundle.rules.slice(0, 200) : []
  }

  private subscriptionRuleBlockerCount(): number {
    const record: SubscriptionRecord | undefined = this.activeRecord()
    if (!record) return 0
    return record.bundle.rules.filter((rule: RoutingRule) =>
      rule.kind === 'unsupported' || rule.kind === 'rule_set' || !this.hasConnectedRuleTarget(record.bundle, rule.target)).length
  }

  private selectedNode(record: SubscriptionRecord): ProxyNode | undefined {
    return record.bundle.nodes.find((node: ProxyNode) => node.id === record.selectedNodeId)
  }

  private hasConnectedRuleTarget(bundle: SubscriptionBundle, target: string): boolean {
    if (target === 'proxy' || target === 'direct' || target === 'reject') return true
    return bundle.policyGroups.some((group: PolicyGroup) => group.name === target &&
      group.nodeIds.some((nodeId: string) => bundle.nodes.some((node: ProxyNode) => node.id === nodeId)))
  }

  private applyStoreState(state: SubscriptionStoreState): void {
    const previousRecord: SubscriptionRecord | undefined = activeSubscription(this.storeState)
    const nextRecord: SubscriptionRecord | undefined = activeSubscription(state)
    const activeSubscriptionChanged: boolean = this.storeState.activeSubscriptionId !== state.activeSubscriptionId
    const activeNodeSetChanged: boolean = !!previousRecord && !!nextRecord &&
      previousRecord.bundle.nodes !== nextRecord.bundle.nodes
    this.storeState = state
    if (activeSubscriptionChanged || activeNodeSetChanged) this.resetNodeWindow(true)
    const record: SubscriptionRecord | undefined = nextRecord
    if (!record) {
      this.subscriptionName = '尚未添加订阅'
      this.subscriptionFormat = '—'
      this.nodeCount = 0
      this.selectedNodeName = '未选择节点'
      this.warningCount = 0
      this.latencyText = '— ms'
      this.proxyLatencyText = '— ms'
      return
    }
    const selected: ProxyNode | undefined = this.selectedNode(record)
    this.subscriptionName = subscriptionDisplayName(record)
    this.subscriptionFormat = record.bundle.metadata.sourceFormat
    this.nodeCount = record.bundle.nodes.length
    this.selectedNodeName = selected ? selected.name : '未选择节点'
    this.warningCount = record.bundle.warnings.length
    this.latencyText = selected ? this.latencyLabel(selected.id) : '— ms'
  }

  private async restoreSubscriptions(): Promise<void> {
    this.isLoadingStore = true
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
      const repository: SubscriptionRepository = new SubscriptionRepository(context.filesDir)
      this.localConfigJson = (await new LocalConfigStore(context.filesDir).load()) || ''
      if (this.localConfigJson) this.localConfigMessage = '当前使用已保存的本地配置'
      this.subscriptionRepository = repository
      const state: SubscriptionStoreState = await repository.load()
      this.applyStoreState(state)
      if (state.records.length > 0) {
        this.importMessage = `已恢复 ${state.records.length} 个订阅，点击卡片可切换`
      }
    } catch (_) {
      this.importMessage = '本地订阅读取失败；旧数据未被覆盖'
      this.showToast(this.importMessage)
    } finally {
      this.isLoadingStore = false
    }
  }

  private currentNetworkSettings(): NetworkSettings {
    return {
      schemaVersion: NETWORK_SETTINGS_SCHEMA,
      runMode: this.runMode,
      nodeSelectionMode: this.nodeSelectionMode,
      logLevel: this.logLevel,
      ipv6Enabled: this.ipv6Enabled,
      dnsPresetId: this.dnsPresetId,
      customDns: this.customDns,
      localRules: this.localRules,
      applicationMode: this.applicationMode,
      trustedApplications: this.trustedApplications.slice()
    }
  }

  private async restoreSettingsAndRuntime(): Promise<void> {
    this.settingsLoading = true
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
      this.settingsRepository = new NetworkSettingsRepository(context.filesDir)
      this.connectionCoordinator = new ConnectionCoordinator(context)
      const settings: NetworkSettings = await this.settingsRepository.load()
      this.runMode = settings.runMode
      this.nodeSelectionMode = settings.nodeSelectionMode
      this.logLevel = settings.logLevel
      this.ipv6Enabled = settings.ipv6Enabled
      this.dnsPresetId = settings.dnsPresetId
      this.customDns = settings.customDns
      this.customDnsDraft = settings.customDns
      this.localRules = settings.localRules.slice()
      this.applicationMode = settings.applicationMode
      this.trustedApplications = settings.trustedApplications.slice()
      this.coreInfo = this.connectionCoordinator.getInfo()
      if (!this.coreInfo.available) {
        this.connectionMessage = `安全锁定：${this.coreInfo.reason}`
      }
      await this.syncConnectionStatus()
    } catch (error) {
      const message: string = error instanceof Error ? error.message : '网络设置读取失败'
      this.dnsMessage = `${message}；使用本次默认设置`
      this.connectionPhase = 'unknown'
      this.connectionMessage = 'VPN 状态尚未确认'
    } finally {
      this.settingsLoading = false
    }
  }

  private async saveNetworkSettings(): Promise<void> {
    const repository: NetworkSettingsRepository | null = this.settingsRepository
    if (!repository) throw new Error('网络设置存储尚未就绪')
    await repository.save(this.currentNetworkSettings())
  }

  private applyNetworkSettings(settings: NetworkSettings): void {
    const previousCustomDns: string = this.customDns
    this.runMode = settings.runMode
    this.nodeSelectionMode = settings.nodeSelectionMode
    this.logLevel = settings.logLevel
    this.ipv6Enabled = settings.ipv6Enabled
    this.dnsPresetId = settings.dnsPresetId
    this.customDns = settings.customDns
    this.localRules = settings.localRules.slice()
    this.applicationMode = settings.applicationMode
    this.trustedApplications = settings.trustedApplications.slice()
    // Keep a genuinely unsaved editor draft while changing an unrelated
    // setting. A DNS save/rollback changes customDns itself and therefore must
    // update the editor to the value that was actually persisted.
    if (this.customDnsDraft === previousCustomDns || previousCustomDns !== settings.customDns) {
      this.customDnsDraft = settings.customDns
    }
  }

  private buildRuntimeConfigJson(state: SubscriptionStoreState, settings: NetworkSettings): string {
    const record: SubscriptionRecord | undefined = activeSubscription(state)
    if (!record || record.bundle.nodes.length === 0 || record.selectedNodeId.length === 0) {
      throw new Error('请先添加订阅并选择节点')
    }
    const unresolvedRule: RoutingRule | undefined = record.bundle.rules.find((rule: RoutingRule) =>
      rule.kind === 'rule_set' || rule.kind === 'unsupported')
    const unconnectedTargetRule: RoutingRule | undefined = record.bundle.rules.find((rule: RoutingRule) =>
      !this.hasConnectedRuleTarget(record.bundle, rule.target))
    if (settings.runMode === 'rule' && (unresolvedRule || unconnectedTargetRule)) {
      if (unconnectedTargetRule) {
        throw new Error(`当前订阅规则引用尚未接通的策略组“${unconnectedTargetRule.target}”；请先使用全局代理或直连模式`)
      }
      if (unresolvedRule && unresolvedRule.kind === 'rule_set') {
        throw new Error('当前订阅依赖尚未下载的远程规则集；请先使用全局代理或直连模式')
      }
      throw new Error('当前订阅包含尚未支持的规则类型；请先使用全局代理或直连模式')
    }
    const dnsEndpoint: string = resolveDnsEndpoint(settings)
    const buildResult: ConfigBuildResult = this.configBuilder.build({
      bundle: record.bundle,
      mode: settings.runMode,
      selectedNodeId: record.selectedNodeId,
      selectionMode: settings.nodeSelectionMode,
      logLevel: settings.logLevel,
      ipv6Enabled: settings.ipv6Enabled,
      localRules: settings.localRules
    }, dnsEndpoint)
    return buildResult.configJson
  }

  private async persistRuntimeSnapshot(state: SubscriptionStoreState, settings: NetworkSettings,
    storeChanged: boolean, settingsChanged: boolean): Promise<void> {
    if (storeChanged && settingsChanged) {
      throw new Error('一次运行配置事务只能修改订阅或网络设置之一')
    }
    if (storeChanged) {
      const repository: SubscriptionRepository | null = this.subscriptionRepository
      if (!repository) throw new Error('订阅存储尚未就绪')
      await repository.save(state)
    }
    if (settingsChanged) {
      const repository: NetworkSettingsRepository | null = this.settingsRepository
      if (!repository) throw new Error('网络设置存储尚未就绪')
      await repository.save(settings)
    }
  }

  private applyRuntimeSnapshot(state: SubscriptionStoreState, settings: NetworkSettings,
    storeChanged: boolean, settingsChanged: boolean): void {
    if (storeChanged) this.applyStoreState(state)
    if (settingsChanged) this.applyNetworkSettings(settings)
  }

  private async reconnectPreviousRuntime(action: string, coordinator: ConnectionCoordinator,
    previousState: SubscriptionStoreState, previousSettings: NetworkSettings,
    previousConfigJson: string, storeChanged: boolean, settingsChanged: boolean,
    changeError: string, token: number): Promise<boolean> {
    if (token !== this.reconfigurationEpoch) return false
    try {
      await this.persistRuntimeSnapshot(previousState, previousSettings, storeChanged, settingsChanged)
      if (token !== this.reconfigurationEpoch) return false
      this.applyRuntimeSnapshot(previousState, previousSettings, storeChanged, settingsChanged)
    } catch (_) {
      this.connectionPhase = 'idle'
      this.connectionMessage = `${action}失败；旧配置恢复保存失败，VPN 保持断开`
      this.showToast(`${changeError}；旧配置恢复保存失败，VPN 已保持断开`)
      return false
    }

    this.invalidateIdleProbes()
    this.connectionPhase = 'starting'
    this.connectionMessage = `${action}失败，正在恢复原连接…`
    try {
      if (token !== this.reconfigurationEpoch) return false
      this.connectionPhase = 'authorizing'
      const restoredStatus: CoreStatus = await coordinator.connect(previousConfigJson,
        vpnApplicationScope(previousSettings))
      if (token !== this.reconfigurationEpoch) {
        // The user requested stop while connect was in-flight. Do not publish
        // success; perform the winning stop against this newly claimed session.
        this.connectionPhase = 'stopping'
        this.connectionMessage = '正在执行用户请求的安全停止…'
        const stoppedStatus: CoreStatus = await coordinator.disconnect()
        this.applyCoreStatus(stoppedStatus)
        return false
      }
      if (!restoredStatus.running) throw new Error('核心未确认原连接已恢复')
      this.applyCoreStatus(restoredStatus)
      this.showToast(`${changeError}；已恢复原设置和原连接`)
      return false
    } catch (error) {
      const restoreMessage: string = error instanceof Error ? error.message : '原连接恢复失败'
      if (isConfirmedNoTunStartupError(restoreMessage)) {
        this.connectionPhase = 'idle'
        this.connectionMessage = `${action}失败；原设置已恢复，但 VPN 当前断开`
      } else {
        this.connectionPhase = 'unknown'
        this.connectionMessage = `${action}失败且原连接恢复结果未知；请安全停止并检查`
      }
      this.showToast(`${changeError}；原设置已恢复，但原连接恢复失败：${restoreMessage}`)
      return false
    }
  }

  private async commitRuntimeReconfiguration(action: string, plan: RuntimeReconfigurationPlan,
    nextState: SubscriptionStoreState, nextSettings: NetworkSettings,
    storeChanged: boolean, settingsChanged: boolean, successMessage: string): Promise<boolean> {
    const previousState: SubscriptionStoreState = this.storeState
    const previousSettings: NetworkSettings = this.currentNetworkSettings()

    if (plan === 'reject') return false

    if (plan === 'persist-only') {
      try {
        await this.persistRuntimeSnapshot(nextState, nextSettings, storeChanged, settingsChanged)
        this.applyRuntimeSnapshot(nextState, nextSettings, storeChanged, settingsChanged)
        this.invalidateRuntimeProbes()
        this.showToast(successMessage)
        return true
      } catch (error) {
        const message: string = error instanceof Error ? error.message : `${action}保存失败`
        this.showToast(`${message}，原设置未改变`)
        return false
      }
    }

    const coordinator: ConnectionCoordinator | null = this.connectionCoordinator
    if (!coordinator) {
      this.showToast('VPN 运行协调器尚未就绪')
      return false
    }

    let previousConfigJson: string
    let nextConfigJson: string
    try {
      // Both configurations are generated before touching the current TUN.
      // Native CheckConfig still runs inside the Extension after TUN creation;
      // startup rollback remains authoritative if native validation rejects it.
      previousConfigJson = this.buildRuntimeConfigJson(previousState, previousSettings)
      nextConfigJson = this.buildRuntimeConfigJson(nextState, nextSettings)
      vpnApplicationScope(previousSettings)
      vpnApplicationScope(nextSettings)
    } catch (error) {
      const message: string = error instanceof Error ? error.message : '新运行配置无法生成'
      this.showToast(`${message}；当前连接和设置未改变`)
      return false
    }

    const token: number = ++this.reconfigurationEpoch
    this.invalidateRuntimeProbes()
    this.connectionPhase = 'stopping'
    this.connectionMessage = `${action}：正在安全停止当前 VPN/TUN…`
    try {
      const stoppedStatus: CoreStatus = await coordinator.disconnect()
      if (token !== this.reconfigurationEpoch) return false
      if (stoppedStatus.running) throw new Error('核心未确认当前 VPN 已停止')
      this.applyCoreStatus(stoppedStatus)
    } catch (error) {
      const message: string = error instanceof Error ? error.message : '当前 VPN 安全停止失败'
      this.connectionPhase = 'unknown'
      this.connectionMessage = `${action}未执行：${message}；设置未改变`
      this.showToast(this.connectionMessage)
      return false
    }

    try {
      await this.persistRuntimeSnapshot(nextState, nextSettings, storeChanged, settingsChanged)
      if (token !== this.reconfigurationEpoch) return false
      this.applyRuntimeSnapshot(nextState, nextSettings, storeChanged, settingsChanged)
    } catch (error) {
      const message: string = error instanceof Error ? error.message : `${action}保存失败`
      return await this.reconnectPreviousRuntime(action, coordinator, previousState, previousSettings,
        previousConfigJson, storeChanged, settingsChanged, message, token)
    }

    this.invalidateIdleProbes()
    this.connectionPhase = 'starting'
    this.connectionMessage = `${action}：新配置已保存，正在重新连接…`
    try {
      if (token !== this.reconfigurationEpoch) return false
      this.connectionPhase = 'authorizing'
      const status: CoreStatus = await coordinator.connect(nextConfigJson,
        vpnApplicationScope(nextSettings))
      if (token !== this.reconfigurationEpoch) {
        this.connectionPhase = 'stopping'
        this.connectionMessage = '正在执行用户请求的安全停止…'
        const stoppedStatus: CoreStatus = await coordinator.disconnect()
        this.applyCoreStatus(stoppedStatus)
        return false
      }
      if (!status.running) throw new Error('核心未确认新配置正在运行')
      this.applyCoreStatus(status)
      this.showToast(`${successMessage}，VPN 已按新配置重新连接`)
      return true
    } catch (error) {
      const message: string = error instanceof Error ? error.message : '新配置连接失败'
      if (reconfigurationRecovery(isConfirmedNoTunStartupError(message)) === 'rollback-and-reconnect') {
        return await this.reconnectPreviousRuntime(action, coordinator, previousState, previousSettings,
          previousConfigJson, storeChanged, settingsChanged, message, token)
      }
      // The runtime outcome is unknown. Starting the old configuration could
      // create a second VPN, while reverting the labels would misrepresent a
      // possibly running new configuration. Keep the new persisted choice and
      // lock controls until the user performs an authoritative safe stop.
      this.connectionPhase = 'unknown'
      this.connectionMessage = `${action}已保存，但重新连接结果未知：${message}`
      this.showToast(`${this.connectionMessage}；请安全停止并检查`)
      return false
    }
  }

  private async selectRunMode(mode: RunMode): Promise<void> {
    if (mode === this.runMode) return
    const plan: RuntimeReconfigurationPlan = this.runtimeReconfigurationPlan('切换路由模式')
    if (plan === 'reject') return
    this.configurationBusy = true
    const nextSettings: NetworkSettings = this.currentNetworkSettings()
    nextSettings.runMode = mode
    try {
      await this.commitRuntimeReconfiguration('切换路由模式', plan, this.storeState, nextSettings,
        false, true, `路由模式已切换为${mode === 'rule' ? '规则' : (mode === 'global' ? '全局代理' : '直连')}`)
    } finally {
      this.endRuntimeConfigurationMutation()
    }
  }

  private async selectNodeSelectionMode(mode: NodeSelectionMode): Promise<void> {
    if (mode === this.nodeSelectionMode) return
    const plan: RuntimeReconfigurationPlan = this.runtimeReconfigurationPlan('切换节点策略')
    if (plan === 'reject') return
    this.configurationBusy = true
    const nextSettings: NetworkSettings = this.currentNetworkSettings()
    nextSettings.nodeSelectionMode = mode
    try {
      const changed: boolean = await this.commitRuntimeReconfiguration('切换节点策略', plan,
        this.storeState, nextSettings, false, true, mode === 'manual' ? '已切换为手动选点' :
          (mode === 'auto' ? '已切换为自动优选' : '已切换为周期故障转移'))
      if (changed) this.proxyLatencyText = '— ms'
    } finally {
      this.endRuntimeConfigurationMutation()
    }
  }

  private async selectLogLevel(level: CoreLogLevel): Promise<void> {
    if (level === this.logLevel) return
    const plan: RuntimeReconfigurationPlan = this.runtimeReconfigurationPlan('切换日志等级')
    if (plan === 'reject') return
    this.configurationBusy = true
    const nextSettings: NetworkSettings = this.currentNetworkSettings()
    nextSettings.logLevel = level
    try {
      await this.commitRuntimeReconfiguration('切换日志等级', plan, this.storeState, nextSettings,
        false, true, `核心日志等级已设为 ${level}`)
    } finally {
      this.endRuntimeConfigurationMutation()
    }
  }

  private async setIpv6Enabled(enabled: boolean): Promise<void> {
    if (enabled === this.ipv6Enabled) return
    const plan: RuntimeReconfigurationPlan = this.runtimeReconfigurationPlan('切换 IPv6')
    if (plan === 'reject') return
    this.configurationBusy = true
    const nextSettings: NetworkSettings = this.currentNetworkSettings()
    nextSettings.ipv6Enabled = enabled
    try {
      await this.commitRuntimeReconfiguration('切换 IPv6', plan, this.storeState, nextSettings,
        false, true, nextSettings.ipv6Enabled ? 'IPv6 已开启并接管双栈' :
          'IPv6 已关闭，TUN 将接管并阻止 IPv6 泄漏')
    } finally {
      this.endRuntimeConfigurationMutation()
    }
  }

  private async loadApplicationCatalog(): Promise<void> {
    if (this.applicationCatalogLoading || this.applicationCatalogLoaded) return
    this.applicationCatalogLoading = true
    this.applicationMessage = this.t('正在读取可启动应用…', 'Loading launchable apps…')
    try {
      this.applicationCatalog = await this.applicationCatalogService.listLaunchableApplications()
      this.applicationCatalogLoaded = true
      this.applicationMessage = this.applicationCatalog.length > 0 ?
        this.t(`已读取 ${this.applicationCatalog.length} 个可启动应用`,
          `${this.applicationCatalog.length} launchable apps found`) :
        this.t('未读取到可启动应用，可手动填写包名',
          'No launchable apps found. Enter a bundle name manually.')
    } catch (_) {
      this.applicationCatalog = []
      this.applicationMessage = this.t('系统未返回应用列表，可手动填写包名',
        'The system did not return an app list. Enter a bundle name manually.')
    } finally {
      this.applicationCatalogLoading = false
    }
  }

  private visibleApplicationCatalog(): SelectableApplication[] {
    const query: string = this.applicationSearch.trim().toLowerCase()
    const matched: SelectableApplication[] = query.length === 0 ? this.applicationCatalog :
      this.applicationCatalog.filter((application: SelectableApplication) =>
        application.label.toLowerCase().includes(query) ||
        application.bundleName.toLowerCase().includes(query))
    return matched.slice(0, 40)
  }

  private applicationDisplayName(bundleName: string): string {
    const application: SelectableApplication | undefined = this.applicationCatalog.find(
      (candidate: SelectableApplication) => candidate.bundleName === bundleName)
    return application ? application.label : bundleName
  }

  private async openApplicationEditor(): Promise<void> {
    this.applicationEditorOpen = !this.applicationEditorOpen
    if (this.applicationEditorOpen) await this.loadApplicationCatalog()
  }

  private async setApplicationMode(mode: VpnApplicationMode): Promise<void> {
    if (mode === this.applicationMode) return
    if (mode === 'allowlist' && this.trustedApplications.length === 0) {
      this.applicationEditorOpen = true
      await this.loadApplicationCatalog()
      this.applicationMessage = this.t('请先至少选择一个应用，再启用“仅所选应用”',
        'Select at least one app before enabling Only selected apps.')
      this.showToast(this.applicationMessage)
      return
    }
    const plan: RuntimeReconfigurationPlan = this.runtimeReconfigurationPlan('切换应用接管范围')
    if (plan === 'reject') return
    this.configurationBusy = true
    const nextSettings: NetworkSettings = this.currentNetworkSettings()
    nextSettings.applicationMode = mode
    try {
      const changed: boolean = await this.commitRuntimeReconfiguration('切换应用接管范围', plan,
        this.storeState, nextSettings, false, true, mode === 'allowlist' ?
          `仅 ${nextSettings.trustedApplications.length} 个所选应用进入 VPN` :
          '全部应用进入 VPN')
      if (changed) {
        this.applicationMessage = mode === 'allowlist' ?
          this.t('未选择的应用将直接使用系统网络',
            'Apps not selected will use the system network directly.') :
          this.t('所有应用流量都会进入 TUN', 'All app traffic will enter TUN.')
      }
    } finally {
      this.endRuntimeConfigurationMutation()
    }
  }

  private async setApplicationSelected(bundleName: string, selected: boolean): Promise<void> {
    let validatedBundleName: string
    try {
      validatedBundleName = validateApplicationBundleName(bundleName)
    } catch (error) {
      const message: string = error instanceof Error ? error.message : '应用包名不正确'
      this.applicationMessage = this.effectiveLanguage === 'en' ?
        'The application bundle name is invalid.' : message
      this.showToast(this.applicationMessage)
      return
    }
    const currentlySelected: boolean = this.trustedApplications.includes(validatedBundleName)
    if (selected === currentlySelected) return
    let nextApplications: string[]
    try {
      nextApplications = normalizeTrustedApplications(selected ?
        this.trustedApplications.concat([validatedBundleName]) :
        this.trustedApplications.filter((candidate: string) => candidate !== validatedBundleName))
    } catch (error) {
      const message: string = error instanceof Error ? error.message : '应用白名单无法更新'
      this.applicationMessage = this.effectiveLanguage === 'en' ?
        `Only ${MAX_TRUSTED_APPLICATIONS} applications can be selected.` : message
      this.showToast(this.applicationMessage)
      return
    }
    if (this.applicationMode === 'allowlist' && nextApplications.length === 0) {
      this.applicationMessage = this.t('仅所选应用模式至少保留一个应用；请先切换到“全部应用”',
        'Keep at least one app selected, or switch to All apps first.')
      this.showToast(this.applicationMessage)
      return
    }
    const gatePlan: RuntimeReconfigurationPlan = this.runtimeReconfigurationPlan(
      selected ? '加入应用白名单' : '移出应用白名单')
    if (gatePlan === 'reject') return
    // Editing the prepared list while All apps is active does not affect the
    // current TUN. Persist it without interrupting a healthy VPN.
    const plan: RuntimeReconfigurationPlan = this.applicationMode === 'allowlist' ?
      gatePlan : 'persist-only'
    this.configurationBusy = true
    const nextSettings: NetworkSettings = this.currentNetworkSettings()
    nextSettings.trustedApplications = nextApplications
    try {
      const changed: boolean = await this.commitRuntimeReconfiguration(
        selected ? '加入应用白名单' : '移出应用白名单', plan,
        this.storeState, nextSettings, false, true,
        selected ? '应用已加入 VPN 白名单' : '应用已移出 VPN 白名单')
      if (changed) {
        this.applicationBundleDraft = ''
        this.applicationMessage = this.applicationMode === 'allowlist' ?
          this.t('应用接管范围已生效', 'Application scope is active.') :
          this.t('白名单已保存；切换到“仅所选应用”后生效',
            'Allowlist saved; it applies in Only selected apps mode.')
      }
    } finally {
      this.endRuntimeConfigurationMutation()
    }
  }

  private async addApplicationBundle(): Promise<void> {
    await this.setApplicationSelected(this.applicationBundleDraft, true)
  }

  private localRuleKindLabel(kind: string): string {
    if (kind === 'domain') return this.t('完整域名', 'Exact domain')
    if (kind === 'domain_suffix') return this.t('域名后缀', 'Domain suffix')
    return this.t('IP 网段', 'IP CIDR')
  }

  private localRuleTargetLabel(target: string): string {
    if (target === 'proxy') return this.t('代理', 'Proxy')
    if (target === 'direct') return this.t('直连', 'Direct')
    return this.t('拒绝', 'Reject')
  }

  private localRuleValidationMessage(message: string): string {
    if (this.effectiveLanguage !== 'en') return message
    if (message.includes('最多')) return `Local rules are limited to ${MAX_LOCAL_ROUTING_RULES}`
    if (message.includes('只能配置一次')) return 'A match condition can be configured only once.'
    if (message.includes('目标仅支持')) return 'Choose Proxy, Direct or Reject.'
    if (message.includes('仅支持完整域名')) return 'Only exact domain, domain suffix and IP CIDR rules are supported.'
    if (message.includes('请输入域名')) return 'Enter a domain.'
    if (message.includes('域名规则过长')) return 'The domain rule is too long.'
    if (message.includes('域名规则只能填写')) return 'Enter a domain only; URLs, paths and wildcards are not supported.'
    if (message.includes('域名格式')) return 'The domain format is invalid.'
    if (message.includes('请输入 CIDR')) return 'Enter an IP CIDR.'
    if (message.includes('必须包含有效前缀')) return 'CIDR must include a valid prefix length.'
    if (message.includes('前缀不能包含前导零')) return 'The CIDR prefix must not contain leading zeros.'
    if (message.includes('IPv4 CIDR')) return 'IPv4 CIDR prefix must be between 0 and 32.'
    if (message.includes('IPv6 CIDR')) return 'IPv6 CIDR prefix must be between 0 and 128.'
    if (message.includes('CIDR IP 地址') || message.includes('CIDR 网段格式')) return 'The IP CIDR format is invalid.'
    return 'Could not save the local rule.'
  }

  private async addLocalRule(): Promise<void> {
    const gatePlan: RuntimeReconfigurationPlan = this.runtimeReconfigurationPlan('新增本地规则')
    if (gatePlan === 'reject') return
    // Global and Direct do not consume local rules in the active runtime.
    // Persist without interrupting a healthy connection; Rule mode still uses
    // the acknowledged stop/save/reconnect transaction.
    const plan: RuntimeReconfigurationPlan = this.runMode === 'rule' ? gatePlan : 'persist-only'
    if (this.localRules.length >= MAX_LOCAL_ROUTING_RULES) {
      this.localRuleMessage = this.t(`本地规则最多 ${MAX_LOCAL_ROUTING_RULES} 条`,
        `Local rules are limited to ${MAX_LOCAL_ROUTING_RULES}`)
      this.showToast(this.localRuleMessage)
      return
    }
    this.configurationBusy = true
    try {
      const ruleKind: 'domain' | 'domain_suffix' | 'ip_cidr' =
        this.localRuleKind === 'domain_suffix' ? 'domain_suffix' :
          (this.localRuleKind === 'ip_cidr' ? 'ip_cidr' : 'domain')
      const rule: RoutingRule = validateLocalRoutingRule(ruleKind,
        this.localRuleDraft, this.localRuleTarget)
      const nextRules: RoutingRule[] = normalizeLocalRoutingRules(this.localRules.concat([rule]))
      const nextSettings: NetworkSettings = this.currentNetworkSettings()
      nextSettings.localRules = nextRules
      const changed: boolean = await this.commitRuntimeReconfiguration('新增本地规则', plan,
        this.storeState, nextSettings, false, true, this.runMode === 'rule' ?
          '本地规则已保存并应用' : '本地规则已保存；切换到规则模式后应用')
      if (changed) {
        this.localRuleDraft = ''
        this.localRuleMessage = this.runMode === 'rule' ?
          this.t('已优先于订阅规则应用', 'Applied before subscription rules') :
          this.t('已保存；切换到规则模式后应用', 'Saved; applies in Rule mode')
      }
    } catch (error) {
      const message: string = error instanceof Error ? error.message : '规则保存失败'
      this.localRuleMessage = this.localRuleValidationMessage(message)
      this.showToast(this.localRuleMessage)
    } finally {
      this.endRuntimeConfigurationMutation()
    }
  }

  private async removeLocalRule(index: number): Promise<void> {
    if (index < 0 || index >= this.localRules.length) return
    const gatePlan: RuntimeReconfigurationPlan = this.runtimeReconfigurationPlan('删除本地规则')
    if (gatePlan === 'reject') return
    const plan: RuntimeReconfigurationPlan = this.runMode === 'rule' ? gatePlan : 'persist-only'
    this.configurationBusy = true
    try {
      const nextSettings: NetworkSettings = this.currentNetworkSettings()
      nextSettings.localRules = this.localRules.filter((_rule: RoutingRule, ruleIndex: number) => ruleIndex !== index)
      const changed: boolean = await this.commitRuntimeReconfiguration('删除本地规则', plan,
        this.storeState, nextSettings, false, true, this.runMode === 'rule' ?
          '本地规则已删除' : '本地规则已删除；当前路由无需重连')
      if (changed) this.localRuleMessage = this.runMode === 'rule' ?
        this.t('删除已生效', 'Removal applied') :
        this.t('已删除；当前路由未重启', 'Removed without restarting the current route')
    } finally {
      this.endRuntimeConfigurationMutation()
    }
  }

  private async selectDnsPreset(presetId: DnsPresetId): Promise<void> {
    if (presetId === this.dnsPresetId) return
    const plan: RuntimeReconfigurationPlan = this.runtimeReconfigurationPlan('切换 DNS')
    if (plan === 'reject') return
    if (presetId === 'custom' && this.customDns.trim().length === 0) {
      // Opening the custom editor does not yet change the runtime. Keep the
      // current DNS active until a valid endpoint is saved transactionally.
      this.customDnsEditorOpen = true
      this.customDnsDraft = this.customDns
      this.dnsMessage = '请输入 HTTPS DoH 或 TLS DoT 地址并保存；当前连接仍使用原 DNS'
      return
    }
    this.configurationBusy = true
    const nextSettings: NetworkSettings = this.currentNetworkSettings()
    nextSettings.dnsPresetId = presetId
    try {
      if (presetId === 'custom') {
        validateDnsEndpoint(this.customDns)
      }
      const changed: boolean = await this.commitRuntimeReconfiguration('切换 DNS', plan,
        this.storeState, nextSettings, false, true, `已选择 ${findDnsPreset(presetId).name}`)
      if (changed) {
        this.customDnsEditorOpen = false
        this.dnsMessage = `运行 DNS：${findDnsPreset(presetId).name}`
      }
    } catch (error) {
      const message: string = error instanceof Error ? error.message : 'DNS 设置保存失败'
      this.showToast(`${message}，原设置未改变`)
    } finally {
      this.endRuntimeConfigurationMutation()
    }
  }

  private async saveCustomDns(): Promise<void> {
    const plan: RuntimeReconfigurationPlan = this.runtimeReconfigurationPlan('保存 DNS')
    if (plan === 'reject') return
    this.configurationBusy = true
    try {
      const validated: string = validateDnsEndpoint(this.customDnsDraft)
      const nextSettings: NetworkSettings = this.currentNetworkSettings()
      nextSettings.customDns = validated
      nextSettings.dnsPresetId = 'custom'
      const changed: boolean = await this.commitRuntimeReconfiguration('保存 DNS', plan,
        this.storeState, nextSettings, false, true, '自定义加密 DNS 已保存')
      if (changed) {
        this.customDnsEditorOpen = false
        this.dnsMessage = '自定义加密 DNS 已保存并应用'
      }
    } catch (error) {
      const message: string = error instanceof Error ? error.message : 'DNS 地址不正确'
      this.dnsMessage = message
      this.showToast(message)
    } finally {
      this.endRuntimeConfigurationMutation()
    }
  }

  private connectionTitle(): string {
    if (this.connectionPhase === 'connected') return this.t('已连接', 'Connected')
    if (this.connectionPhase === 'checking') return this.t('检查中', 'Checking')
    if (this.connectionPhase === 'authorizing') return this.t('等待授权', 'Awaiting permission')
    if (this.connectionPhase === 'starting') return this.t('正在连接', 'Connecting')
    if (this.connectionPhase === 'stopping') return this.t('正在断开', 'Disconnecting')
    if (this.connectionPhase === 'unknown') return this.t('状态未知', 'Status unknown')
    if (this.connectionPhase === 'error') return this.t('连接失败', 'Connection failed')
    return this.t('未连接', 'Disconnected')
  }

  private connectionColor(): string {
    if (this.connectionPhase === 'connected') return this.palette().accent
    if (this.connectionPhase === 'error') return this.palette().danger
    if (this.connectionPhase === 'checking' || this.connectionPhase === 'authorizing' || this.connectionPhase === 'starting' ||
      this.connectionPhase === 'stopping') return this.palette().warning
    if (this.connectionPhase === 'unknown') return this.palette().warning
    return this.palette().textPrimary
  }

  private isConnectionBusy(): boolean {
    return this.connectionPhase === 'checking' || this.connectionPhase === 'authorizing' || this.connectionPhase === 'starting' ||
      this.connectionPhase === 'stopping'
  }

  private runtimeConfigurationEditable(): boolean {
    if (this.localConfigJson.length > 0) return false
    return !this.localConfigLoading && !this.configurationBusy && !this.settingsLoading && !this.isLoadingStore &&
      !this.isConnectionBusy() && (this.connectionPhase === 'idle' || this.connectionPhase === 'connected')
  }

  private idleConfigurationEditable(): boolean {
    return !this.localConfigLoading && !this.configurationBusy && !this.settingsLoading && !this.isLoadingStore &&
      !this.isConnectionBusy() && this.connectionPhase === 'idle'
  }

  private canEditIdleConfiguration(action: string): boolean {
    if (this.idleConfigurationEditable()) return true
    if (this.configurationBusy) this.showToast(`请等待当前配置保存完成后再${action}`)
    else if (this.settingsLoading || this.isLoadingStore) this.showToast(`请等待本地配置恢复完成后再${action}`)
    else if (this.connectionPhase === 'connected') this.showToast(`请先断开 VPN 再${action}`)
    else if (this.isConnectionBusy()) this.showToast(`请等待当前 VPN 操作完成后再${action}`)
    else this.showToast(`请先重新检查 VPN 状态后再${action}`)
    return false
  }

  private beginIdleConfigurationMutation(action: string): boolean {
    if (!this.canEditIdleConfiguration(action)) return false
    this.configurationBusy = true
    return true
  }

  private runtimeReconfigurationPlan(action: string): RuntimeReconfigurationPlan {
    if (this.localConfigJson.length > 0 || this.localConfigLoading) {
      this.showToast('当前使用本地配置，请断开 VPN 后导入修改后的 JSON，或切回订阅')
      return 'reject'
    }
    const plan: RuntimeReconfigurationPlan = planRuntimeReconfiguration({
      configurationBusy: this.configurationBusy,
      settingsLoading: this.settingsLoading,
      subscriptionsLoading: this.isLoadingStore,
      connectionBusy: this.isConnectionBusy(),
      connectionPhase: this.connectionPhase
    })
    if (plan !== 'reject') return plan
    if (this.configurationBusy) {
      this.showToast(`请等待当前配置保存完成后再${action}`)
      return plan
    }
    if (this.settingsLoading || this.isLoadingStore) {
      this.showToast(`请等待本地配置恢复完成后再${action}`)
      return plan
    }
    if (this.isConnectionBusy()) {
      this.showToast(`请等待当前 VPN 操作完成后再${action}`)
      return plan
    }
    if (this.connectionPhase !== 'idle') {
      this.showToast(`请先重新检查 VPN 状态后再${action}`)
      return plan
    }
    return plan
  }

  private canEditRuntimeConfiguration(action: string): boolean {
    return this.runtimeReconfigurationPlan(action) !== 'reject'
  }

  private beginRuntimeConfigurationMutation(action: string): boolean {
    if (this.runtimeReconfigurationPlan(action) === 'reject') return false
    this.configurationBusy = true
    return true
  }

  private subscriptionMetadataEditable(): boolean {
    return !this.localConfigLoading && !this.configurationBusy && !this.settingsLoading && !this.isLoadingStore &&
      !this.isConnectionBusy() && (this.connectionPhase === 'idle' || this.connectionPhase === 'connected')
  }

  private beginSubscriptionMetadataMutation(): boolean {
    if (!this.subscriptionMetadataEditable()) {
      this.showToast('请等待当前 VPN 操作或本地保存完成')
      return false
    }
    this.configurationBusy = true
    return true
  }

  private endRuntimeConfigurationMutation(): void {
    this.configurationBusy = false
  }

  private connectionButtonLabel(): string {
    if (this.connectionPhase === 'connected') return this.t('断开 VPN', 'Disconnect VPN')
    if (this.connectionPhase === 'unknown' || this.connectionPhase === 'error') {
      return this.t('安全停止并重新检查', 'Safe stop and check')
    }
    if (this.configurationBusy) return this.t('正在保存配置…', 'Saving configuration…')
    if (this.connectionPhase === 'checking') return this.t('正在检查 VPN…', 'Checking VPN…')
    if (this.connectionPhase === 'authorizing') return this.t('等待系统授权…', 'Awaiting system permission…')
    if (this.connectionPhase === 'starting') return this.t('正在启动核心…', 'Starting core…')
    if (this.connectionPhase === 'stopping') return this.t('正在断开…', 'Disconnecting…')
    return this.t('连接 VPN', 'Connect VPN')
  }

  private connectionActionEnabled(): boolean {
    if (this.isConnectionBusy()) return false
    if (this.connectionPhase === 'connected' || this.connectionPhase === 'unknown' ||
      this.connectionPhase === 'error') return this.connectionCoordinator !== null
    return !this.localConfigLoading && !this.configurationBusy && !this.settingsLoading && !this.isLoadingStore
  }

  private connectionActionColor(): string {
    if (!this.connectionActionEnabled()) return this.palette().borderStrong
    return this.connectionPhase === 'connected' ? this.palette().warning : this.palette().accent
  }

  private tunSwitchEnabled(): boolean {
    if (this.connectionPhase !== 'idle' && this.connectionPhase !== 'connected') return false
    return this.connectionActionEnabled()
  }

  private formatBytes(value: number): string {
    if (value < 1024) return `${value} B`
    if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KiB`
    if (value < 1024 * 1024 * 1024) return `${(value / 1024 / 1024).toFixed(1)} MiB`
    return `${(value / 1024 / 1024 / 1024).toFixed(2)} GiB`
  }

  private invalidateRuntimeProbes(): void {
    this.runtimeProbeEpoch++
    this.isProxyTesting = false
    this.isProxyTestingAll = false
    this.proxyTestCompletedCount = 0
    this.proxyTestTotalCount = 0
    this.proxyTestingNodeIds = []
    this.isTestingWebsites = false
    this.isTestingEgress = false
    this.proxyLatencyText = '— ms'
    this.proxyNodeLatencies = []
    this.websiteTestResults = emptyWebsiteTestResults()
    this.egressInfo = emptyEgressInfo()
    this.revealEgressIp = false
  }

  private invalidateRuntimePathDiagnostics(): void {
    // A selector change invalidates results that describe the active egress
    // path, but per-node URLTest measurements still describe the candidate
    // nodes that were tested in this same running sing-box session. Keep those
    // measurements so latency sorting remains useful immediately after a hot
    // switch.
    this.runtimeProbeEpoch++
    this.isProxyTesting = false
    this.isProxyTestingAll = false
    this.proxyTestCompletedCount = 0
    this.proxyTestTotalCount = 0
    this.proxyTestingNodeIds = []
    this.isTestingWebsites = false
    this.isTestingEgress = false
    this.proxyLatencyText = '— ms'
    this.websiteTestResults = emptyWebsiteTestResults()
    this.egressInfo = emptyEgressInfo()
    this.revealEgressIp = false
  }

  private invalidateIdleProbes(): void {
    this.idleProbeEpoch++
    this.probingNodeIds = []
    this.isProbingAll = false
  }

  private isCurrentRuntimeProbe(token: number): boolean {
    return token === this.runtimeProbeEpoch && this.connectionPhase === 'connected'
  }

  private proxyRuntimeAvailable(): boolean {
    return this.connectionPhase === 'connected' && this.runMode !== 'direct'
  }

  private proxyTestBusy(): boolean {
    return this.isProxyTesting || this.isProxyTestingAll || this.proxyTestingNodeIds.length > 0
  }

  private batchNodeTestEnabled(): boolean {
    if (this.connectionPhase === 'idle') return !this.isProbingAll
    if (this.connectionPhase === 'connected') return this.runMode !== 'direct' && !this.proxyTestBusy()
    return false
  }

  private batchNodeTestLabel(): string {
    if (this.connectionPhase === 'connected') {
      if (this.runMode === 'direct') return this.t('直连不测速', 'Unavailable in Direct')
      if (this.isProxyTestingAll) {
        return this.t(`代理测速 ${this.proxyTestCompletedCount}/${this.proxyTestTotalCount}`,
          `Proxy test ${this.proxyTestCompletedCount}/${this.proxyTestTotalCount}`)
      }
      return this.t('批量代理测速', 'Test all proxies')
    }
    return this.isProbingAll ? this.t('TCP 测试中…', 'Testing TCP…') : this.t('批量 TCP', 'Test all TCP')
  }

  private runBatchNodeTests(): void {
    if (this.connectionPhase === 'connected') {
      this.runAllNodeProxyUrlTests()
      return
    }
    this.probeAllNodes()
  }

  private applyCoreStatus(status: CoreStatus): void {
    if (status.running && this.connectionPhase === 'idle') this.invalidateIdleProbes()
    if (this.runtimeWasRunning && !status.running) this.invalidateRuntimeProbes()
    const currentRuntimeTag: string = status.running ? status.selectedOutboundTag : ''
    if (status.running && this.runtimeSelectedOutboundTag.length > 0 && currentRuntimeTag.length > 0 &&
      this.runtimeSelectedOutboundTag !== currentRuntimeTag) {
      // Website and egress results describe one concrete outbound path. A
      // manual or automatic core switch invalidates both completed and in-flight
      // diagnostics from the previous node.
      this.invalidateRuntimePathDiagnostics()
    }
    this.runtimeSelectedOutboundTag = currentRuntimeTag
    this.runtimeWasRunning = status.running
    this.connectionPhase = status.running ? 'connected' : 'idle'
    this.connectionMessage = status.running ? '系统 VPN/TUN 正在接管设备流量' : '等待连接'
    this.uploadSpeed = status.running ? this.formatBytes(status.uploadBytes) : '暂未统计'
    this.downloadSpeed = status.running ? this.formatBytes(status.downloadBytes) : '暂未统计'
    this.activeConnections = status.running ? status.activeConnections : 0
    this.runtimeSelectedNodeName = ''
    if (status.running && status.selectedOutboundTag.length > 0) {
      const record: SubscriptionRecord | undefined = this.activeRecord()
      const runtimeNode: ProxyNode | undefined = record ?
        record.bundle.nodes.find((node: ProxyNode) => node.id === status.selectedOutboundTag) : undefined
      this.runtimeSelectedNodeName = runtimeNode ? runtimeNode.name : status.selectedOutboundTag
    }
    const now: number = Date.now()
    if (status.running && this.previousStatsAt > 0 && now > this.previousStatsAt &&
      status.uploadBytes >= this.previousUploadBytes && status.downloadBytes >= this.previousDownloadBytes) {
      const elapsed: number = now - this.previousStatsAt
      const uploadPerSecond: number = Math.floor((status.uploadBytes - this.previousUploadBytes) * 1000 / elapsed)
      const downloadPerSecond: number = Math.floor((status.downloadBytes - this.previousDownloadBytes) * 1000 / elapsed)
      this.uploadRate = `${this.formatBytes(uploadPerSecond)}/s`
      this.downloadRate = `${this.formatBytes(downloadPerSecond)}/s`
    } else {
      this.uploadRate = '0 B/s'
      this.downloadRate = '0 B/s'
    }
    if (status.running) {
      this.previousStatsAt = now
      this.previousUploadBytes = status.uploadBytes
      this.previousDownloadBytes = status.downloadBytes
    } else {
      this.previousStatsAt = 0
      this.previousUploadBytes = 0
      this.previousDownloadBytes = 0
      // Reachability and exit-IP results describe one concrete VPN session.
      // Never keep them on screen after disconnect, rollback or session loss.
      this.websiteTestResults = emptyWebsiteTestResults()
      this.egressInfo = emptyEgressInfo()
      this.revealEgressIp = false
    }
  }

  private async syncConnectionStatus(): Promise<void> {
    const expectedPhase: string = this.connectionPhase
    const coordinator: ConnectionCoordinator | null = this.connectionCoordinator
    if (!coordinator) {
      this.connectionPhase = 'unknown'
      this.connectionMessage = '连接服务尚未就绪'
      return
    }
    if (!this.coreInfo.available) {
      this.connectionPhase = 'error'
      this.connectionMessage = this.coreInfo.reason
      return
    }
    try {
      const status: CoreStatus = await coordinator.getStatus()
      if (this.connectionPhase !== expectedPhase) return
      this.applyCoreStatus(status)
      if (!status.running && status.lastError.length > 0) {
        this.connectionPhase = 'error'
        this.connectionMessage = status.lastError
      }
    } catch (_) {
      if (this.connectionPhase !== expectedPhase) return
      this.connectionPhase = 'unknown'
      this.connectionMessage = '核心状态暂不可读，不会解锁运行配置'
    }
  }

  private async persistAndApply(state: SubscriptionStoreState): Promise<void> {
    const repository: SubscriptionRepository | null = this.subscriptionRepository
    if (!repository) throw new Error('订阅存储尚未就绪')
    await repository.save(state)
    this.applyStoreState(state)
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: this.localizedRuntimeText(message) })
    } catch (_) {
      // A prompt failure must not change the subscription state.
    }
  }

  private privacyDetails(): string {
    return this.t(
      '本应用不要求账号，也不内置广告、分析 SDK 或自营遥测服务。订阅地址、订阅名称、节点与凭据在设备上解析；订阅目录、应用接管白名单和静态 sing-box 运行配置使用应用作用域 HUKS 密钥执行 AES-256-GCM 加密，并保存在应用私有目录。网络模式、IPv6、日志等级和 DNS 选择保存在本机。\n\n只有在你主动执行相应功能时才会联网：更新订阅会访问你填写的 HTTPS 订阅主机；连接时会访问所选 DoH/DoT 上游；网站诊断会访问界面列出的 Apple、GitHub、Google、YouTube、ChatGPT、Claude、Netflix、Disney+ 与 TikTok 端点；出口检测会访问 Cloudflare HTTPS trace。完整出口 IP 默认遮蔽，不写入订阅文件。\n\n权限用途：INTERNET 仅用于上述用户主动发起的订阅、VPN/DNS 与诊断联网；GET_NETWORK_INFO 仅用于读取当前网络承载类型，并在断开或升级恢复时确认系统中已不存在 BEARER_VPN；GET_BUNDLE_INFO 仅在你打开应用白名单管理时读取具有桌面入口的本机应用名称与包名，用于本地选择，不会上传。应用不会读取完整企业安装清单、Wi-Fi 密码、通讯录或位置。\n\n“清除本地敏感数据”会删除加密订阅目录、旧版订阅明文、应用接管白名单和静态运行配置，并把网络/DNS 设置恢复为默认值。它不会删除设备 HUKS 主密钥，也会保留外观与语言偏好。正式构建中的公开隐私政策 URL 和最终运营主体以本页“公开发布信息”区域为准；任一项缺失或无效时，发布门禁保持阻塞。',
      'This app requires no account and includes no ads, analytics SDKs or first-party telemetry service. Subscription URLs, names, nodes and credentials are parsed on device. The subscription catalog, application tunnel allowlist and static sing-box runtime configuration are encrypted with AES-256-GCM using an app-scoped HUKS key and stored in the private app sandbox. Network mode, IPv6, log level and DNS choices stay on device.\n\nNetwork access occurs only when you request a related feature: updating a subscription contacts the HTTPS host you entered; connecting contacts the selected DoH/DoT upstream; website diagnostics contact the listed Apple, GitHub, Google, YouTube, ChatGPT, Claude, Netflix, Disney+ and TikTok endpoints; egress checks contact Cloudflare HTTPS trace. The full egress IP is masked by default and is not written to subscription files.\n\nPermission purposes: INTERNET is used only for the user-initiated profile, VPN/DNS and diagnostics traffic described above. GET_NETWORK_INFO reads only current bearer types so disconnect and upgrade recovery can confirm that no BEARER_VPN remains. GET_BUNDLE_INFO is used only when you open allowlist management to read the names and bundle IDs of locally installed apps with Home entries; the list stays on device. The app does not read the full enterprise installation inventory, Wi-Fi passwords, contacts or location.\n\nClear local sensitive data removes the encrypted subscription catalog, legacy subscription plaintext, application tunnel allowlist and static runtime configuration, and resets network/DNS settings. It does not delete the device HUKS master key, and it keeps appearance and language preferences. The signed build public privacy-policy URL and final operator identity are shown under Public release information; release remains blocked when either value is missing or invalid.')
  }

  private licenseDetails(): string {
    return this.t(
      '本项目及分发物采用 GPL-3.0-or-later。代理核心 sing-box v1.14.2 采用 GPL-3.0-or-later，并包含可审计的 HarmonyOS/嵌入式适配补丁；SagerNet gVisor fork 采用 Apache-2.0；Go 与 OpenHarmony Go 端口保留 BSD 风格许可及专利声明。完整许可文本、第三方声明、精确版本锁和补丁保存在随源码分发的 LICENSE、THIRD_PARTY_NOTICES.md 与 third_party 目录。\n\n本应用不是华为、HarmonyOS 或 sing-box 项目的官方产品，也未获得这些项目的隶属关系或背书。原生 sing-box 核心只能随签名应用版本升级，不能从订阅下载后热替换。\n\n每个分发版本都必须提供与二进制精确对应、可长期公开访问的完整源码 URL，包括应用源码、sing-box、gVisor、OpenHarmony Go 工具链、补丁、依赖锁、构建脚本与重建说明。签名构建中的精确版本入口以本页“公开发布信息”区域为准；缺失或无效时发布门禁保持阻塞。',
      'This project and its distribution use GPL-3.0-or-later. The sing-box v1.14.2 proxy core is GPL-3.0-or-later and includes auditable HarmonyOS/embedded adaptation patches. The SagerNet gVisor fork is Apache-2.0. Go and the OpenHarmony Go port retain BSD-style license and patent notices. Complete license texts, third-party notices, exact version locks and patches are distributed in LICENSE, THIRD_PARTY_NOTICES.md and the third_party source tree.\n\nThis app is not an official Huawei, HarmonyOS or sing-box product and is not affiliated with or endorsed by them. The native sing-box core can be upgraded only in a signed app release; it cannot be hot-replaced from a subscription.\n\nEvery distributed version must provide a durable public URL for the exact corresponding source of every binary, including the app, sing-box, gVisor, OpenHarmony Go toolchain, patches, dependency locks, build scripts and rebuild instructions. The signed build exact-version entry is shown under Public release information; release remains blocked when it is missing or invalid.')
  }

  private userAgreementDetails(): string {
    return this.t(
      '一、产品性质\n本应用是独立开发的 HarmonyOS 网络工具，通过系统 VPN/TUN 和 sing-box 核心处理设备网络流量。本应用不是华为、HarmonyOS、sing-box 或任何订阅服务商的官方产品。\n\n二、用户责任\n你只能导入自己有权使用的 HTTPS 订阅，并应遵守所在地法律、网络服务条款和订阅服务商规则。不得利用本应用侵害他人权益、绕过依法实施的访问控制或从事违法活动。\n\n三、运行与风险\n代理节点、订阅规则、DNS、网络环境和第三方端点均可能变化。本应用不承诺任何节点、网站、地区内容、带宽或持续可用性。连接状态只在系统 VPN/TUN 与核心运行读回确认后显示；你可随时执行安全停止。\n\n四、数据与联网\n订阅与运行配置按“隐私与数据”页说明在本机处理和加密。导入/更新订阅、连接 VPN 和联网诊断仅在你同意本机隐私摘要后启用；撤回后进入离线受限模式。\n\n五、开源软件\n本应用采用 GPL-3.0-or-later，并包含 sing-box、gVisor 与 OpenHarmony Go 等开源组件。完整许可与第三方声明可在本应用内查看。原生核心仅随签名应用发布更新。\n\n六、发布信息\n最终运营主体、联系渠道、公开隐私政策、司法管辖与消费者条款以本页“公开发布信息”及公开用户协议为准；任一必填信息缺失或无效时，发布门禁保持阻塞。',
      '1. Product nature\nThis is an independently developed HarmonyOS network tool. It processes device traffic through system VPN/TUN and the sing-box core. It is not an official product of Huawei, HarmonyOS, sing-box or any subscription provider.\n\n2. User responsibility\nImport only HTTPS subscriptions you are authorized to use. You are responsible for complying with applicable law, network-service terms and provider rules. Do not use this app to infringe rights, evade lawfully applied access controls or conduct unlawful activity.\n\n3. Operation and risk\nProxy nodes, subscription rules, DNS, network conditions and third-party endpoints can change. The app does not promise node availability, website access, regional content, bandwidth or continuous service. Connected is shown only after system VPN/TUN and core runtime readback are confirmed. You can perform a safe stop at any time.\n\n4. Data and network access\nSubscriptions and runtime configuration are processed and encrypted on device as described under Privacy & data. Import/update, VPN connection and network diagnostics are enabled only after you accept the on-device privacy summary. Withdrawal activates offline limited mode.\n\n5. Open-source software\nThe app uses GPL-3.0-or-later and includes sing-box, gVisor, OpenHarmony Go and other open-source components. Complete licenses and notices are available in the app. The native core is updated only through a signed app release.\n\n6. Release information\nThe final operator identity, contact channel, public privacy policy, jurisdiction and consumer terms are governed by Public release information and the published user agreement. Release preflight remains blocked while any required value is missing or invalid.')
  }

  private confirmClearSensitiveData(): void {
    if (this.connectionPhase !== 'idle' || this.isConnectionBusy() || this.configurationBusy) {
      this.showToast('只有在 VPN 已确认断开时才能清除本地敏感数据')
      return
    }
    try {
      this.getUIContext().getPromptAction().showDialog({
        title: this.t('清除本地敏感数据', 'Clear local sensitive data'),
        message: this.t('将删除订阅、节点凭据、旧版明文和静态运行配置，并恢复网络/DNS 默认值。外观与语言偏好会保留。继续查看最终确认？',
          'This removes subscriptions, node credentials, legacy plaintext and static runtime configuration, and restores network/DNS defaults. Appearance and language preferences are kept. Continue to final confirmation?'),
        buttons: [
          { text: this.t('取消', 'Cancel'), color: this.palette().textSecondary },
          { text: this.t('继续', 'Continue'), color: this.palette().warning }
        ]
      }).then((result) => {
        if (result.index === 1) this.confirmClearSensitiveDataFinal()
      }).catch(() => this.showToast('清除确认窗口打开失败'))
    } catch (_) {
      this.showToast('清除确认窗口打开失败')
    }
  }

  private confirmClearSensitiveDataFinal(): void {
    if (this.connectionPhase !== 'idle' || this.isConnectionBusy() || this.configurationBusy) {
      this.showToast('只有在 VPN 已确认断开时才能清除本地敏感数据')
      return
    }
    try {
      this.getUIContext().getPromptAction().showDialog({
        title: this.t('最终确认', 'Final confirmation'),
        message: this.t('此操作不可撤销。确认永久清除本机的订阅与代理凭据？',
          'This cannot be undone. Permanently clear subscriptions and proxy credentials from this device?'),
        buttons: [
          { text: this.t('保留数据', 'Keep data'), color: this.palette().textSecondary },
          { text: this.t('永久清除', 'Clear permanently'), color: this.palette().danger }
        ]
      }).then((result) => {
        if (result.index === 1) this.clearSensitiveData()
      }).catch(() => this.showToast('清除确认窗口打开失败'))
    } catch (_) {
      this.showToast('清除确认窗口打开失败')
    }
  }

  private async clearSensitiveData(): Promise<void> {
    if (this.clearingSensitiveData) return
    const coordinator: ConnectionCoordinator | null = this.connectionCoordinator
    const subscriptionRepository: SubscriptionRepository | null = this.subscriptionRepository
    const settingsRepository: NetworkSettingsRepository | null = this.settingsRepository
    if (!coordinator || !subscriptionRepository || !settingsRepository) {
      this.showToast('清除服务尚未就绪，请稍后重试')
      return
    }
    this.clearingSensitiveData = true
    this.configurationBusy = true
    let allCleared: boolean = true
    try {
      // UI state is not authoritative. Re-read the cross-process runtime and
      // proceed only when the coordinator proves that no live/error session or
      // TUN remains. configurationBusy prevents a concurrent connect attempt.
      const status: CoreStatus = await coordinator.getStatus()
      if (this.connectionPhase !== 'idle' || status.running || status.lastError.length > 0) {
        this.showToast('只有在 VPN 已确认断开时才能清除本地敏感数据')
        return
      }
      const context: common.UIAbilityContext = this.applicationContext()
      const runtimeStore: VpnRuntimeConfigStore = new VpnRuntimeConfigStore(context.filesDir)
      const defaults: NetworkSettings = defaultNetworkSettings()
      try {
        // Absence is the canonical default state. Delete encrypted, candidate,
        // backup and legacy settings rather than writing a new static file.
        await settingsRepository.clear()
      } catch (_) {
        allCleared = false
      }
      try {
        await runtimeStore.clear()
        await new LocalConfigStore(context.filesDir).clear()
        this.localConfigJson = ''
        this.localConfigDraft = ''
      } catch (_) {
        allCleared = false
      }
      try {
        await subscriptionRepository.clear()
      } catch (_) {
        allCleared = false
      }
      if (!allCleared) {
        await this.restoreSubscriptions()
        await this.restoreSettingsAndRuntime()
        this.showToast('清除未全部完成；已重新读取设备上的实际数据')
        return
      }
      this.applyStoreState(emptySubscriptionStore())
      this.applyNetworkSettings(defaults)
      this.nodeLatencies = []
      this.proxyNodeLatencies = []
      this.probingNodeIds = []
      this.proxyTestingNodeIds = []
      this.websiteTestResults = emptyWebsiteTestResults()
      this.egressInfo = emptyEgressInfo()
      this.revealEgressIp = false
      this.importMessage = '本地敏感数据已清除；外观与语言偏好已保留'
      this.dnsMessage = '默认使用加密 DNS；所有 DNS 请求由 TUN 交给 sing-box 处理'
      this.showToast(this.importMessage)
    } catch (_) {
      await this.restoreSubscriptions()
      await this.restoreSettingsAndRuntime()
      this.showToast('清除未全部完成；已重新读取设备上的实际数据')
    } finally {
      this.configurationBusy = false
      this.clearingSensitiveData = false
    }
  }

  private showCoreUnavailableDialog(): void {
    try {
      this.getUIContext().getPromptAction().showDialog({
        title: this.t('核心尚未通过真机验收', 'Core is not device-verified'),
        message: this.t(`${this.coreInfo.reason}\n\n为了避免创建 TUN 后导致整机断网，当前按钮不会伪造“已连接”状态。`,
          `${this.localizedRuntimeText(this.coreInfo.reason)}\n\nTo prevent a broken device network after TUN creation, the app will not report a fake Connected state.`),
        buttons: [
          { text: this.t('我知道了', 'Got it'), color: this.palette().accent }
        ]
      }).catch(() => {
        // The safety lock remains active even if the dialog cannot be shown.
      })
    } catch (_) {
      // The safety lock remains active even if the dialog cannot be created.
    }
  }


  private async importLocalFile(): Promise<void> {
    if (!this.canEditIdleConfiguration('导入本地配置')) return
    if (!this.networkConsentGranted()) return
    this.localConfigLoading = true
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const paths = await new picker.DocumentViewPicker(context).select({ maxSelectNumber: 1 })
      if (paths.length === 0) return
      const text: string = await readLocalDocument(paths[0])
      await this.saveLocalConfig(text)
    } catch (error) {
      this.localConfigMessage = error instanceof Error ? error.message : '本地文件导入失败'
      this.showToast(this.localConfigMessage)
    } finally { this.localConfigLoading = false }
  }

  private async importLocalText(): Promise<void> {
    if (!this.canEditIdleConfiguration('保存本地配置') || !this.networkConsentGranted()) return
    this.localConfigLoading = true
    try { await this.saveLocalConfig(this.localConfigDraft) }
    catch (error) {
      this.localConfigMessage = error instanceof Error ? error.message : '配置保存失败'
      this.showToast(this.localConfigMessage)
    } finally { this.localConfigLoading = false }
  }

  private async saveLocalConfig(text: string): Promise<void> {
    const prepared: string = prepareLocalConfig(text)
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    await new LocalConfigStore(context.filesDir).save(prepared)
    this.localConfigJson = prepared
    this.localConfigDraft = ''
    this.localConfigMessage = '结构检查通过并已加密保存；开启 VPN 时由内核完整校验'
    this.showToast(this.localConfigMessage)
  }

  private async useSubscriptionConfig(): Promise<void> {
    if (!this.canEditIdleConfiguration('切回订阅')) return
    this.localConfigLoading = true
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await new LocalConfigStore(context.filesDir).clear()
      this.localConfigJson = ''
      this.localConfigMessage = '已切回订阅配置；再次使用本地配置时请重新导入'
    } catch (_) { this.showToast('切换失败，保留本地配置') }
    finally { this.localConfigLoading = false }
  }

  private async connectLocalConfig(coordinator: ConnectionCoordinator): Promise<void> {
    this.invalidateIdleProbes()
    this.invalidateRuntimeProbes()
    this.connectionPhase = 'authorizing'
    this.connectionMessage = '正在使用本地配置请求系统 VPN…'
    try {
      const status = await coordinator.connect(this.localConfigJson, vpnApplicationScope(this.currentNetworkSettings()))
      this.applyCoreStatus(status)
      this.showToast('本地配置 VPN/TUN 已连接')
    } catch (error) {
      const message: string = error instanceof Error ? error.message : '本地配置启动失败'
      this.connectionPhase = isConfirmedNoTunStartupError(message) ? 'idle' : 'unknown'
      this.connectionMessage = message
      this.showToast(message)
    }
  }

  private async importSubscription(): Promise<void> {
    if (this.isImporting) return
    if (!this.networkConsentGranted()) return
    if (!this.beginIdleConfigurationMutation('导入订阅')) return
    const sourceUrl: string = this.subscriptionUrl.trim()
    this.isImporting = true
    this.importMessage = '正在下载并解析订阅…'
    try {
      const bundle: SubscriptionBundle = await this.subscriptionService.downloadAndParse(sourceUrl)
      const next: SubscriptionStoreState = upsertSubscription(
        this.storeState,
        sourceUrl,
        bundle,
        Date.now(),
        this.newSubscriptionName
      )
      await this.persistAndApply(next)
      this.nodeLatencies = []
      this.proxyNodeLatencies = []
      this.latencyText = '— ms'
      this.proxyLatencyText = '— ms'
      this.subscriptionUrl = ''
      this.newSubscriptionName = ''
      this.importMessage = `已保存 ${next.records.length} 个订阅；当前订阅含 ${bundle.nodes.length} 个节点`
      this.showToast('订阅已保存，节点列表已更新')
    } catch (error) {
      const message: string = error instanceof Error ? error.message : '订阅解析失败'
      this.importMessage = message
      this.showToast(message)
    } finally {
      this.isImporting = false
      this.endRuntimeConfigurationMutation()
    }
  }

  private async refreshSubscription(record: SubscriptionRecord): Promise<void> {
    if (this.isImporting) return
    if (!this.networkConsentGranted()) return
    if (!this.beginIdleConfigurationMutation('更新订阅')) return
    this.isImporting = true
    this.importMessage = `正在更新 ${subscriptionDisplayName(record)}…`
    try {
      const bundle: SubscriptionBundle = await this.subscriptionService.downloadAndParse(record.sourceUrl)
      const next: SubscriptionStoreState = upsertSubscription(
        this.storeState,
        record.sourceUrl,
        bundle,
        Date.now()
      )
      await this.persistAndApply(next)
      this.nodeLatencies = []
      this.proxyNodeLatencies = []
      this.latencyText = '— ms'
      this.proxyLatencyText = '— ms'
      this.importMessage = `更新完成：${bundle.nodes.length} 个节点、${bundle.rules.length} 条规则`
      this.showToast('订阅更新成功')
    } catch (error) {
      const message: string = error instanceof Error ? error.message : '订阅更新失败'
      this.importMessage = `${message}；已保留上次可用配置`
      this.showToast(this.importMessage)
    } finally {
      this.isImporting = false
      this.endRuntimeConfigurationMutation()
    }
  }

  private async activateSubscription(subscriptionId: string): Promise<void> {
    if (subscriptionId === this.storeState.activeSubscriptionId) return
    const plan: RuntimeReconfigurationPlan = this.runtimeReconfigurationPlan('切换订阅')
    if (plan === 'reject') return
    this.configurationBusy = true
    const nextState: SubscriptionStoreState = setActiveSubscription(this.storeState, subscriptionId)
    try {
      const nextRecord: SubscriptionRecord | undefined = activeSubscription(nextState)
      const changed: boolean = await this.commitRuntimeReconfiguration('切换订阅', plan, nextState,
        this.currentNetworkSettings(), true, false,
        `已切换到 ${nextRecord ? subscriptionDisplayName(nextRecord) : '新订阅'}`)
      if (changed) {
        this.nodeLatencies = []
        this.proxyNodeLatencies = []
        this.proxyLatencyText = '— ms'
      }
    } finally {
      this.endRuntimeConfigurationMutation()
    }
  }

  private beginRenameSubscription(record: SubscriptionRecord): void {
    if (!this.subscriptionMetadataEditable()) {
      this.showToast('请等待当前 VPN 操作完成后再重命名订阅')
      return
    }
    this.renamingSubscriptionId = record.id
    this.renameSubscriptionDraft = record.customName
  }

  private async saveSubscriptionRename(record: SubscriptionRecord): Promise<void> {
    if (!this.beginSubscriptionMetadataMutation()) return
    try {
      await this.persistAndApply(renameSubscription(this.storeState, record.id, this.renameSubscriptionDraft))
      this.renamingSubscriptionId = ''
      this.renameSubscriptionDraft = ''
      this.showToast('订阅名称已保存')
    } catch (_) {
      this.showToast('订阅名称保存失败')
    } finally {
      this.endRuntimeConfigurationMutation()
    }
  }

  private async chooseNode(subscriptionId: string, nodeId: string): Promise<void> {
    if (this.connectionPhase === 'connected') {
      if (this.configurationBusy || this.isConnectionBusy()) return
      const record: SubscriptionRecord | undefined = this.activeRecord()
      if (!record || record.id !== subscriptionId) {
        this.showToast('运行中只能切换当前订阅的节点')
        return
      }
      if (this.runMode === 'direct') {
        this.configurationBusy = true
        try {
          await this.persistAndApply(selectSubscriptionNode(this.storeState, subscriptionId, nodeId))
          this.showToast('当前为直连模式，不经过代理；已保存为下次代理连接的首选节点')
        } catch (_) {
          this.showToast('下次代理连接的首选节点保存失败')
        } finally {
          this.configurationBusy = false
        }
        return
      }
      if (this.nodeSelectionMode !== 'manual') {
        this.showToast(this.nodeSelectionMode === 'auto' ?
          '自动优选由 URLTest 决定，运行中不能手动指定节点；请先切换为手动模式' :
          '故障转移由核心健康检查决定，运行中不能手动指定节点；请先切换为手动模式')
        return
      }
      const coordinator: ConnectionCoordinator | null = this.connectionCoordinator
      if (!coordinator) {
        this.showToast('VPN 运行协调器尚未就绪')
        return
      }
      const runtimeToken: number = this.runtimeProbeEpoch
      this.configurationBusy = true
      try {
        const status: CoreStatus = await coordinator.selectOutbound(nodeId)
        if (runtimeToken !== this.runtimeProbeEpoch) return
        if (!status.running || status.selectedOutboundTag !== nodeId) {
          throw new Error('核心未确认新的运行节点')
        }
        // Native readback is authoritative for the current session. Reflect it
        // immediately; local persistence only controls the next connection.
        this.applyCoreStatus(status)
        this.proxyLatencyText = '— ms'
        try {
          await this.persistAndApply(selectSubscriptionNode(this.storeState, subscriptionId, nodeId))
          this.showToast('运行节点已切换')
        } catch (_) {
          this.showToast('本次运行节点已切换，但首选节点保存失败；下次连接可能恢复旧选择')
        }
      } catch (error) {
        if (runtimeToken !== this.runtimeProbeEpoch) return
        const message: string = error instanceof Error ? error.message : '运行节点切换失败'
        this.showToast(message)
        if (this.connectionPhase === 'connected') await this.syncConnectionStatus()
      } finally {
        this.configurationBusy = false
      }
      return
    }
    if (!this.beginRuntimeConfigurationMutation('切换节点')) return
    try {
      await this.persistAndApply(selectSubscriptionNode(this.storeState, subscriptionId, nodeId))
      this.latencyText = this.latencyLabel(nodeId)
      this.proxyLatencyText = '— ms'
      this.showToast(this.nodeSelectionMode === 'manual' ? '手动节点已切换' :
        (this.nodeSelectionMode === 'auto' ? '已设置自动优选的偏好节点' : '已设置故障转移首选节点'))
    } catch (_) {
      this.showToast('节点选择保存失败')
    } finally {
      this.endRuntimeConfigurationMutation()
    }
  }

  private nodeSelectionInteractive(): boolean {
    if (this.connectionPhase === 'connected') {
      return !this.configurationBusy && !this.isConnectionBusy() && !this.isProxyTesting &&
        (this.runMode === 'direct' || this.nodeSelectionMode === 'manual')
    }
    return this.runtimeConfigurationEditable()
  }

  private confirmRemoveSubscription(record: SubscriptionRecord): void {
    if (!this.canEditIdleConfiguration('删除订阅')) return
    this.getUIContext().getPromptAction().showDialog({
      title: this.t('删除订阅', 'Remove subscription'),
      message: this.t(`确认删除“${subscriptionDisplayName(record)}”及其本地节点配置？`,
        `Remove “${subscriptionDisplayName(record)}” and its local node configuration?`),
      buttons: [
        { text: this.t('取消', 'Cancel'), color: this.palette().textSecondary },
        { text: this.t('删除', 'Remove'), color: this.palette().danger }
      ]
    }).then((result) => {
      if (result.index === 1) this.removeSubscriptionRecord(record.id)
    }).catch(() => {
      this.showToast('删除确认窗口打开失败')
    })
  }

  private async removeSubscriptionRecord(subscriptionId: string): Promise<void> {
    if (!this.beginIdleConfigurationMutation('删除订阅')) return
    try {
      const next: SubscriptionStoreState = removeSubscription(this.storeState, subscriptionId)
      await this.persistAndApply(next)
      this.nodeLatencies = []
      this.proxyNodeLatencies = []
      this.proxyLatencyText = '— ms'
      this.importMessage = `已删除订阅，当前共 ${next.records.length} 个`
      this.showToast('订阅已删除')
    } catch (_) {
      this.showToast('删除失败，原订阅仍保留')
    } finally {
      this.endRuntimeConfigurationMutation()
    }
  }

  private sourceHost(sourceUrl: string): string {
    const withoutScheme: string = sourceUrl.startsWith('https://') ? sourceUrl.slice(8) : sourceUrl
    const slash: number = withoutScheme.indexOf('/')
    const query: number = withoutScheme.indexOf('?')
    const fragment: number = withoutScheme.indexOf('#')
    let end: number = withoutScheme.length
    if (slash >= 0 && slash < end) end = slash
    if (query >= 0 && query < end) end = query
    if (fragment >= 0 && fragment < end) end = fragment
    const authority: string = withoutScheme.slice(0, end)
    const userInfo: number = authority.lastIndexOf('@')
    return userInfo >= 0 ? authority.slice(userInfo + 1) : authority
  }

  private latencyLabel(nodeId: string): string {
    const latency: NodeLatency | undefined = this.nodeLatencies.find((item: NodeLatency) => item.nodeId === nodeId)
    if (!latency) return '— ms'
    return latency.milliseconds < 0 ? this.t('超时', 'Timeout') : `${latency.milliseconds} ms`
  }

  private isProbing(nodeId: string): boolean {
    return this.probingNodeIds.includes(nodeId)
  }

  private isProxyTestingNode(nodeId: string): boolean {
    return this.proxyTestingNodeIds.includes(nodeId)
  }

  private proxyNodeLatencyLabel(nodeId: string): string {
    const latency: NodeLatency | undefined = this.proxyNodeLatencies.find((item: NodeLatency) => item.nodeId === nodeId)
    if (!latency) return '— ms'
    return latency.milliseconds < 0 ? '-1 ms' : `${latency.milliseconds} ms`
  }

  private nodeLatencyResult(nodeId: string): number | undefined {
    const results: NodeLatency[] = this.connectionPhase === 'connected' ?
      this.proxyNodeLatencies : this.nodeLatencies
    const result: NodeLatency | undefined = results.find((item: NodeLatency) => item.nodeId === nodeId)
    return result ? result.milliseconds : undefined
  }

  private nodeLatencyQuality(nodeId: string): NodeLatencyQuality {
    return classifyNodeLatency(this.nodeLatencyResult(nodeId))
  }

  private nodeLatencyForeground(nodeId: string): string {
    const quality: NodeLatencyQuality = this.nodeLatencyQuality(nodeId)
    if (quality === 'fast') return this.palette().accent
    if (quality === 'normal') return this.palette().blue
    if (quality === 'slow') return this.palette().warning
    if (quality === 'very_slow' || quality === 'failed') return this.palette().danger
    return this.palette().textSecondary
  }

  private nodeLatencyBackground(nodeId: string): string {
    const quality: NodeLatencyQuality = this.nodeLatencyQuality(nodeId)
    if (quality === 'fast') return this.palette().accentSoft
    if (quality === 'normal') return this.palette().blueSoft
    if (quality === 'slow') return this.palette().warningSoft
    if (quality === 'very_slow' || quality === 'failed') return this.palette().dangerSoft
    return this.palette().surfaceElevated
  }

  private nodeTestActionLabel(nodeId: string): string {
    if (this.connectionPhase === 'connected') {
      if (this.runMode === 'direct') return this.t('直连', 'Direct')
      if (this.isProxyTestingNode(nodeId)) return this.t('测速中', 'Testing')
      const proxyLatency: NodeLatency | undefined = this.proxyNodeLatencies.find(
        (item: NodeLatency) => item.nodeId === nodeId)
      if (!proxyLatency) return this.t('测速', 'Test')
      return proxyLatency.milliseconds < 0 ? this.t('失败', 'Failed') : `${proxyLatency.milliseconds}ms`
    }
    if (this.isProbing(nodeId)) return this.t('测速中', 'Testing')
    const tcpLatency: NodeLatency | undefined = this.nodeLatencies.find((item: NodeLatency) => item.nodeId === nodeId)
    if (!tcpLatency) return this.t('测速', 'Test')
    return tcpLatency.milliseconds < 0 ? this.t('超时', 'Timeout') : `${tcpLatency.milliseconds}ms`
  }

  private nodeTestActionDescription(nodeId: string): string {
    if (this.connectionPhase === 'connected') {
      if (this.runMode === 'direct') {
        return this.t('直连模式不经过代理节点，无法执行代理测速',
          'Direct mode does not use a proxy node, so proxy testing is unavailable.')
      }
      return this.t(`通过当前 VPN 运行时测试此节点，结果 ${this.nodeTestActionLabel(nodeId)}`,
        `Test this node through the active VPN runtime. Result: ${this.nodeTestActionLabel(nodeId)}.`)
    }
    return this.t(`测试此节点服务器的 TCP 可达性，结果 ${this.latencyLabel(nodeId)}`,
      `Test this node server's TCP reachability. Result: ${this.latencyLabel(nodeId)}.`)
  }

  private setProxyNodeLatency(nodeId: string, milliseconds: number): void {
    const kept: NodeLatency[] = this.proxyNodeLatencies.filter((item: NodeLatency) => item.nodeId !== nodeId)
    kept.push({ nodeId: nodeId, milliseconds: milliseconds })
    this.proxyNodeLatencies = kept
  }

  private setLatency(nodeId: string, milliseconds: number): void {
    const kept: NodeLatency[] = this.nodeLatencies.filter((item: NodeLatency) => item.nodeId !== nodeId)
    kept.push({ nodeId: nodeId, milliseconds: milliseconds })
    this.nodeLatencies = kept
    const record: SubscriptionRecord | undefined = this.activeRecord()
    if (record && record.selectedNodeId === nodeId) this.latencyText = this.latencyLabel(nodeId)
  }

  private async probeNode(node: ProxyNode): Promise<void> {
    if (!this.networkConsentGranted()) return
    // This socket is created by the UI process. Only the VPN Extension process
    // is protected from its own TUN, so probing while connected would measure
    // an ambiguous path through the VPN rather than a direct server reachability
    // check. Keep the diagnostic honest and only allow it while fully idle.
    if (this.connectionPhase !== 'idle') {
      this.showToast('请先断开 VPN，再进行服务器 TCP 可达性测试')
      return
    }
    if (this.isProbing(node.id)) return
    const token: number = this.idleProbeEpoch
    this.probingNodeIds = this.probingNodeIds.concat([node.id])
    try {
      const latency: number = await this.nodeProbeService.measureTcpLatency(node)
      if (token !== this.idleProbeEpoch || this.connectionPhase !== 'idle') return
      this.setLatency(node.id, latency)
    } finally {
      if (token === this.idleProbeEpoch) {
        this.probingNodeIds = this.probingNodeIds.filter((nodeId: string) => nodeId !== node.id)
      }
    }
  }

  private async probeAllNodes(): Promise<void> {
    if (this.isProbingAll) return
    if (!this.networkConsentGranted()) return
    if (this.connectionPhase !== 'idle') {
      this.showToast('请先断开 VPN，再进行服务器 TCP 可达性测试')
      return
    }
    const record: SubscriptionRecord | undefined = this.activeRecord()
    const nodes: ProxyNode[] = record ? record.bundle.nodes : []
    if (nodes.length === 0) {
      this.showToast('请先添加并选择订阅')
      return
    }

    const token: number = this.idleProbeEpoch
    this.isProbingAll = true
    this.nodeLatencies = []
    try {
      for (let start: number = 0; start < nodes.length; start += 5) {
        const tasks: Promise<void>[] = []
        const end: number = Math.min(nodes.length, start + 5)
        for (let index: number = start; index < end; index++) {
          tasks.push(this.probeNode(nodes[index]))
        }
        await Promise.all(tasks)
        if (token !== this.idleProbeEpoch || this.connectionPhase !== 'idle') return
      }
      if (token === this.idleProbeEpoch && this.connectionPhase === 'idle') {
        this.showToast('服务器 TCP 可达性测试完成')
      }
    } finally {
      if (token === this.idleProbeEpoch) this.isProbingAll = false
    }
  }

  private async runSelectedProxyUrlTest(): Promise<void> {
    if (this.proxyTestBusy()) return
    if (!this.networkConsentGranted()) return
    if (this.connectionPhase !== 'connected') {
      this.showToast('代理 URLTest 需要先连接 VPN；未连接时可使用 TCP 延迟测试')
      return
    }
    if (this.runMode === 'direct') {
      this.showToast('当前为直连模式，流量不经过代理，代理组 URLTest 不适用')
      return
    }
    const coordinator: ConnectionCoordinator | null = this.connectionCoordinator
    const record: SubscriptionRecord | undefined = this.activeRecord()
    if (!coordinator || !record || record.selectedNodeId.length === 0) {
      this.showToast('请先选择一个节点')
      return
    }
    const token: number = this.runtimeProbeEpoch
    this.isProxyTesting = true
    this.proxyLatencyText = '测试中…'
    try {
      // Test the runtime proxy group rather than a guessed node. In automatic
      // and failover modes this follows the outbound actually chosen by the
      // sing-box URLTest group inside the protected Extension process.
      const milliseconds: number = await coordinator.urlTest('proxy')
      if (!this.isCurrentRuntimeProbe(token)) return
      this.proxyLatencyText = milliseconds >= 0 ? `${milliseconds} ms` : '失败'
      this.showToast(milliseconds >= 0 ? '代理 URLTest 完成' : '代理 URLTest 失败')
    } catch (error) {
      if (!this.isCurrentRuntimeProbe(token)) return
      const message: string = error instanceof Error ? error.message : '代理 URLTest 失败'
      this.proxyLatencyText = '失败'
      this.showToast(message)
    } finally {
      if (token === this.runtimeProbeEpoch) {
        this.isProxyTesting = false
        if (this.proxyLatencyText === '测试中…') this.proxyLatencyText = '— ms'
        // A concurrent disconnect owns the stopping transition. Never let a
        // finishing URLTest read an older heartbeat and overwrite stopping with
        // connected/idle while the TUN cleanup acknowledgement is pending.
        if (this.connectionPhase === 'connected') await this.syncConnectionStatus()
      }
    }
  }

  private async runNodeProxyUrlTest(node: ProxyNode): Promise<void> {
    if (!this.networkConsentGranted()) return
    if (this.connectionPhase !== 'connected') {
      this.showToast('节点代理测速需要先连接 VPN')
      return
    }
    if (this.runMode === 'direct') {
      this.showToast('当前为直连模式，流量不经过代理，节点代理测速不适用')
      return
    }
    if (this.proxyTestBusy()) return
    const coordinator: ConnectionCoordinator | null = this.connectionCoordinator
    if (!coordinator) {
      this.showToast('VPN 运行协调器尚未就绪')
      return
    }
    const token: number = this.runtimeProbeEpoch
    this.proxyTestingNodeIds = this.proxyTestingNodeIds.concat([node.id])
    try {
      const milliseconds: number = await coordinator.urlTest(node.id)
      if (!this.isCurrentRuntimeProbe(token)) return
      this.setProxyNodeLatency(node.id, milliseconds)
      this.showToast(milliseconds >= 0 ? `${node.name} 代理测速完成` : `${node.name} 代理测速失败`)
    } catch (error) {
      if (!this.isCurrentRuntimeProbe(token)) return
      const message: string = error instanceof Error ? error.message : '节点代理测速失败'
      this.setProxyNodeLatency(node.id, -1)
      this.showToast(message)
    } finally {
      if (token === this.runtimeProbeEpoch) {
        this.proxyTestingNodeIds = this.proxyTestingNodeIds.filter((nodeId: string) => nodeId !== node.id)
        if (this.connectionPhase === 'connected') await this.syncConnectionStatus()
      }
    }
  }

  private async runAllNodeProxyUrlTests(): Promise<void> {
    if (this.proxyTestBusy()) return
    if (!this.networkConsentGranted()) return
    if (this.connectionPhase !== 'connected') {
      this.showToast('批量代理测速需要先连接 VPN')
      return
    }
    if (this.runMode === 'direct') {
      this.showToast('当前为直连模式，流量不经过代理，批量代理测速不适用')
      return
    }
    const coordinator: ConnectionCoordinator | null = this.connectionCoordinator
    const record: SubscriptionRecord | undefined = this.activeRecord()
    if (!coordinator || !record || record.bundle.nodes.length === 0) {
      this.showToast('请先添加并选择订阅')
      return
    }

    // Runtime commands share one bridge file and sing-box URLTest itself is
    // asynchronous. Keep this batch strictly serial: every result belongs to
    // one concrete node tag and no command can overwrite another. The runtime
    // epoch plus subscription id are the session gate; an explicit disconnect
    // invalidates them synchronously and therefore prevents both later
    // submissions and stale result writes.
    const token: number = this.runtimeProbeEpoch
    const subscriptionId: string = record.id
    const nodes: ProxyNode[] = record.bundle.nodes.slice()
    this.isProxyTestingAll = true
    this.proxyTestCompletedCount = 0
    this.proxyTestTotalCount = nodes.length
    this.proxyNodeLatencies = []
    try {
      for (let index: number = 0; index < nodes.length; index++) {
        if (!this.isCurrentRuntimeProbe(token) ||
          this.storeState.activeSubscriptionId !== subscriptionId) return
        const node: ProxyNode = nodes[index]
        this.proxyTestingNodeIds = [node.id]
        try {
          const milliseconds: number = await coordinator.urlTest(node.id)
          if (!this.isCurrentRuntimeProbe(token) ||
            this.storeState.activeSubscriptionId !== subscriptionId) return
          this.setProxyNodeLatency(node.id, milliseconds)
        } catch (_) {
          if (!this.isCurrentRuntimeProbe(token) ||
            this.storeState.activeSubscriptionId !== subscriptionId) return
          this.setProxyNodeLatency(node.id, -1)
        }
        if (!this.isCurrentRuntimeProbe(token) ||
          this.storeState.activeSubscriptionId !== subscriptionId) return
        this.proxyTestCompletedCount = index + 1
      }
      if (this.isCurrentRuntimeProbe(token) &&
        this.storeState.activeSubscriptionId === subscriptionId) {
        this.showToast('批量代理 URLTest 完成')
      }
    } finally {
      if (token === this.runtimeProbeEpoch) {
        this.proxyTestingNodeIds = []
        this.isProxyTestingAll = false
        this.proxyTestCompletedCount = 0
        this.proxyTestTotalCount = 0
        if (this.connectionPhase === 'connected') await this.syncConnectionStatus()
      }
    }
  }

  private websiteResult(id: string): WebsiteTestResult {
    const found: WebsiteTestResult | undefined = this.websiteTestResults.find((item: WebsiteTestResult) => item.id === id)
    return found ? found : { id: id, state: 'idle', latencyMs: 0, responseCode: 0,
      preflightResponseCode: 0, errorCategory: 'none', errorCode: 0 }
  }

  private websiteProbeErrorLabel(result: WebsiteTestResult): string {
    let category: string = this.t('未知网络错误', 'Unknown network error')
    if (result.errorCategory === 'dns') category = this.t('DNS 解析失败', 'DNS resolution failed')
    if (result.errorCategory === 'tcp') category = this.t('TCP 连接失败', 'TCP connection failed')
    if (result.errorCategory === 'timeout') category = this.t('连接超时', 'Connection timed out')
    if (result.errorCategory === 'tls') category = this.t('TLS 安全连接失败', 'TLS handshake failed')
    if (result.errorCategory === 'io') category = this.t('网络读写失败', 'Network I/O failed')
    return result.errorCode > 0 ? `${category} · E${result.errorCode}` : category
  }

  private websiteResultLabel(result: WebsiteTestResult): string {
    if (result.state === 'testing') return this.t('测试中…', 'Testing…')
    if (result.state === 'reachable') {
      if (result.id === 'chatgpt' && result.preflightResponseCode > 0) {
        return this.t(`入口可达 · 主页可打开 · ${result.latencyMs}ms`,
          `Endpoint reached · Home available · ${result.latencyMs}ms`)
      }
      return result.responseCode === 204 ? this.t(`204 正常 · ${result.latencyMs}ms`, `204 OK · ${result.latencyMs}ms`) :
        this.t(`可打开 · ${result.latencyMs}ms · HTTP ${result.responseCode}`,
          `Available · ${result.latencyMs}ms · HTTP ${result.responseCode}`)
    }
    if (result.state === 'limited') return result.id === 'chatgpt' && result.preflightResponseCode > 0 ?
      this.t(`入口可达 · 主页受限 · HTTP ${result.responseCode}`,
        `Endpoint reached · Home limited · HTTP ${result.responseCode}`) :
      this.t(`端点到达但不可用 · HTTP ${result.responseCode}`,
        `Reached but unavailable · HTTP ${result.responseCode}`)
    if (result.state === 'failed') return result.responseCode > 0 ?
      (result.id === 'chatgpt' && result.preflightResponseCode > 0 ?
        this.t(`入口可达 · 主页失败 · HTTP ${result.responseCode}`,
          `Endpoint reached · Home failed · HTTP ${result.responseCode}`) :
        this.t(`失败 · HTTP ${result.responseCode}`, `Failed · HTTP ${result.responseCode}`)) :
      (result.id === 'chatgpt' && result.preflightResponseCode > 0 ?
        this.t(`入口可达 · 主页${this.websiteProbeErrorLabel(result)}`,
          `Endpoint reached · Home ${this.websiteProbeErrorLabel(result)}`) :
        this.websiteProbeErrorLabel(result))
    return this.t('待测试', 'Not tested')
  }

  private websiteResultIcon(result: WebsiteTestResult): string {
    if (result.state === 'reachable') return '✓'
    if (result.state === 'limited') return '!'
    if (result.state === 'failed') return '×'
    return '◌'
  }

  private websiteResultColor(result: WebsiteTestResult): string {
    if (result.state === 'reachable') return this.palette().accent
    if (result.state === 'limited') return this.palette().warning
    if (result.state === 'failed') return this.palette().danger
    return this.palette().textTertiary
  }

  private updateWebsiteResult(result: WebsiteTestResult): void {
    const next: WebsiteTestResult[] = this.websiteTestResults.filter((item: WebsiteTestResult) => item.id !== result.id)
    next.push(result)
    this.websiteTestResults = WEBSITE_TEST_TARGETS.map((target: WebsiteTestTarget) => {
      const current: WebsiteTestResult | undefined = next.find((item: WebsiteTestResult) => item.id === target.id)
      return current ? current : { id: target.id, state: 'idle', latencyMs: 0, responseCode: 0,
        preflightResponseCode: 0, errorCategory: 'none', errorCode: 0 }
    })
  }

  private async runAllWebsiteTests(): Promise<void> {
    if (this.isTestingWebsites) return
    if (!this.networkConsentGranted()) return
    if (this.connectionPhase !== 'connected') {
      this.showToast('请先连接 VPN，再测试当前网络的网站可用性')
      return
    }
    const token: number = this.runtimeProbeEpoch
    this.isTestingWebsites = true
    this.websiteTestResults = WEBSITE_TEST_TARGETS.map((target: WebsiteTestTarget) => {
      const result: WebsiteTestResult = {
        id: target.id,
        state: 'testing',
        latencyMs: 0,
        responseCode: 0,
        preflightResponseCode: 0,
        errorCategory: 'none',
        errorCode: 0
      }
      return result
    })
    try {
      for (let start: number = 0; start < WEBSITE_TEST_TARGETS.length; start += 3) {
        const tasks: Promise<WebsiteTestResult>[] = []
        const end: number = Math.min(WEBSITE_TEST_TARGETS.length, start + 3)
        for (let index: number = start; index < end; index++) {
          tasks.push(this.websiteProbeService.probe(WEBSITE_TEST_TARGETS[index]))
        }
        const batch: WebsiteTestResult[] = await Promise.all(tasks)
        if (!this.isCurrentRuntimeProbe(token)) return
        for (let index: number = 0; index < batch.length; index++) this.updateWebsiteResult(batch[index])
      }
      if (!this.isCurrentRuntimeProbe(token)) return
      this.showToast('网站可用性测试完成')
    } finally {
      if (token === this.runtimeProbeEpoch) {
        this.isTestingWebsites = false
        if (this.connectionPhase !== 'connected') this.websiteTestResults = emptyWebsiteTestResults()
      }
    }
  }

  private maskedEgressIp(): string {
    if (this.egressInfo.ip.length === 0) return this.t('尚未检测', 'Not checked')
    if (this.revealEgressIp) return this.egressInfo.ip
    if (this.egressInfo.ip.includes(':')) {
      const groups: string[] = this.egressInfo.ip.split(':')
      return groups.length > 2 ? `${groups[0]}:${groups[1]}:••••` : '••••'
    }
    const parts: string[] = this.egressInfo.ip.split('.')
    return parts.length === 4 ? `${parts[0]}.${parts[1]}.•••.•••` : '••••'
  }

  private async probeEgressInfo(): Promise<void> {
    if (this.isTestingEgress) return
    if (!this.networkConsentGranted()) return
    if (this.connectionPhase !== 'connected') {
      this.showToast('请先连接 VPN，再检测当前出口 IP')
      return
    }
    const token: number = this.runtimeProbeEpoch
    this.isTestingEgress = true
    try {
      const result: EgressInfo = await this.websiteProbeService.probeEgress()
      if (!this.isCurrentRuntimeProbe(token)) return
      this.egressInfo = result
      this.showToast('当前出口 IP 检测完成')
    } catch (error) {
      if (!this.isCurrentRuntimeProbe(token)) return
      const message: string = error instanceof Error ? error.message : '出口 IP 检测失败'
      this.showToast(message)
    } finally {
      if (token === this.runtimeProbeEpoch) this.isTestingEgress = false
    }
  }

  private async setTunEnabled(enabled: boolean): Promise<void> {
    if (enabled) {
      if (this.connectionPhase === 'connected') return
      if (this.connectionPhase !== 'idle') {
        this.showToast(this.t('请等待 VPN 状态确认后再开启',
          'Wait until the VPN state is confirmed before turning it on'))
        return
      }
    } else {
      if (this.connectionPhase === 'idle') return
      if (this.connectionPhase !== 'connected') {
        this.showToast(this.t('请等待 VPN 状态确认后再关闭',
          'Wait until the VPN state is confirmed before turning it off'))
        return
      }
    }
    await this.tryConnect()
  }

  private async tryConnect(): Promise<void> {
    const stoppingAllowed: boolean = this.connectionPhase === 'connected' || this.connectionPhase === 'unknown' ||
      this.connectionPhase === 'error'
    if ((this.configurationBusy || this.localConfigLoading) && !stoppingAllowed) {
      this.showToast('请等待当前配置保存完成')
      return
    }
    if ((this.settingsLoading || this.isLoadingStore) && !stoppingAllowed) {
      this.showToast('请等待本地配置恢复完成')
      return
    }
    if (this.isConnectionBusy()) return
    const coordinator: ConnectionCoordinator | null = this.connectionCoordinator
    if (!coordinator) {
      this.showToast('连接服务仍在初始化，请稍后重试')
      return
    }

    if (this.connectionPhase === 'unknown' || this.connectionPhase === 'error') {
      this.reconfigurationEpoch++
      this.invalidateRuntimeProbes()
      this.connectionPhase = 'stopping'
      this.connectionMessage = '正在安全停止可能残留的 VPN/TUN…'
      try {
        const status: CoreStatus = await coordinator.disconnect()
        this.applyCoreStatus(status)
        this.showToast('VPN 已安全停止，可以重新连接')
      } catch (error) {
        const message: string = error instanceof Error ? error.message : 'VPN 安全停止失败'
        this.connectionPhase = 'unknown'
        this.connectionMessage = `${message}；配置仍保持锁定`
        this.showToast(message)
      }
      return
    }

    if (this.connectionPhase === 'connected') {
      // An explicit stop has priority over a connected reconfiguration. Its
      // epoch invalidates every pending post-await reconnect continuation.
      this.reconfigurationEpoch++
      this.invalidateRuntimeProbes()
      this.connectionPhase = 'stopping'
      this.connectionMessage = '正在停止核心并销毁 TUN…'
      try {
        const status: CoreStatus = await coordinator.disconnect()
        this.applyCoreStatus(status)
        this.showToast('VPN 已断开')
      } catch (error) {
        const message: string = error instanceof Error ? error.message : 'VPN 断开失败'
        this.connectionPhase = 'unknown'
        this.connectionMessage = `${message}；断开结果尚未确认`
        this.showToast(message)
      }
      return
    }

    if (!this.networkConsentGranted()) return

    this.coreInfo = coordinator.getInfo()
    if (!this.coreInfo.available) {
      this.showCoreUnavailableDialog()
      return
    }

    if (this.localConfigJson.length > 0) {
      await this.connectLocalConfig(coordinator)
      return
    }
    const record: SubscriptionRecord | undefined = this.activeRecord()
    if (!record || record.bundle.nodes.length === 0 || record.selectedNodeId.length === 0) {
      this.currentTab = 'subscription'
      this.showToast('请先添加订阅并选择节点')
      return
    }

    const unresolvedRule: RoutingRule | undefined = record.bundle.rules.find((rule: RoutingRule) =>
      rule.kind === 'rule_set' || rule.kind === 'unsupported')
    const unconnectedTargetRule: RoutingRule | undefined = record.bundle.rules.find((rule: RoutingRule) =>
      !this.hasConnectedRuleTarget(record.bundle, rule.target))
    if (this.runMode === 'rule' && (unresolvedRule || unconnectedTargetRule)) {
      this.currentTab = 'home'
      if (unconnectedTargetRule) {
        this.showToast(`当前订阅规则引用尚未接通的策略组“${unconnectedTargetRule.target}”；请先使用全局代理或直连模式`)
      } else if (unresolvedRule && unresolvedRule.kind === 'rule_set') {
        this.showToast('当前订阅依赖尚未下载的远程规则集；请先使用全局代理或直连模式')
      } else {
        this.showToast('当前订阅包含尚未支持的规则类型；请先使用全局代理或直连模式')
      }
      return
    }

    if (this.dnsPresetId === 'custom' && this.customDnsDraft !== this.customDns) {
      this.currentTab = 'settings'
      this.showToast('请先校验并保存自定义 DNS')
      return
    }
    let configJson: string = ''
    let applicationScope: VpnApplicationScope
    try {
      const currentSettings: NetworkSettings = this.currentNetworkSettings()
      applicationScope = vpnApplicationScope(currentSettings)
      const dnsEndpoint: string = resolveDnsEndpoint(currentSettings)
      const buildResult: ConfigBuildResult = this.configBuilder.build({
        bundle: record.bundle,
        mode: this.runMode,
        selectedNodeId: record.selectedNodeId,
        selectionMode: this.nodeSelectionMode,
        logLevel: this.logLevel,
        ipv6Enabled: this.ipv6Enabled,
        localRules: this.localRules
      }, dnsEndpoint)
      configJson = buildResult.configJson
    } catch (error) {
      const message: string = error instanceof Error ? error.message : '运行配置不完整'
      this.showToast(message)
      return
    }

    this.invalidateIdleProbes()
    this.invalidateRuntimeProbes()
    this.connectionPhase = 'starting'
    this.connectionMessage = '正在生成运行配置，随后请求系统 VPN…'
    try {
      this.connectionPhase = 'authorizing'
      this.connectionMessage = '正在请求系统 VPN；已授权时不会再次弹窗'
      const status: CoreStatus = await coordinator.connect(configJson, applicationScope)
      this.applyCoreStatus(status)
      this.showToast('VPN/TUN 已连接')
    } catch (error) {
      const message: string = error instanceof Error ? error.message : 'VPN 连接失败'
      if (isConfirmedNoTunStartupError(message)) {
        // The coordinator either closed an unclaimed authorization ticket or
        // observed the Extension's authoritative rollback acknowledgement.
        // In both cases no TUN remains, so configuration can be edited again.
        this.connectionPhase = 'idle'
        this.connectionMessage = message.startsWith('VPN 启动失败且已安全回滚') ?
          message : 'VPN 启动请求未被系统接受，未创建 TUN'
      } else {
        this.connectionPhase = 'unknown'
        this.connectionMessage = `${message}；请重新检查 VPN 状态`
      }
      this.showToast(message)
    }
  }

  private selectionModeTitle(): string {
    if (this.nodeSelectionMode === 'auto') return this.t('自动优选', 'Auto select')
    if (this.nodeSelectionMode === 'failover') return this.t('周期故障转移', 'Failover')
    return this.t('手动选择', 'Manual select')
  }

  private selectionModeDescription(): string {
    if (this.runMode === 'direct') {
      return this.t('直连模式不使用代理组；节点选择只作为下次规则/全局代理连接的首选。',
        'Direct mode bypasses proxy groups. This node is saved for the next Rule or Global connection.')
    }
    if (this.nodeSelectionMode === 'auto') {
      return this.t('sing-box 定期对全部候选执行 URLTest，选择真实代理延迟更低的节点；50ms 容差避免频繁切换。',
        'sing-box periodically URLTests every candidate and selects the fastest real proxy path. A 50 ms tolerance avoids churn.')
    }
    if (this.nodeSelectionMode === 'failover') {
      return this.t('由 sing-box URLTest 周期检查实现首选优先；不是 Mihomo Fallback。失败后通常在 30–45 秒内按订阅顺序切换。',
        'Periodic sing-box URLTests keep the preferred node first and switch in subscription order after failure, usually within 30–45 seconds.')
    }
    return this.t('始终使用你选定的节点；连接后可由 sing-box Selector 热切换，不重建 TUN。',
      'Uses your selected node. While connected, the sing-box Selector switches it live without rebuilding TUN.')
  }

  private selectedNodeRole(): string {
    if (this.runMode === 'direct') return this.t('下次代理首选', 'Next proxy preference')
    if (this.nodeSelectionMode === 'auto') return this.t('偏好节点', 'Preferred node')
    if (this.nodeSelectionMode === 'failover') return this.t('首选节点', 'Primary node')
    return this.t('当前节点', 'Current node')
  }

  private tunRuntimeLabel(): string {
    if (this.connectionPhase === 'connected') {
      return this.applicationMode === 'allowlist' ?
        this.t(`运行中 · 仅 ${this.trustedApplications.length} 个所选应用`,
          `Running · ${this.trustedApplications.length} selected apps`) :
        this.t('运行中 · 全部应用接管', 'Running · All apps tunneled')
    }
    if (this.connectionPhase === 'error' || this.connectionPhase === 'unknown') {
      return this.t('未通过运行确认', 'Runtime not confirmed')
    }
    return this.t('连接时创建 · 尚未运行验证', 'Created on connection · Not running')
  }

  private ipv6RuntimeLabel(): string {
    if (this.connectionPhase === 'connected') {
      return this.ipv6Enabled ? this.t('运行中 · IPv4 + IPv6 代理', 'Running · IPv4 + IPv6 proxied') :
        this.t('运行中 · IPv4 代理 · IPv6 已阻断', 'Running · IPv4 proxied · IPv6 blocked')
    }
    if (this.connectionPhase === 'error' || this.connectionPhase === 'unknown') {
      return this.t('IPv6 运行状态尚未确认', 'IPv6 runtime not confirmed')
    }
    return this.ipv6Enabled ? this.t('已开启 · 下次连接代理双栈', 'On · Dual stack on next connection') :
      this.t('已关闭 · 下次连接拦截并拒绝 IPv6', 'Off · IPv6 blocked on next connection')
  }

  private dnsPresetDescriptionEn(id: DnsPresetId): string {
    if (id === 'cloudflare') return 'Privacy-focused remote DoH, transported through the proxy after bootstrap.'
    if (id === 'quad9') return 'Security-filtered remote DNS, transported through the proxy after bootstrap.'
    if (id === 'alidns') return 'Encrypted AliDNS endpoint optimized for mainland network bootstrap.'
    return 'Use a valid HTTPS DoH or TLS DoT endpoint.'
  }

  private dnsPresetDisplayName(preset: DnsPreset): string {
    if (preset.id === 'custom') return this.t('自定义', 'Custom')
    return preset.name
  }

  private subscriptionActionLabel(record: SubscriptionRecord, action: string): string {
    if (action === 'use') {
      return this.storeState.activeSubscriptionId === record.id ? this.t('当前使用', 'Active') : this.t('切换', 'Use')
    }
    if (action === 'update') return this.t('更新', 'Update')
    if (action === 'rename') return this.t('重命名', 'Rename')
    return this.t('删除', 'Delete')
  }

  private subscriptionActionEnabled(record: SubscriptionRecord, action: string): boolean {
    if (action === 'use') {
      return record.id !== this.storeState.activeSubscriptionId && this.runtimeConfigurationEditable()
    }
    if (action === 'update') return !this.isImporting && this.idleConfigurationEditable()
    if (action === 'rename') return this.subscriptionMetadataEditable()
    return this.idleConfigurationEditable()
  }

  private subscriptionActionForeground(record: SubscriptionRecord, action: string): string {
    if (!this.subscriptionActionEnabled(record, action)) {
      return action === 'use' && record.id === this.storeState.activeSubscriptionId ?
        this.palette().accentForeground : this.palette().textDisabled
    }
    if (action === 'use' && this.storeState.activeSubscriptionId === record.id) return this.palette().accentForeground
    if (action === 'delete') return this.palette().danger
    return this.palette().textSecondary
  }

  private subscriptionActionBackground(record: SubscriptionRecord, action: string): string {
    if (!this.subscriptionActionEnabled(record, action)) {
      return action === 'use' && record.id === this.storeState.activeSubscriptionId ?
        this.palette().accent : this.palette().surfaceMuted
    }
    if (action === 'use' && this.storeState.activeSubscriptionId === record.id) return this.palette().accent
    if (action === 'delete') return this.palette().dangerSoft
    return this.palette().surfaceElevated
  }

  private invokeSubscriptionAction(record: SubscriptionRecord, action: string): void {
    if (action === 'use') this.activateSubscription(record.id)
    else if (action === 'update') this.refreshSubscription(record)
    else if (action === 'rename') this.beginRenameSubscription(record)
    else this.confirmRemoveSubscription(record)
  }

  @Builder
  subscriptionActionButton(record: SubscriptionRecord, action: string, leftMargin: number) {
    Button(this.subscriptionActionLabel(record, action))
      .height(44)
      .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
      .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
        minFontSize: APP_TYPOGRAPHY.controlMin,
        maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
        heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
      .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
      .fontColor(this.subscriptionActionForeground(record, action))
      .backgroundColor(this.subscriptionActionBackground(record, action))
      .borderRadius(9)
      .layoutWeight(1)
      .margin({ left: leftMargin })
      .enabled(this.subscriptionActionEnabled(record, action))
      .onClick(() => this.invokeSubscriptionAction(record, action))
  }

  @Builder
  modeButton(mode: RunMode) {
    Button(this.runModeUiLabel(mode))
      .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
      .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
        minFontSize: APP_TYPOGRAPHY.controlMin,
        maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
        heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
      .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
      .fontWeight(this.runMode === mode ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(!this.runtimeConfigurationEditable() ? this.palette().textDisabled :
        (this.runMode === mode ? this.palette().accentForeground : this.palette().textSecondary))
      .backgroundColor(!this.runtimeConfigurationEditable() ? this.palette().surfaceMuted :
        (this.runMode === mode ? this.palette().accent : this.palette().surfaceElevated))
      .borderRadius(10)
      .height(44)
      .layoutWeight(1)
      .margin({ left: mode === 'rule' ? 0 : (this.isCompactLayout() ? 4 : 6) })
      .enabled(this.runtimeConfigurationEditable())
      .onClick(() => {
        this.selectRunMode(mode)
      })
  }

  @Builder
  selectionModeButton(mode: NodeSelectionMode) {
    Button(this.selectionModeUiLabel(mode))
      .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
      .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
        minFontSize: APP_TYPOGRAPHY.controlMin,
        maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
        heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
      .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
      .fontWeight(this.nodeSelectionMode === mode ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(!this.runtimeConfigurationEditable() ? this.palette().textDisabled :
        (this.nodeSelectionMode === mode ? this.palette().accentForeground : this.palette().textSecondary))
      .backgroundColor(!this.runtimeConfigurationEditable() ? this.palette().surfaceMuted :
        (this.nodeSelectionMode === mode ? this.palette().accent : this.palette().surfaceElevated))
      .borderRadius(10)
      .height(44)
      .layoutWeight(1)
      .margin({ left: mode === 'manual' ? 0 : (this.isCompactLayout() ? 4 : 6) })
      .enabled(this.runtimeConfigurationEditable())
      .onClick(() => {
        this.selectNodeSelectionMode(mode)
      })
  }

  @Builder
  logLevelButton(label: string, level: CoreLogLevel) {
    Button(label)
      .height(44)
      .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
      .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
        minFontSize: APP_TYPOGRAPHY.controlMin,
        maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
        heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
      .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
      .fontColor(!this.runtimeConfigurationEditable() ? this.palette().textDisabled :
        (this.logLevel === level ? this.palette().accentForeground : this.palette().textSecondary))
      .backgroundColor(!this.runtimeConfigurationEditable() ? this.palette().surfaceMuted :
        (this.logLevel === level ? this.palette().accent : this.palette().surfaceElevated))
      .borderRadius(9)
      .layoutWeight(1)
      .margin({ left: level === 'debug' ? 0 : (this.isCompactLayout() ? 4 : 6) })
      .enabled(this.runtimeConfigurationEditable())
      .onClick(() => this.selectLogLevel(level))
  }

  @Builder
  applicationModeButton(mode: VpnApplicationMode) {
    Button(mode === 'all' ? this.t('全部应用', 'All apps') :
      this.t('仅所选应用', 'Only selected'))
      .height(44)
      .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
      .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
        minFontSize: APP_TYPOGRAPHY.controlMin,
        maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
        heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
      .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
      .fontColor(!this.runtimeConfigurationEditable() ? this.palette().textDisabled :
        (this.applicationMode === mode ? this.palette().accentForeground : this.palette().textSecondary))
      .backgroundColor(!this.runtimeConfigurationEditable() ? this.palette().surfaceMuted :
        (this.applicationMode === mode ? this.palette().accent : this.palette().surfaceElevated))
      .borderRadius(10)
      .layoutWeight(1)
      .margin({ left: mode === 'all' ? 0 : 6 })
      .enabled(this.runtimeConfigurationEditable())
      .onClick(() => this.setApplicationMode(mode))
  }

  @Builder
  applicationSelectionRow(application: SelectableApplication) {
    Row() {
      Column() {
        Text(application.label)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(application.bundleName)
          .fontSize(9)
          .fontColor(this.palette().textTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 3 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Toggle({
        type: ToggleType.Switch,
        isOn: this.trustedApplications.includes(application.bundleName)
      })
        .width(52)
        .height(32)
        .selectedColor(this.palette().accent)
        .switchStyle({
          pointRadius: 13,
          trackBorderRadius: 16,
          unselectedColor: this.palette().borderStrong,
          pointColor: this.palette().controlThumb
        })
        .enabled(this.runtimeConfigurationEditable())
        .onChange((selected: boolean) => {
          this.setApplicationSelected(application.bundleName, selected)
        })
    }
    .width('100%')
    .height(52)
    .padding({ left: 10, right: 6 })
    .border({ width: { bottom: 1 }, color: this.palette().border })
    .accessibilityText(`${application.label}，${application.bundleName}`)
  }

  @Builder
  trustedApplicationRow(bundleName: string) {
    Row() {
      Column() {
        Text(this.applicationDisplayName(bundleName))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(bundleName)
          .fontSize(9)
          .fontColor(this.palette().textTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 3 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Button(this.t('移除', 'Remove'))
        .height(44)
        .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
        .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
          minFontSize: APP_TYPOGRAPHY.controlMin,
          maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
          heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
        .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
        .fontColor(this.runtimeConfigurationEditable() ? this.palette().danger : this.palette().textDisabled)
        .backgroundColor(this.palette().dangerSoft)
        .borderRadius(9)
        .margin({ left: 8 })
        .enabled(this.runtimeConfigurationEditable())
        .onClick(() => this.setApplicationSelected(bundleName, false))
    }
    .width('100%')
    .padding({ top: 5, bottom: 5 })
  }

  @Builder
  localRuleKindButton(kind: string) {
    Button(this.localRuleKindLabel(kind))
      .height(44)
      .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
      .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
        minFontSize: APP_TYPOGRAPHY.controlMin,
        maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
        heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
      .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
      .fontColor(!this.runtimeConfigurationEditable() ? this.palette().textDisabled :
        (this.localRuleKind === kind ? this.palette().accentForeground : this.palette().textSecondary))
      .backgroundColor(!this.runtimeConfigurationEditable() ? this.palette().surfaceMuted :
        (this.localRuleKind === kind ? this.palette().accent : this.palette().surfaceElevated))
      .borderRadius(9)
      .layoutWeight(1)
      .margin({ left: kind === 'domain' ? 0 : 5 })
      .enabled(this.runtimeConfigurationEditable())
      .onClick(() => {
        this.localRuleKind = kind
        this.localRuleMessage = ''
      })
  }

  @Builder
  localRuleTargetButton(target: string) {
    Button(this.localRuleTargetLabel(target))
      .height(44)
      .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
      .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
        minFontSize: APP_TYPOGRAPHY.controlMin,
        maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
        heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
      .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
      .fontColor(!this.runtimeConfigurationEditable() ? this.palette().textDisabled :
        (this.localRuleTarget === target ? this.palette().accentForeground : this.palette().textSecondary))
      .backgroundColor(!this.runtimeConfigurationEditable() ? this.palette().surfaceMuted :
        (this.localRuleTarget === target ? this.palette().accent : this.palette().surfaceElevated))
      .borderRadius(9)
      .layoutWeight(1)
      .margin({ left: target === 'proxy' ? 0 : 5 })
      .enabled(this.runtimeConfigurationEditable())
      .onClick(() => {
        this.localRuleTarget = target
        this.localRuleMessage = ''
      })
  }

  @Builder
  localRuleRow(rule: RoutingRule, index: number) {
    Row() {
      Column() {
        Text(rule.value)
          .fontSize(12)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${this.localRuleKindLabel(rule.kind)}  →  ${this.localRuleTargetLabel(rule.target)}`)
          .fontSize(9)
          .fontColor(this.palette().textTertiary)
          .width('100%')
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Button(this.t('删除', 'Delete'))
        .height(44)
        .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
        .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
          minFontSize: APP_TYPOGRAPHY.controlMin,
          maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
          heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
        .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
        .fontColor(this.runtimeConfigurationEditable() ? this.palette().danger : this.palette().textDisabled)
        .backgroundColor(this.palette().dangerSoft)
        .borderRadius(9)
        .margin({ left: 8 })
        .enabled(this.runtimeConfigurationEditable())
        .onClick(() => this.removeLocalRule(index))
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .border({ width: { bottom: 1 }, color: this.palette().border })
    .accessibilityText(`${rule.value}，${this.localRuleKindLabel(rule.kind)}，${this.localRuleTargetLabel(rule.target)}`)
  }

  @Builder
  dnsPresetRow(preset: DnsPreset) {
    Row() {
      Column() {
        Text(this.dnsPresetDisplayName(preset))
          .fontSize(14)
          .fontWeight(this.dnsPresetId === preset.id ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.palette().textPrimary)
        Text(this.effectiveLanguage === 'en' ? this.dnsPresetDescriptionEn(preset.id) : preset.description)
          .fontSize(10)
          .fontColor(this.palette().textTertiary)
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text(this.dnsPresetId === preset.id ? '✓' : '›')
        .fontSize(17)
        .fontColor(this.dnsPresetId === preset.id ? this.palette().accent : this.palette().textDisabled)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(this.dnsPresetId === preset.id ? this.palette().accentSoft : this.palette().surfaceMuted)
    .borderRadius(12)
    .margin({ top: 8 })
    .enabled(this.runtimeConfigurationEditable())
    .opacity(this.runtimeConfigurationEditable() ? 1 : 0.55)
    .onClick(() => this.selectDnsPreset(preset.id))
  }

  @Builder
  subscriptionCard(record: SubscriptionRecord) {
    Column() {
      Row() {
        Column() {
          Text(subscriptionDisplayName(record))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.sourceHost(record.sourceUrl))
            .fontSize(11)
            .fontColor(this.palette().textTertiary)
            .margin({ top: 5 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Text(this.t(`${record.bundle.nodes.length} 节点`, `${record.bundle.nodes.length} nodes`))
          .fontSize(12)
          .fontColor(this.palette().accent)
      }
      .width('100%')

      if (record.bundle.warnings.length > 0) {
        Text(this.t(`${record.bundle.warnings.length} 条兼容性提示：${record.bundle.warnings.slice(0, 2).join('；')}`,
          `${record.bundle.warnings.length} compatibility notes`))
          .fontSize(10)
          .lineHeight(16)
          .fontColor(this.palette().warning)
          .width('100%')
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 10 })
      }

      if (this.renamingSubscriptionId === record.id) {
        Row() {
          TextInput({ placeholder: this.t('留空恢复订阅原标题', 'Leave blank to restore profile title'),
            text: this.renameSubscriptionDraft })
            .height(44)
            .fontSize(12)
            .fontColor(this.palette().textPrimary)
            .placeholderColor(this.palette().placeholder)
            .backgroundColor(this.palette().background)
            .borderRadius(9)
            .padding({ left: 11, right: 11 })
            .maxLength(64)
            .layoutWeight(1)
            .enabled(this.subscriptionMetadataEditable())
            .onChange((value: string) => {
              this.renameSubscriptionDraft = value
            })
          Button(this.t('保存', 'Save'))
            .height(44)
            .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
            .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
              minFontSize: APP_TYPOGRAPHY.controlMin,
              maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
              heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
            .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
            .fontColor(this.subscriptionMetadataEditable() ? this.palette().accentForeground : this.palette().textDisabled)
            .backgroundColor(this.subscriptionMetadataEditable() ? this.palette().accent : this.palette().surfaceMuted)
            .borderRadius(9)
            .margin({ left: 8 })
            .enabled(this.subscriptionMetadataEditable())
            .onClick(() => this.saveSubscriptionRename(record))
          Button(this.t('取消', 'Cancel'))
            .height(44)
            .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
            .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
              minFontSize: APP_TYPOGRAPHY.controlMin,
              maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
              heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
            .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
            .fontColor(this.palette().textSecondary)
            .backgroundColor(this.palette().surfaceElevated)
            .borderRadius(9)
            .margin({ left: 8 })
            .onClick(() => {
              this.renamingSubscriptionId = ''
              this.renameSubscriptionDraft = ''
            })
        }
        .width('100%')
        .margin({ top: 12 })
      }

      if (this.isCompactLayout()) {
        Column() {
          Row() {
            this.subscriptionActionButton(record, 'use', 0)
            this.subscriptionActionButton(record, 'update', 8)
          }
          .width('100%')
          Row() {
            this.subscriptionActionButton(record, 'rename', 0)
            this.subscriptionActionButton(record, 'delete', 8)
          }
          .width('100%')
          .margin({ top: 8 })
        }
        .width('100%')
        .margin({ top: 14 })
      } else {
        Row() {
          this.subscriptionActionButton(record, 'use', 0)
          this.subscriptionActionButton(record, 'update', 8)
          this.subscriptionActionButton(record, 'rename', 8)
          this.subscriptionActionButton(record, 'delete', 8)
        }
        .width('100%')
        .margin({ top: 14 })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.palette().surface)
    .borderRadius(20)
    .border({
      width: this.storeState.activeSubscriptionId === record.id ? 1.5 : 0.5,
      color: this.storeState.activeSubscriptionId === record.id ? this.palette().accent : this.palette().border
    })
    .margin({ top: 10 })
  }

  @Builder
  nodeRow(record: SubscriptionRecord, node: ProxyNode) {
    Row() {
      Button() {
        Row() {
          Column() {
            Text(node.name)
              .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.body : 13)
              .fontWeight(record.selectedNodeId === node.id ? FontWeight.Medium : FontWeight.Regular)
              .fontColor(this.palette().textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(node.protocol.toUpperCase())
              .fontSize(APP_TYPOGRAPHY.micro)
              .fontColor(this.palette().textTertiary)
              .margin({ top: 3 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Text(record.selectedNodeId === node.id ? '✓' : '›')
            .width(this.isCompactLayout() ? 24 : 28)
            .fontSize(17)
            .fontColor(record.selectedNodeId === node.id ? this.palette().accent : this.palette().textDisabled)
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .padding({ left: 15, right: 8 })
      }
      .layoutWeight(1)
      .height(this.isCompactLayout() ? 62 : 66)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .borderRadius(13)
      .opacity(this.nodeSelectionInteractive() ? 1 : 0.55)
      .enabled(this.nodeSelectionInteractive())
      .accessibilityText(node.name)
      .accessibilityDescription(this.nodeSelectionInteractive() ?
        this.t('点击选择节点；右侧按钮单独测速', 'Tap to select the node. The action on the right tests it.') :
        this.t('当前策略不允许手动切换', 'The current strategy does not allow manual selection.'))
      .onClick(() => this.chooseNode(record.id, node.id))
      Button(this.nodeTestActionLabel(node.id))
        .width(this.isCompactLayout() ? 72 : 86)
        .height(44)
        .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
        .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
          minFontSize: APP_TYPOGRAPHY.controlMin,
          maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
          heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
        .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
        .fontColor((this.connectionPhase === 'idle' || this.proxyRuntimeAvailable()) ?
          this.nodeLatencyForeground(node.id) : this.palette().textDisabled)
        .backgroundColor((this.connectionPhase === 'idle' || this.proxyRuntimeAvailable()) ?
          this.nodeLatencyBackground(node.id) : this.palette().surfaceMuted)
        .borderRadius(9)
        .enabled((this.connectionPhase === 'idle' && !this.isProbing(node.id)) ||
          (this.proxyRuntimeAvailable() && !this.proxyTestBusy()))
        .margin({ right: 10 })
        .accessibilityDescription(this.nodeTestActionDescription(node.id))
        .onClick(() => {
          if (this.connectionPhase === 'connected') this.runNodeProxyUrlTest(node)
          else this.probeNode(node)
        })
    }
    .width('100%')
    .height(this.isCompactLayout() ? 62 : 66)
    .backgroundColor(record.selectedNodeId === node.id ? this.palette().accentSoft : this.palette().surface)
    .borderRadius(13)
    .margin({ top: 8 })
  }

  @Builder
  nodeSortButton(mode: string) {
    Button(mode === 'latency' ? this.t('延迟优先', 'Latency') : this.t('默认顺序', 'Default'))
      .width(this.isCompactLayout() ? 78 : 92)
      .height(44)
      .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
      .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
        minFontSize: APP_TYPOGRAPHY.controlMin,
        maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
        heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
      .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
      .fontColor(this.nodeSortMode === mode ? this.palette().accentForeground : this.palette().textSecondary)
      .backgroundColor(this.nodeSortMode === mode ? this.palette().accent : this.palette().surfaceElevated)
      .borderRadius(9)
      .margin({ left: 6 })
      .accessibilityDescription(this.t('切换节点列表排序，不会切换当前节点',
        'Changes list order without switching the active node.'))
      .onClick(() => this.setNodeSortMode(mode))
  }

  @Builder
  tunSwitch() {
    Toggle({ type: ToggleType.Switch, isOn: this.connectionPhase === 'connected' })
      .width(52)
      .height(32)
      .selectedColor(this.palette().accent)
      .switchStyle({ pointRadius: 13, pointColor: this.palette().controlThumb,
        unselectedColor: this.palette().borderStrong, trackBorderRadius: 16 })
      .enabled(this.tunSwitchEnabled())
      .opacity(this.tunSwitchEnabled() ? 1 : 0.55)
      .accessibilityText(this.t('VPN/TUN 接管', 'VPN/TUN handling'))
      .accessibilityDescription(this.connectionPhase === 'connected' ?
        this.t('已开启，关闭会安全销毁 TUN', 'On. Turning it off safely destroys TUN') :
        this.t('已关闭，开启会请求系统 VPN 授权', 'Off. Turning it on requests system VPN permission'))
      .onChange((enabled: boolean) => this.setTunEnabled(enabled))
  }

  @Builder
  unavailableSystemProxySwitch() {
    Toggle({ type: ToggleType.Switch, isOn: false })
      .width(52)
      .height(32)
      .switchStyle({ pointRadius: 13, pointColor: this.palette().controlThumb,
        unselectedColor: this.palette().borderStrong, trackBorderRadius: 16 })
      .enabled(false)
      .opacity(0.45)
      .accessibilityText(this.t('系统全局 HTTP 代理不可用', 'System-wide HTTP proxy unavailable'))
      .accessibilityDescription(this.t('HarmonyOS 普通消费应用无此权限',
        'HarmonyOS consumer apps do not have this permission'))
  }

  @Builder
  ipv6Switch() {
    Toggle({ type: ToggleType.Switch, isOn: this.ipv6Enabled })
      .width(52)
      .height(32)
      .selectedColor(this.palette().accent)
      .switchStyle({ pointRadius: 13, pointColor: this.palette().controlThumb,
        unselectedColor: this.palette().borderStrong, trackBorderRadius: 16 })
      .enabled(this.runtimeConfigurationEditable())
      .opacity(this.runtimeConfigurationEditable() ? 1 : 0.55)
      .accessibilityText(this.t('IPv6 代理', 'IPv6 proxying'))
      .accessibilityDescription(this.ipv6Enabled ?
        this.t('已开启 IPv4 与 IPv6 代理', 'IPv4 and IPv6 proxying is on') :
        this.t('IPv6 已被 TUN 接管并阻断', 'IPv6 is captured and blocked by TUN'))
      .onChange((enabled: boolean) => this.setIpv6Enabled(enabled))
  }

  @Builder
  networkConsentSwitch() {
    Toggle({ type: ToggleType.Switch, isOn: this.privacyConsent === 'accepted' })
      .width(52)
      .height(32)
      .selectedColor(this.palette().accent)
      .switchStyle({ pointRadius: 13, pointColor: this.palette().controlThumb,
        unselectedColor: this.palette().borderStrong, trackBorderRadius: 16 })
      .enabled(this.privacyConsentSwitchEnabled())
      .opacity(this.privacyConsentSwitchEnabled() ? 1 : 0.55)
      .accessibilityText(this.t('允许联网功能', 'Allow network features'))
      .accessibilityDescription(this.privacyConsent === 'accepted' ?
        this.t('已同意；关闭前需要确认并复核 VPN 状态',
          'Accepted. Turning it off requires confirmation and VPN state verification') :
        this.t('已拒绝；开启后可使用订阅、VPN 与联网诊断',
          'Declined. Turning it on enables profiles, VPN and network diagnostics'))
      .onChange((enabled: boolean) => this.setNetworkConsentEnabled(enabled))
  }

  @Builder
  homeNetworkTakeoverCard() {
    Column() {
      Row() {
        Column() {
          Text('TUN / VPN')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().textPrimary)
          Text(this.tunRuntimeLabel())
            .fontSize(APP_TYPOGRAPHY.caption)
            .fontColor(this.connectionPhase === 'connected' ? this.palette().accent : this.palette().textSecondary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        this.tunSwitch()
      }
      .width('100%')
      Row() {
        Column() {
          Text(this.t('系统代理', 'System proxy'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().textDisabled)
          Text(this.t('HarmonyOS 消费应用无全局代理权限', 'Not available to HarmonyOS consumer apps'))
            .fontSize(APP_TYPOGRAPHY.caption)
            .fontColor(this.palette().placeholder)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        this.unavailableSystemProxySwitch()
      }
      .width('100%')
      .margin({ top: 16 })
      Row() {
        Column() {
          Text(this.t('IPv6 接管', 'IPv6 handling'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().textPrimary)
          Text(this.ipv6Enabled ? this.t('代理 IPv4 + IPv6', 'Proxy IPv4 + IPv6') :
            this.t('接管并拒绝 IPv6，防止直连泄漏', 'Capture and block IPv6 to prevent leaks'))
            .fontSize(APP_TYPOGRAPHY.caption)
            .fontColor(this.palette().textTertiary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        this.ipv6Switch()
      }
      .width('100%')
      .margin({ top: 16 })
      Text(this.t('“全局代理”是 TUN 内的路由模式，不等于系统 HTTP 代理。',
        'Global is a routing mode inside TUN; it is not a system HTTP proxy switch.'))
        .fontSize(10)
        .lineHeight(16)
        .fontColor(this.palette().textTertiary)
        .width('100%')
        .margin({ top: 14 })
    }
    .width('100%')
    .padding(18)
    .linearGradient({ angle: 132, colors: [[this.palette().surface, 0],
      [this.palette().surfaceElevated, 0.62], [this.palette().backgroundGlow, 1]] })
    .border({ width: 1, color: this.palette().border })
    .borderRadius(22)
  }


  @Builder
  dashboardMetric(label: string, value: string, detail: string) {
    Column({ space: 6 }) {
      Text(label).fontSize(12).fontColor(this.palette().textSecondary)
      Text(value).fontSize(21).fontWeight(FontWeight.Medium)
        .fontColor(this.palette().textPrimary).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(detail).fontSize(11).fontColor(this.palette().textTertiary).maxLines(1)
    }
    .layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

  @Builder
  dashboardRow(icon: Resource, title: string, value: string, tab: string) {
    Row({ space: 14 }) {
      SymbolGlyph(icon).fontSize(22).fontColor([this.palette().accent])
      Column({ space: 5 }) {
        Text(title).fontSize(15).fontColor(this.palette().textPrimary)
        Text(value).fontSize(12).fontColor(this.palette().textSecondary)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text('›').fontSize(24).fontColor(this.palette().textTertiary)
    }
    .width('100%').constraintSize({ minHeight: 76 }).padding(18)
    .backgroundColor(this.palette().surface).borderRadius(22)
    .accessibilityText(title + ' ' + value)
    .onClick(() => { this.currentTab = tab })
  }

  @Builder
  homePage() {
    Scroll() {
      Column({ space: 16 }) {
        Column({ space: 18 }) {
          Row({ space: 12 }) {
            Stack() {
              SymbolGlyph($r('sys.symbol.diagnostic_analytics')).fontSize(28)
                .fontColor([this.connectionColor()])
            }.width(52).height(52).borderRadius(26)
              .backgroundColor(this.palette().accentSoft)
            Column({ space: 5 }) {
              Text(this.connectionTitle()).fontSize(23).fontWeight(FontWeight.Medium)
                .fontColor(this.palette().textPrimary).maxLines(1)
              Text('sing-box ' + this.coreInfo.version).fontSize(12)
                .fontColor(this.palette().textSecondary)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }.width('100%')
          Text(this.localizedRuntimeText(this.connectionMessage)).fontSize(13).lineHeight(20)
            .fontColor(this.connectionPhase === 'error' ? this.palette().danger : this.palette().textSecondary)
            .width('100%')
          Button(this.connectionButtonLabel())
            .width('100%').height(52).fontSize(16).fontWeight(FontWeight.Medium)
            .backgroundColor(this.connectionActionColor()).fontColor(this.palette().accentForeground)
            .borderRadius(26).enabled(this.connectionActionEnabled())
            .onClick(() => this.tryConnect())
        }.width('100%').padding(22).backgroundColor(this.palette().surface)
          .borderRadius(26)

        Row({ space: 12 }) {
          this.dashboardMetric(this.t('下载', 'Download'), this.downloadRate,
            this.localizedRuntimeText(this.downloadSpeed))
          this.dashboardMetric(this.t('上传', 'Upload'), this.uploadRate,
            this.localizedRuntimeText(this.uploadSpeed))
          this.dashboardMetric(this.t('连接', 'Connections'), this.activeConnections.toString(),
            this.connectionPhase === 'connected' ? this.t('实时', 'Live') : this.t('未连接', 'Offline'))
        }.width('100%').padding(20).backgroundColor(this.palette().surface).borderRadius(22)

        this.dashboardRow($r('sys.symbol.rectangle_stack'), this.t('当前配置', 'Current profile'),
          this.localConfigJson.length > 0 ? this.t('本地 sing-box JSON', 'Local sing-box JSON') :
            this.localizedRuntimeText(this.subscriptionName), 'subscription')
        this.dashboardRow($r('sys.symbol.diagnostic_analytics'), this.t('代理与路由', 'Proxies and routing'),
          this.localConfigJson.length > 0 ? this.t('由本地配置管理', 'Managed by local profile') :
            this.runModeUiLabel(this.runMode) + ' · ' + this.localizedRuntimeText(this.selectedNodeName), 'proxy')
        this.dashboardRow($r('sys.symbol.diagnostic_analytics'), this.t('运行诊断', 'Diagnostics'),
          this.t('流量、规则与连通性测试', 'Traffic, rules and connectivity'), 'activity')

        Column({ space: 10 }) {
          Row() {
            Text(this.t('后台连接', 'Background connection')).fontSize(15)
              .fontColor(this.palette().textPrimary)
            Blank()
            Text('VPN Extension').fontSize(11).fontColor(this.palette().accent)
          }.width('100%')
          Text(this.t('连接后可返回桌面或锁屏。VPN 扩展独立管理隧道；断开请使用上方按钮。',
            'After connecting, return Home or lock the screen. The VPN extension owns the tunnel; use Disconnect to stop.'))
            .fontSize(12).lineHeight(19).fontColor(this.palette().textSecondary).width('100%')
        }.width('100%').padding(18).backgroundColor(this.palette().surface).borderRadius(22)

        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text(this.t('减少透明效果', 'Reduce transparency')).fontSize(15)
              .fontColor(this.palette().textPrimary)
            Text(this.t('使用实色导航背景', 'Use a solid navigation background')).fontSize(12)
              .fontColor(this.palette().textSecondary)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.reduceTransparency })
            .selectedColor(this.palette().accent)
            .onChange((value: boolean) => { this.setReducedTransparency(value) })
        }.width('100%').padding(18).backgroundColor(this.palette().surface).borderRadius(22)
      }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 112 })
    }.layoutWeight(1).scrollBar(BarState.Off)
  }

  private async setReducedTransparency(value: boolean): Promise<void> {
    this.reduceTransparency = value
    if (!this.uiPreferences) return
    try {
      await this.uiPreferences.put('reduce-transparency', value)
      await this.uiPreferences.flush()
    } catch (_) {
      this.showToast(this.t('外观设置暂未保存', 'Appearance setting was not saved'))
    }
  }

  @Builder
  proxyPage() {
    Scroll() {
      Column() {
        Column() {
          Row() {
            Column() {
              Text(this.t('联网功能', 'Network features'))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette().textSecondary)
              Text(this.privacyConsent === 'accepted' ?
                this.t('已同意 · 可在设置中管理', 'Accepted · Manage in Settings') :
                this.t('离线受限 · 可在设置中启用', 'Offline limited · Enable in Settings'))
                .fontSize(10)
                .fontColor(this.privacyConsent === 'accepted' ? this.palette().accent : this.palette().warning)
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text(this.privacyConsent === 'accepted' ? this.t('已开启', 'Enabled') : this.t('已关闭', 'Disabled'))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.privacyConsent === 'accepted' ? this.palette().accent : this.palette().warning)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor(this.privacyConsent === 'accepted' ? this.palette().accentSoft : this.palette().warningSoft)
              .borderRadius(12)
          }
          .width('100%')
          Row() {
            Column() {
              Text(this.t('实时网络状态', 'LIVE NETWORK STATUS'))
                .fontSize(APP_TYPOGRAPHY.caption)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette().textTertiary)
                .letterSpacing(0.6)
              Text(this.connectionTitle())
                .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.displayCompact : APP_TYPOGRAPHY.display)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.connectionColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .margin({ top: 6 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Stack() {
              Text('◌')
                .fontSize(28)
                .fontColor(this.connectionColor())
              Text(this.connectionPhase === 'connected' ? '●' : '○')
                .fontSize(11)
                .fontColor(this.connectionColor())
            }
              .width(54)
              .height(54)
              .backgroundColor(this.palette().accentSoft)
              .border({ width: 1, color: this.palette().borderStrong })
              .borderRadius(27)
          }
          .width('100%')

          Text(this.localizedRuntimeText(this.connectionMessage))
            .fontSize(12)
            .lineHeight(18)
            .fontColor(this.connectionPhase === 'error' ? this.palette().danger :
              (this.connectionPhase === 'unknown' || this.connectionPhase === 'checking' ? this.palette().warning :
              (this.coreInfo.available ? this.palette().accent : this.palette().warning)))
            .margin({ top: 16 })

          if (this.connectionPhase === 'unknown' || this.connectionPhase === 'error') {
            Button(this.connectionButtonLabel())
              .width('100%')
              .height(52)
              .fontSize(APP_TYPOGRAPHY.control)
              .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
                minFontSize: APP_TYPOGRAPHY.controlMin, maxFontSize: APP_TYPOGRAPHY.control,
                heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
              .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().accentForeground)
              .backgroundColor(this.connectionActionColor())
              .borderRadius(14)
              .margin({ top: 18 })
              .enabled(this.connectionActionEnabled())
              .accessibilityDescription(this.t('只执行安全停止和状态复核，不会立即重连',
                'Performs only a safe stop and status verification; it does not reconnect immediately'))
              .onClick(() => this.tryConnect())
          }
        }
        .width('100%')
        .padding(20)
        .linearGradient({ angle: 138, colors: [[this.palette().surface, 0],
          [this.palette().surfaceGlass, 0.56], [this.palette().backgroundGlowSecondary, 1]] })
        .borderRadius(24)
        .border({ width: 1, color: this.palette().borderStrong })
        .shadow({ radius: 18, color: this.palette().shadow, offsetY: 8 })

        Text(this.t('网络接管', 'NETWORK HANDLING'))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .letterSpacing(0.7)
          .fontColor(this.palette().textSecondary)
          .width('100%')
          .margin({ top: 22, bottom: 10 })
        this.homeNetworkTakeoverCard()

        Text(this.t('路由模式', 'ROUTING MODE'))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .letterSpacing(0.7)
          .fontColor(this.palette().textSecondary)
          .width('100%')
          .margin({ top: 22, bottom: 10 })
        Row() {
          this.modeButton('rule')
          this.modeButton('global')
          this.modeButton('direct')
        }
        .width('100%')
        Text(this.runMode === 'rule' ?
          this.t('规则：按订阅规则分流，未匹配流量按订阅最终规则处理。',
            'Rule: route by subscription rules; unmatched traffic follows the final rule.') :
          (this.runMode === 'global' ?
            this.t('全局代理：TUN 接管的流量全部交给当前节点；不是系统 HTTP 代理开关。',
              'Global: all TUN traffic uses the current node. This is not a system HTTP proxy switch.') :
            this.t('直连：TUN 仍保持连接，但业务流量不经过代理节点。',
              'Direct: TUN remains connected, but application traffic bypasses proxy nodes.')))
          .fontSize(11)
          .lineHeight(17)
          .fontColor(this.palette().textTertiary)
          .width('100%')
          .margin({ top: 9 })

        Text(this.t('节点策略', 'NODE STRATEGY'))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .letterSpacing(0.7)
          .fontColor(this.palette().textSecondary)
          .width('100%')
          .margin({ top: 22, bottom: 10 })
        Row() {
          this.selectionModeButton('manual')
          this.selectionModeButton('auto')
          this.selectionModeButton('failover')
        }
        .width('100%')
        Column() {
          Row() {
            Text(this.selectionModeTitle())
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().accent)
            Blank()
            Text(this.nodeSelectionMode === 'manual' ? 'Selector' : 'URLTest')
              .fontSize(10)
              .fontColor(this.palette().textSecondary)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(this.palette().surfaceElevated)
              .borderRadius(8)
          }
          .width('100%')
          Text(this.selectionModeDescription())
            .fontSize(11)
            .lineHeight(18)
            .fontColor(this.palette().textTertiary)
            .width('100%')
            .margin({ top: 8 })
        }
        .width('100%')
        .padding(14)
        .backgroundColor(this.palette().surfaceMuted)
        .borderRadius(12)
        .margin({ top: 9 })

        Column() {
          Row() {
            Text(this.selectedNodeRole())
              .fontSize(APP_TYPOGRAPHY.body)
              .fontColor(this.palette().textTertiary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Blank()
            Column() {
              Text(`TCP ${this.latencyText}`)
                .fontSize(APP_TYPOGRAPHY.caption)
                .fontColor(this.palette().textSecondary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.connectionPhase === 'connected' && this.runMode === 'direct' ?
                this.t('代理 URLTest 不适用', 'Proxy URLTest unavailable') :
                `Proxy URLTest ${this.localizedRuntimeText(this.proxyLatencyText)}`)
                .fontSize(APP_TYPOGRAPHY.caption)
                .fontColor(this.palette().accent)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 3 })
            }
            .alignItems(HorizontalAlign.End)
          }
          .width('100%')
          Text(this.localizedNodeName(this.selectedNodeName))
            .fontSize(APP_TYPOGRAPHY.sectionTitle)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().textPrimary)
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 7 })
          Text(this.localizedSubscriptionName(this.subscriptionName))
            .fontSize(APP_TYPOGRAPHY.body)
            .fontColor(this.palette().textTertiary)
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
          if (this.connectionPhase === 'connected' && this.runMode === 'direct') {
            Text(this.t('当前业务出站：直连', 'Active outbound: Direct'))
              .fontSize(11)
              .fontColor(this.palette().accent)
              .width('100%')
              .margin({ top: 8 })
          } else if (this.connectionPhase === 'connected' && this.runtimeSelectedNodeName.length > 0) {
            Text(this.t(`运行中实际节点：${this.runtimeSelectedNodeName}`,
              `Active runtime node: ${this.runtimeSelectedNodeName}`))
              .fontSize(11)
              .fontColor(this.palette().accent)
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 8 })
          }
          Button(this.connectionPhase === 'connected' && this.runMode === 'direct' ?
            this.t('直连模式不使用代理', 'Proxy disabled in Direct mode') :
              (this.isProxyTesting ? this.t('正在通过代理组测试…', 'Testing through proxy group…') : 'Proxy group URLTest'))
            .width('100%')
            .height(44)
            .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
            .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
              minFontSize: APP_TYPOGRAPHY.controlMin,
              maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
              heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
            .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
            .fontColor(this.proxyRuntimeAvailable() ? this.palette().accentForeground : this.palette().textTertiary)
            .backgroundColor(this.proxyRuntimeAvailable() ? this.palette().accent : this.palette().surfaceElevated)
            .borderRadius(10)
            .enabled(this.proxyRuntimeAvailable() && !this.proxyTestBusy())
            .margin({ top: 13 })
            .onClick(() => this.runSelectedProxyUrlTest())
          Text(this.connectionPhase === 'connected' && this.runMode === 'direct' ?
            this.t('当前 TUN 仅做直连转发，不经过任何代理节点；节点选择只保存给下次代理连接。',
              'The current TUN forwards directly. Node selection is saved for the next proxied connection.') :
            this.t('代理组 URLTest 会经过 sing-box 当前实际 outbound 发起请求；TCP 延迟只测服务器端口。',
              'Proxy URLTest uses the active sing-box outbound. TCP latency only checks the server port.'))
            .fontSize(10)
            .lineHeight(16)
            .fontColor(this.palette().textTertiary)
            .width('100%')
            .margin({ top: 7 })
        }
        .width('100%')
        .padding(18)
        .backgroundColor(this.palette().surface)
        .borderRadius(22)
        .margin({ top: 18 })

        if (this.activeRecord()) {
          Row() {
            Column() {
              Text(this.t(`首页节点切换 · ${this.nodeCount}`, `Switch node · ${this.nodeCount}`))
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette().textPrimary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.t(`${this.subscriptionName} · 点节点即可设置${this.selectedNodeRole()}`,
                `${this.localizedSubscriptionName(this.subscriptionName)} · Tap a node to set ${this.selectedNodeRole()}`))
                .fontSize(10)
                .fontColor(this.palette().textTertiary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Button(this.batchNodeTestLabel())
              .width(this.isCompactLayout() ? 106 : 132)
              .height(44)
              .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
              .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
                minFontSize: APP_TYPOGRAPHY.controlMin,
                maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
                heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
              .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
              .fontColor(this.batchNodeTestEnabled() ? this.palette().accentForeground : this.palette().textDisabled)
              .backgroundColor(this.batchNodeTestEnabled() ? this.palette().accent : this.palette().surfaceMuted)
              .borderRadius(9)
              .enabled(this.batchNodeTestEnabled())
              .onClick(() => this.runBatchNodeTests())
          }
          .width('100%')
          .margin({ top: 22 })

          TextInput({ placeholder: this.t('搜索节点名称或协议', 'Search node name or protocol'), text: this.nodeFilter })
            .width('100%')
            .height(44)
            .fontSize(12)
            .fontColor(this.palette().textPrimary)
            .placeholderColor(this.palette().placeholder)
            .backgroundColor(this.palette().surface)
            .border({ width: 1, color: this.palette().border })
            .borderRadius(11)
            .padding({ left: 13, right: 13 })
            .margin({ top: 10 })
            .maxLength(128)
            .onChange((value: string) => this.updateNodeFilter(value))

          Row() {
            Text(this.t('节点排序', 'Node order'))
              .fontSize(APP_TYPOGRAPHY.caption)
              .fontColor(this.palette().textTertiary)
              .layoutWeight(1)
            this.nodeSortButton('default')
            this.nodeSortButton('latency')
          }
          .width('100%')
          .margin({ top: 9 })
          Text(this.t('延迟等级：快 ≤100 · 一般 ≤250 · 慢 ≤600 · 很慢 >600ms；未测和失败排在已测节点之后。',
            'Latency: fast ≤100 · normal ≤250 · slow ≤600 · very slow >600ms. Untested and failed nodes follow measured nodes.'))
            .fontSize(APP_TYPOGRAPHY.micro)
            .lineHeight(15)
            .fontColor(this.palette().textTertiary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 6 })

          Text(this.nodeFilter.trim().length === 0 ?
            this.t(`已显示 ${this.visibleNodes().length} / ${this.matchingNodes().length}`,
              `Showing ${this.visibleNodes().length} of ${this.matchingNodes().length}`) :
            this.t(`筛选 ${this.matchingNodes().length} / 全部 ${this.nodeCount} · 已显示 ${this.visibleNodes().length}`,
              `${this.matchingNodes().length} of ${this.nodeCount} match · showing ${this.visibleNodes().length}`))
            .fontSize(10)
            .fontColor(this.palette().textTertiary)
            .width('100%')
            .margin({ top: 8 })

          if (this.matchingNodes().length === 0) {
            Text(this.t('没有匹配的节点', 'No matching nodes'))
              .fontSize(12)
              .fontColor(this.palette().textTertiary)
              .width('100%')
              .padding(16)
              .backgroundColor(this.palette().surfaceMuted)
              .borderRadius(12)
              .margin({ top: 10 })
          } else {
            ForEach(this.visibleNodes(), (node: ProxyNode) => {
              this.nodeRow(this.activeRecord() as SubscriptionRecord, node)
            }, (node: ProxyNode) => node.id)
          }

          if (this.visibleNodes().length < this.matchingNodes().length) {
            Button(this.t(`再显示 ${Math.min(NODE_RENDER_BATCH_SIZE,
              this.matchingNodes().length - this.visibleNodes().length)} 个`,
              `Load ${Math.min(NODE_RENDER_BATCH_SIZE,
                this.matchingNodes().length - this.visibleNodes().length)} more`))
              .width('100%')
              .height(44)
              .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
              .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
                minFontSize: APP_TYPOGRAPHY.controlMin,
                maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
                heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
              .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
              .fontColor(this.palette().accent)
              .backgroundColor(this.palette().accentSoft)
              .borderRadius(11)
              .margin({ top: 10 })
              .onClick(() => this.loadMoreNodes())
          }

          Text(this.connectionPhase === 'connected' ?
            (this.runMode === 'direct' ?
              this.t('直连模式不经过代理；点节点只保存下次代理连接的首选，代理测速保持关闭。',
                'Direct mode bypasses proxy nodes. Tapping only saves the next preference; proxy tests stay disabled.') :
              (this.nodeSelectionMode === 'manual' ?
              this.t('运行中可直接切换节点；可单独或批量通过 sing-box 对每个节点进行真实代理测速。',
                'Switch nodes live while connected. Test one or all nodes through real sing-box proxy URLTests.') :
              this.t('自动策略由核心决定当前节点；运行中节点列表已锁定，切换为手动模式后可热切换。',
                'The core controls automatic strategies. The node list is locked while connected; switch to Manual for live selection.'))) :
            this.t('TCP 只检查服务器端口可达性。真正的代理协议延迟请连接后使用上方代理组 URLTest。',
              'TCP only checks server-port reachability. Connect first to measure real proxy protocol latency.'))
            .fontSize(11)
            .lineHeight(17)
            .fontColor(this.palette().textTertiary)
            .width('100%')
            .padding(14)
            .backgroundColor(this.palette().surfaceMuted)
            .borderRadius(12)
            .margin({ top: 12 })
        } else {
          Button(this.t('前往添加订阅', 'Add a subscription'))
            .width('100%')
            .height(44)
            .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
            .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
              minFontSize: APP_TYPOGRAPHY.controlMin,
              maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
              heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
            .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
            .fontColor(this.palette().accent)
            .backgroundColor(this.palette().surfaceElevated)
            .borderRadius(12)
            .margin({ top: 18 })
            .onClick(() => {
              this.currentTab = 'subscription'
            })
        }

        Row() {
          Column() {
            Text(this.t('↓ 累计下载', '↓ Downloaded'))
              .fontSize(12)
              .fontColor(this.palette().textTertiary)
            Text(this.localizedRuntimeText(this.downloadSpeed))
              .fontSize(APP_TYPOGRAPHY.metric)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 5 })
            Text(this.downloadRate)
              .fontSize(10)
              .fontColor(this.palette().blue)
              .margin({ top: 3 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Column() {
            Text(this.t('↑ 累计上传', '↑ Uploaded'))
              .fontSize(12)
              .fontColor(this.palette().textTertiary)
            Text(this.localizedRuntimeText(this.uploadSpeed))
              .fontSize(APP_TYPOGRAPHY.metric)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 5 })
            Text(this.uploadRate)
              .fontSize(10)
              .fontColor(this.palette().warning)
              .margin({ top: 3 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Column() {
            Text(this.t('活跃连接', 'Active'))
              .fontSize(12)
              .fontColor(this.palette().textTertiary)
            Text(`${this.activeConnections}`)
              .fontSize(APP_TYPOGRAPHY.metric)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().accent)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 5 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding(18)
        .backgroundColor(this.palette().surface)
        .borderRadius(22)
        .margin({ top: 12, bottom: 112 })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  subscriptionPage() {
    Scroll() {
      Column() {
        Column() {
          Text(this.t('配置', 'Profiles'))
            .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.pageTitleCompact : APP_TYPOGRAPHY.pageTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().textPrimary)
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.t('每个地址独立保存和更新；支持 sing-box JSON、Clash/Mihomo 常用 YAML、Base64/URI 节点列表。',
            'Each source is stored and updated independently. Supports sing-box JSON, common Clash/Mihomo YAML, Base64 and URI lists.'))
            .fontSize(13)
            .lineHeight(20)
            .fontColor(this.palette().textSecondary)
            .width('100%')
            .margin({ top: 8 })
          Text(this.localConfigJson.length > 0 ? '当前配置：本地 sing-box JSON' : '本地 sing-box 配置')
            .fontSize(18).fontColor(this.palette().textPrimary).margin({ top: 12 })
          Text('保留 DNS、分流、规则集和测速组；TUN 地址、MTU、协议栈由鸿蒙 VPN 适配。文件内引用的其他本地文件不会自动导入。使用本地配置时，订阅节点和分流设置不生效。')
            .fontSize(12).fontColor(this.palette().textSecondary).margin({ top: 8 })
          Button('选择本地 JSON 文件')
            .width('100%').margin({ top: 12 })
            .enabled(this.idleConfigurationEditable()).onClick(() => this.importLocalFile())
          TextArea({ placeholder: '也可以粘贴完整 sing-box JSON', text: this.localConfigDraft })
            .height(130).maxLength(4194304).margin({ top: 8 })
            .enabled(this.idleConfigurationEditable())
            .onChange((value: string) => { this.localConfigDraft = value })
          Button('校验并使用粘贴的配置')
            .width('100%').margin({ top: 8 })
            .enabled(this.idleConfigurationEditable() && this.localConfigDraft.length > 0)
            .onClick(() => this.importLocalText())
          Text(this.localConfigLoading ? '正在读取并校验…' : this.localConfigMessage)
            .fontSize(12).fontColor(this.palette().textSecondary).margin({ top: 8 })
          if (this.localConfigJson.length > 0) {
            Button('移除本地配置并切回订阅')
              .width('100%').margin({ top: 8 }).enabled(this.idleConfigurationEditable())
              .onClick(() => this.useSubscriptionConfig())
          }
          TextInput({ placeholder: this.t('订阅名称（可选）', 'Subscription name (optional)'),
            text: this.newSubscriptionName })
            .height(44)
            .fontSize(13)
            .fontColor(this.palette().textPrimary)
            .placeholderColor(this.palette().placeholder)
            .backgroundColor(this.palette().background)
            .borderRadius(12)
            .padding({ left: 14, right: 14 })
            .maxLength(64)
            .margin({ top: 18 })
            .enabled(!this.isImporting && this.idleConfigurationEditable())
            .onChange((value: string) => {
              this.newSubscriptionName = value
            })
          TextInput({ placeholder: 'https://example.com/subscription', text: this.subscriptionUrl })
            .height(48)
            .fontSize(14)
            .fontColor(this.palette().textPrimary)
            .placeholderColor(this.palette().placeholder)
            .backgroundColor(this.palette().background)
            .borderRadius(12)
            .padding({ left: 14, right: 14 })
            .margin({ top: 10 })
            .enabled(!this.isImporting && this.idleConfigurationEditable())
            .onChange((value: string) => {
              this.subscriptionUrl = value
            })
          Button(this.isImporting ? this.t('正在解析…', 'Parsing…') : this.t('添加新订阅', 'Add subscription'))
            .width('100%')
            .height(48)
            .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
            .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
              minFontSize: APP_TYPOGRAPHY.controlMin,
              maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
              heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
            .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
            .fontColor(this.isImporting || !this.idleConfigurationEditable() ?
              this.palette().textDisabled : this.palette().accentForeground)
            .backgroundColor(this.isImporting || !this.idleConfigurationEditable() ? this.palette().borderStrong : this.palette().accent)
            .borderRadius(12)
            .margin({ top: 12 })
            .enabled(!this.isImporting && this.idleConfigurationEditable())
            .onClick(() => this.importSubscription())
          Text(this.localizedRuntimeText(this.importMessage))
            .fontSize(12)
            .lineHeight(18)
            .fontColor(this.palette().textSecondary)
            .width('100%')
            .margin({ top: 12 })
        }
        .width('100%')
        .padding(18)
        .backgroundColor(this.palette().surface)
        .borderRadius(22)
        .border({ width: 1, color: this.palette().border })
        .shadow({ radius: 14, color: this.palette().shadow, offsetY: 6 })

        Row() {
          Text(this.t(`订阅列表 · ${this.storeState.records.length}`,
            `Subscriptions · ${this.storeState.records.length}`))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().textPrimary)
          Blank()
          if (this.isLoadingStore) {
            Text(this.t('正在恢复…', 'Restoring…'))
              .fontSize(11)
              .fontColor(this.palette().textTertiary)
          }
        }
        .width('100%')
        .margin({ top: 20 })
        Text(this.connectionPhase === 'connected' ?
          this.t('切换“当前使用”会先安全停止现有 TUN，并按新订阅自动重连；完成前不会显示为已生效。',
            'Changing the active subscription safely stops TUN and reconnects with the new profile. It is not marked active until confirmed.') :
          this.t('“当前使用”决定下一次连接所用的节点与规则。',
            'The active subscription provides nodes and rules for the next connection.'))
          .fontSize(10)
          .lineHeight(16)
          .fontColor(this.palette().textTertiary)
          .width('100%')
          .margin({ top: 7 })

        if (this.storeState.records.length === 0) {
          Text(this.t('还没有订阅。添加后会在这里显示，每个订阅互不覆盖。',
            'No subscriptions yet. Added sources appear independently and never overwrite one another.'))
            .fontSize(13)
            .lineHeight(20)
            .fontColor(this.palette().textTertiary)
            .width('100%')
            .padding(18)
            .backgroundColor(this.palette().surface)
            .borderRadius(20)
            .margin({ top: 10 })
        } else {
          ForEach(this.storeState.records, (record: SubscriptionRecord) => {
            this.subscriptionCard(record)
          }, (record: SubscriptionRecord) => record.id)
        }

        Text(this.t('订阅页只管理来源、更新和删除；节点选择、策略与测速已集中到首页。',
          'This page manages sources, updates and removal. Node selection, strategy and tests stay on Home.'))
          .fontSize(11)
          .lineHeight(18)
          .fontColor(this.palette().textTertiary)
          .width('100%')
          .padding(14)
          .backgroundColor(this.palette().surfaceMuted)
          .borderRadius(12)
          .margin({ top: 18 })

        Blank()
          .height(24)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  activitySectionButton(section: string) {
    Button(this.activitySectionUiLabel(section))
      .height(44)
      .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
      .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
        minFontSize: APP_TYPOGRAPHY.controlMin,
        maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
        heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
      .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
      .fontColor(this.activitySection === section ? this.palette().accentForeground : this.palette().textSecondary)
      .backgroundColor(this.activitySection === section ? this.palette().accent : this.palette().surfaceElevated)
      .borderRadius(10)
      .layoutWeight(1)
      .margin({ left: section === 'overview' ? 0 : (this.isCompactLayout() ? 4 : 6) })
      .onClick(() => {
        this.activitySection = section
      })
  }

  @Builder
  ruleRow(rule: RoutingRule, index: number) {
    Row() {
      Text(`${index + 1}`)
        .width(30)
        .fontSize(11)
        .fontColor(this.palette().textDisabled)
      Column() {
        Text(rule.value.length > 0 ? rule.value : this.t('最终规则', 'Final rule'))
          .fontSize(13)
          .fontColor(this.palette().textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${this.t('订阅 · 只读', 'Subscription · read-only')}  ·  ${rule.kind}  →  ${rule.target}`)
          .fontSize(10)
          .fontColor(rule.kind === 'unsupported' || rule.kind === 'rule_set' ? this.palette().warning : this.palette().textTertiary)
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(this.palette().surface)
    .borderRadius(12)
    .margin({ top: 7 })
  }

  @Builder
  websiteTestCard(target: WebsiteTestTarget) {
    Column() {
      Row() {
        Text(target.name)
          .fontSize(APP_TYPOGRAPHY.cardTitle)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
        Text(this.websiteResultIcon(this.websiteResult(target.id)))
          .fontSize(16)
          .fontColor(this.websiteResultColor(this.websiteResult(target.id)))
      }
      .width('100%')
      Text(this.websiteResultLabel(this.websiteResult(target.id)))
        .fontSize(10)
        .lineHeight(15)
        .fontColor(this.websiteResultColor(this.websiteResult(target.id)))
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8 })
    }
    .layoutWeight(1)
    .height(94)
    .padding(12)
    .backgroundColor(this.palette().surface)
    .borderRadius(12)
  }

  @Builder
  activityPage() {
    Column() {
      Row() {
        this.activitySectionButton('logs')
        this.activitySectionButton('overview')
        this.activitySectionButton('rules')
        this.activitySectionButton('tests')
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 10 })
      .backgroundColor(this.palette().background)

      Scroll() {
        Column() {
        if (this.activitySection === 'logs') {
          Text(this.t('连接事件', 'Connection events')).fontSize(18).fontWeight(FontWeight.Medium)
            .fontColor(this.palette().textPrimary).width('100%')
          Text(this.t('记录本次打开应用后的连接状态和错误；完整内核日志暂不提供。',
            'Connection states and errors since opening this page. Full core logs are not available.'))
            .fontSize(12).lineHeight(19).fontColor(this.palette().textSecondary).width('100%')
          if (this.connectionEvents.length === 0) {
            Text(this.t('暂无连接事件', 'No connection events yet')).fontSize(14)
              .fontColor(this.palette().textTertiary).margin({ top: 32, bottom: 32 })
          }
          ForEach(this.connectionEvents, (event: string, index: number) => {
            Text(event).fontSize(12).fontFamily('monospace').lineHeight(20)
              .fontColor(this.palette().textPrimary).width('100%').padding(14)
              .backgroundColor(this.palette().surface).borderRadius(12)
          }, (_event: string, index: number) => index.toString())
          Button(this.t('清空事件', 'Clear events')).onClick(() => { this.connectionEvents = [] })
        } else if (this.activitySection === 'overview') {
          Column() {
            Text(this.t('运行诊断', 'Runtime diagnostics'))
              .fontSize(APP_TYPOGRAPHY.sectionTitle)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().textPrimary)
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.t(`VPN：${this.connectionTitle()}\n路由：${this.runMode}\n节点策略：${this.selectionModeTitle()}\nDNS：${this.dnsPresetDisplayName(findDnsPreset(this.dnsPresetId))}\n核心：${this.coreInfo.version || '未知'}`,
              `VPN: ${this.connectionTitle()}\nRouting: ${this.runMode}\nNode strategy: ${this.selectionModeTitle()}\nDNS: ${this.dnsPresetDisplayName(findDnsPreset(this.dnsPresetId))}\nCore: ${this.coreInfo.version || 'Unknown'}`))
              .fontSize(13)
              .lineHeight(22)
              .fontColor(this.palette().textSecondary)
              .width('100%')
              .margin({ top: 12 })
            Row() {
              Column() {
                Text(this.t('累计上传', 'Uploaded'))
                  .fontSize(11)
                  .fontColor(this.palette().textTertiary)
                Text(this.localizedRuntimeText(this.uploadSpeed))
                  .fontSize(APP_TYPOGRAPHY.metric)
                  .fontColor(this.palette().warning)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 5 })
                Text(this.uploadRate)
                  .fontSize(10)
                  .fontColor(this.palette().warning)
                  .margin({ top: 3 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Column() {
                Text(this.t('累计下载', 'Downloaded'))
                  .fontSize(11)
                  .fontColor(this.palette().textTertiary)
                Text(this.localizedRuntimeText(this.downloadSpeed))
                  .fontSize(APP_TYPOGRAPHY.metric)
                  .fontColor(this.palette().blue)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 5 })
                Text(this.downloadRate)
                  .fontSize(10)
                  .fontColor(this.palette().blue)
                  .margin({ top: 3 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Column() {
                Text(this.t('活跃连接', 'Active'))
                  .fontSize(11)
                  .fontColor(this.palette().textTertiary)
                Text(`${this.activeConnections}`)
                  .fontSize(APP_TYPOGRAPHY.metric)
                  .fontColor(this.palette().accent)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 5 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .margin({ top: 20 })
            Text(this.t('这里只显示 VPN Extension / sing-box 返回的真实运行数据；已连接但尚无流量时会如实显示 0 B。',
              'Only live data reported by the VPN Extension and sing-box is shown. A connected but idle tunnel correctly shows 0 B.'))
              .fontSize(11)
              .lineHeight(18)
              .fontColor(this.palette().textTertiary)
              .width('100%')
              .margin({ top: 14 })
          }
          .width('100%')
          .padding(20)
          .backgroundColor(this.palette().surface)
          .borderRadius(22)
          .margin({ top: 14 })
        } else if (this.activitySection === 'rules') {
          Row() {
            Column() {
              Text(this.t(`解析规则预览 · ${this.activeRecord() ? (this.activeRecord() as SubscriptionRecord).bundle.rules.length : 0}`,
                `Parsed rules · ${this.activeRecord() ? (this.activeRecord() as SubscriptionRecord).bundle.rules.length : 0}`))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette().textPrimary)
              Text(this.t('仅预览订阅解析结果，不是实时规则命中日志；最多显示前 200 条',
                'Subscription parse preview, not a live match log. Shows at most 200 rules.'))
                .fontSize(10)
                .fontColor(this.palette().textTertiary)
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .margin({ top: 18 })
          if (this.subscriptionRuleBlockerCount() > 0) {
            Text(this.t(`当前订阅有 ${this.subscriptionRuleBlockerCount()} 条未完整支持或未接通的规则；“规则”模式会阻止启动，不会静默忽略。`,
              `This profile has ${this.subscriptionRuleBlockerCount()} unsupported or unresolved rules. Rule mode is blocked instead of silently ignoring them.`))
              .fontSize(10)
              .lineHeight(17)
              .fontColor(this.palette().warning)
              .width('100%')
              .padding(12)
              .backgroundColor(this.palette().warningSoft)
              .borderRadius(11)
              .margin({ top: 10 })
          }
          if (this.visibleRules().length === 0) {
            Text(this.t('当前订阅没有可展示的规则。全局代理与直连模式仍可使用。',
              'This subscription has no displayable rules. Global and Direct modes remain available.'))
              .fontSize(12)
              .lineHeight(19)
              .fontColor(this.palette().textTertiary)
              .width('100%')
              .padding(18)
              .backgroundColor(this.palette().surface)
              .borderRadius(14)
              .margin({ top: 10 })
          } else {
            ForEach(this.visibleRules(), (rule: RoutingRule, index: number) => {
              this.ruleRow(rule, index)
            }, (rule: RoutingRule, index: number) => `${index}-${rule.kind}-${rule.value}-${rule.target}`)
          }
        } else {
          Column() {
            Row() {
              Column() {
                Text(this.t('出口 IP（联网检测）', 'Egress IP (online check)'))
                  .fontSize(APP_TYPOGRAPHY.cardTitle)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.palette().textPrimary)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.maskedEgressIp())
                  .fontSize(APP_TYPOGRAPHY.body)
                  .fontColor(this.palette().accent)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 6 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Button(this.revealEgressIp ? this.t('隐藏 IP', 'Hide IP') : this.t('显示 IP', 'Show IP'))
                .height(44)
                .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
                .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
                  minFontSize: APP_TYPOGRAPHY.controlMin,
                  maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
                  heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
                .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
                .fontColor(this.egressInfo.ip.length > 0 ? this.palette().textSecondary : this.palette().textDisabled)
                .backgroundColor(this.egressInfo.ip.length > 0 ? this.palette().surfaceElevated : this.palette().surfaceMuted)
                .borderRadius(9)
                .enabled(this.egressInfo.ip.length > 0)
                .onClick(() => {
                  this.revealEgressIp = !this.revealEgressIp
                })
              Button(this.isTestingEgress ? this.t('检测中…', 'Checking…') : this.t('刷新', 'Refresh'))
                .height(44)
                .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
                .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
                  minFontSize: APP_TYPOGRAPHY.controlMin,
                  maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
                  heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
                .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
                .fontColor(this.connectionPhase === 'connected' && !this.isTestingEgress ?
                  this.palette().accentForeground : this.palette().textDisabled)
                .backgroundColor(this.connectionPhase === 'connected' && !this.isTestingEgress ? this.palette().accent : this.palette().surfaceMuted)
                .borderRadius(9)
                .margin({ left: 7 })
                .enabled(this.connectionPhase === 'connected' && !this.isTestingEgress)
                .onClick(() => this.probeEgressInfo())
            }
            .width('100%')
            if (this.egressInfo.ip.length > 0) {
              Text(this.t(`国家/地区：${this.egressInfo.countryCode || '未知'} · Cloudflare 节点：${this.egressInfo.dataCenter || '未知'}`,
                `Country/region: ${this.egressInfo.countryCode || 'Unknown'} · Cloudflare colo: ${this.egressInfo.dataCenter || 'Unknown'}`))
                .fontSize(10)
                .fontColor(this.palette().textTertiary)
                .width('100%')
                .margin({ top: 10 })
            }
            Text(this.t('检测会访问 Cloudflare HTTPS trace 服务；默认遮蔽完整 IP，不写入日志或订阅文件。',
              'Uses Cloudflare HTTPS trace. The full IP is masked by default and never written to logs or profiles.'))
              .fontSize(10)
              .lineHeight(16)
              .fontColor(this.palette().textTertiary)
              .width('100%')
              .margin({ top: 8 })
          }
          .width('100%')
          .padding(16)
          .backgroundColor(this.palette().surface)
          .borderRadius(14)
          .margin({ top: 14 })

          Row() {
            Column() {
                Text(this.t('当前网络网站可用性', 'Website availability'))
                .fontSize(APP_TYPOGRAPHY.sectionTitle)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette().textPrimary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.t('真实 HTTPS 请求；不把“能打开”伪装成会员或地区内容已解锁',
                'Real HTTPS requests. Reachability does not claim subscription or regional unlock.'))
                .fontSize(10)
                .fontColor(this.palette().textTertiary)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Button(this.isTestingWebsites ? this.t('测试中…', 'Testing…') : this.t('全部测试', 'Test all'))
              .height(44)
              .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
              .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
                minFontSize: APP_TYPOGRAPHY.controlMin,
                maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
                heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
              .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
              .fontColor(this.connectionPhase === 'connected' && !this.isTestingWebsites ?
                this.palette().accentForeground : this.palette().textDisabled)
              .backgroundColor(this.connectionPhase === 'connected' && !this.isTestingWebsites ? this.palette().accent : this.palette().surfaceMuted)
              .borderRadius(10)
              .enabled(this.connectionPhase === 'connected' && !this.isTestingWebsites)
              .onClick(() => this.runAllWebsiteTests())
          }
          .width('100%')
          .margin({ top: 18, bottom: 4 })
          ForEach(WEBSITE_TEST_TARGETS, (target: WebsiteTestTarget, index: number) => {
            if (index % 2 === 0) {
              Row() {
                this.websiteTestCard(target)
                if (index + 1 < WEBSITE_TEST_TARGETS.length) {
                  this.websiteTestCard(WEBSITE_TEST_TARGETS[index + 1])
                } else {
                  Blank()
                    .layoutWeight(1)
                }
              }
              .width('100%')
              .margin({ top: 8 })
            }
          }, (target: WebsiteTestTarget) => target.id)
          Text(this.t('检测值只表示当前网络路径的实际响应，不单独证明流量已通过所选代理。Google 和 YouTube 仅 HTTP 204 判为正常；ChatGPT 先检查轻量入口，再严格检查主页，403/429/451 不计为成功。DNS、TCP、超时、TLS 和读写错误仅显示安全分类与数字代码。最终验收还需核对连接前后出口变化、核心流量和真实页面。',
            'Results reflect the current network path only. Google and YouTube pass only on HTTP 204. ChatGPT checks a lightweight endpoint, then validates the home page strictly; 403/429/451 is not success. DNS, TCP, timeout, TLS and I/O failures show only a safe category and numeric code. Final acceptance also checks egress changes, core traffic and real pages.'))
            .fontSize(10)
            .lineHeight(17)
            .fontColor(this.palette().textTertiary)
            .width('100%')
            .padding(13)
            .backgroundColor(this.palette().surfaceMuted)
            .borderRadius(12)
            .margin({ top: 12 })
        }

          Blank()
            .height(24)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  languageChoiceButton(preference: UiLanguagePreference) {
    Button(this.languagePreferenceUiLabel(preference))
      .height(44)
      .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
      .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
        minFontSize: APP_TYPOGRAPHY.controlMin,
        maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
        heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
      .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
      .fontWeight(this.languagePreference === preference ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.languagePreference === preference ? this.palette().accentForeground : this.palette().textSecondary)
      .backgroundColor(this.languagePreference === preference ? this.palette().accent : this.palette().surfaceElevated)
      .border({ width: 1, color: this.languagePreference === preference ? this.palette().accent : this.palette().border })
      .borderRadius(12)
      .layoutWeight(1)
      .margin({ left: preference === 'system' ? 0 : (this.isCompactLayout() ? 4 : 7) })
      .accessibilityText(this.languagePreferenceUiLabel(preference))
      .accessibilityDescription(this.t('切换界面语言', 'Change interface language'))
      .onClick(() => this.selectLanguagePreference(preference))
  }

  @Builder
  themeChoiceButton(preference: UiThemePreference) {
    Button(this.themePreferenceUiLabel(preference))
      .height(44)
      .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
      .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
        minFontSize: APP_TYPOGRAPHY.controlMin,
        maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
        heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
      .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
      .fontWeight(this.themePreference === preference ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.themePreference === preference ? this.palette().accentForeground : this.palette().textSecondary)
      .backgroundColor(this.themePreference === preference ? this.palette().accent : this.palette().surfaceElevated)
      .border({ width: 1, color: this.themePreference === preference ? this.palette().accent : this.palette().border })
      .borderRadius(12)
      .layoutWeight(1)
      .margin({ left: preference === 'system' ? 0 : (this.isCompactLayout() ? 4 : 7) })
      .accessibilityText(this.themePreferenceUiLabel(preference))
      .accessibilityDescription(this.t('切换界面主题', 'Change interface theme'))
      .onClick(() => this.selectThemePreference(preference))
  }

  @Builder
  complianceDetailCard(kind: string) {
    Column() {
      Text(kind === 'privacy' ? this.t('隐私与数据详情', 'Privacy & data details') :
        this.t('开源许可详情', 'Open-source license details'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().textPrimary)
        .width('100%')
      Text(kind === 'privacy' ? this.privacyDetails() : this.licenseDetails())
        .fontSize(11)
        .lineHeight(19)
        .fontColor(this.palette().textSecondary)
        .width('100%')
        .margin({ top: 10 })
      if (kind === 'licenses') {
        Row() {
          Button(this.t('GNU GPL v3 全文', 'Full GNU GPL v3'))
            .height(44)
            .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
            .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
              minFontSize: APP_TYPOGRAPHY.controlMin,
              maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
              heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
            .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
            .fontColor(this.palette().accent)
            .backgroundColor(this.palette().accentSoft)
            .borderRadius(10)
            .layoutWeight(1)
            .accessibilityText(this.t('阅读 GNU GPL 第三版完整许可文本', 'Read the complete GNU GPL version 3'))
            .onClick(() => {
              this.settingsDetail = 'gpl'
            })
          Button(this.t('第三方声明', 'Third-party notices'))
            .height(44)
            .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
            .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
              minFontSize: APP_TYPOGRAPHY.controlMin,
              maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
              heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
            .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
            .fontColor(this.palette().accent)
            .backgroundColor(this.palette().accentSoft)
            .borderRadius(10)
            .layoutWeight(1)
            .margin({ left: 8 })
            .accessibilityText(this.t('阅读第三方组件和 sing-box 许可声明',
              'Read third-party component and sing-box license notices'))
            .onClick(() => {
              this.settingsDetail = 'notices'
            })
        }
        .width('100%')
        .margin({ top: 14 })
      }
      if (kind === 'privacy') {
        Text(this.connectionPhase === 'idle' ?
          this.t('VPN 已确认断开，可以执行本地清除。', 'VPN is confirmed disconnected. Local data can be cleared.') :
          this.t('请先安全断开 VPN；运行态未确认时不会删除任何数据。',
            'Safely disconnect VPN first. No data is deleted while runtime state is unconfirmed.'))
          .fontSize(10)
          .lineHeight(17)
          .fontColor(this.connectionPhase === 'idle' ? this.palette().accent : this.palette().warning)
          .width('100%')
          .padding(12)
          .backgroundColor(this.connectionPhase === 'idle' ? this.palette().accentSoft : this.palette().warningSoft)
          .borderRadius(10)
          .margin({ top: 14 })
        Button(this.clearingSensitiveData ? this.t('正在清除…', 'Clearing…') :
          this.t('清除本地敏感数据', 'Clear local sensitive data'))
          .width('100%')
          .height(48)
          .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
          .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
            minFontSize: APP_TYPOGRAPHY.controlMin,
            maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
            heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
          .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.connectionPhase === 'idle' && !this.clearingSensitiveData ?
            this.palette().danger : this.palette().textDisabled)
          .backgroundColor(this.connectionPhase === 'idle' && !this.clearingSensitiveData ?
            this.palette().dangerSoft : this.palette().surfaceMuted)
          .borderRadius(12)
          .margin({ top: 12 })
          .enabled(this.connectionPhase === 'idle' && !this.clearingSensitiveData &&
            !this.isConnectionBusy() && !this.configurationBusy)
          .accessibilityText(this.t('清除本地敏感数据', 'Clear local sensitive data'))
          .accessibilityDescription(this.t('需要两次确认，且只在 VPN 已确认断开时执行',
            'Requires two confirmations and runs only while VPN is confirmed disconnected'))
          .onClick(() => this.confirmClearSensitiveData())
      }
      Button(this.t('收起详情', 'Close details'))
        .width('100%')
        .height(44)
        .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
        .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
          minFontSize: APP_TYPOGRAPHY.controlMin,
          maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
          heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
        .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
        .fontColor(this.palette().textSecondary)
        .backgroundColor(this.palette().surfaceElevated)
        .borderRadius(11)
        .margin({ top: 12 })
        .accessibilityText(this.t('收起详情', 'Close details'))
        .onClick(() => {
          this.settingsDetail = ''
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.palette().surfaceMuted)
    .border({ width: 1, color: this.palette().border })
    .borderRadius(14)
    .margin({ top: 10 })
    .accessibilityGroup(true)
  }

  @Builder
  localLegalTextCard(kind: string) {
    Column() {
      Text(this.localLegalTitle(kind))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().textPrimary)
        .width('100%')
      Text(this.localLegalBody(kind))
        .fontSize(10)
        .lineHeight(17)
        .fontColor(this.palette().textSecondary)
        .width('100%')
        .margin({ top: 10 })
      Button(this.t('返回合规摘要', 'Back to compliance summary'))
        .width('100%')
        .height(44)
        .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
        .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
          minFontSize: APP_TYPOGRAPHY.controlMin,
          maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
          heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
        .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
        .fontColor(this.palette().accent)
        .backgroundColor(this.palette().accentSoft)
        .borderRadius(11)
        .margin({ top: 14 })
        .onClick(() => {
          this.settingsDetail = ''
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.palette().surfaceMuted)
    .border({ width: 1, color: this.palette().border })
    .borderRadius(14)
    .margin({ top: 10 })
  }

  @Builder
  privacyOnboarding() {
    Scroll() {
      Column() {
        Text('HARMONY NET')
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().accent)
          .letterSpacing(1.2)
          .width('100%')
        Text(this.t('开始前的隐私选择', 'Privacy choice before you start'))
          .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.displayCompact : APP_TYPOGRAPHY.display)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 8 })
        Text(this.t('请先了解哪些数据留在设备、哪些操作会访问第三方端点。不同意仍可进入离线受限模式。',
          'Review what stays on device and which actions contact third-party endpoints. You can decline and continue in offline limited mode.'))
          .fontSize(12)
          .lineHeight(19)
          .fontColor(this.palette().textSecondary)
          .width('100%')
          .margin({ top: 8 })
        Column() {
          Text(this.t('本机处理与加密', 'On-device processing & encryption'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().textPrimary)
            .width('100%')
          Text(this.t('订阅地址、节点和凭据在设备上解析；订阅目录与静态运行配置使用 HUKS AES-256-GCM 加密并保存在应用私有目录。无账号、广告、分析 SDK 或自营遥测。',
            'Subscription URLs, nodes and credentials are parsed on device. The catalog and static runtime configuration use HUKS AES-256-GCM in the private app sandbox. No account, ads, analytics SDK or first-party telemetry.'))
            .fontSize(11)
            .lineHeight(18)
            .fontColor(this.palette().textSecondary)
            .width('100%')
            .margin({ top: 8 })
          Text(this.t('按需访问的第三方', 'Third parties contacted on request'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().textPrimary)
            .width('100%')
            .margin({ top: 18 })
          Text(this.t('更新订阅访问你填写的 HTTPS 主机；连接访问所选 DoH/DoT；诊断可访问 Apple、GitHub、Google、YouTube、ChatGPT、Claude、Netflix、Disney+、TikTok 和 Cloudflare trace。',
            'Profile updates contact the HTTPS host you enter; VPN uses the selected DoH/DoT; diagnostics may contact Apple, GitHub, Google, YouTube, ChatGPT, Claude, Netflix, Disney+, TikTok and Cloudflare trace.'))
            .fontSize(11)
            .lineHeight(18)
            .fontColor(this.palette().textSecondary)
            .width('100%')
            .margin({ top: 8 })
        }
        .width('100%')
        .padding(18)
        .backgroundColor(this.palette().surface)
        .border({ width: 1, color: this.palette().border })
        .borderRadius(22)
        .margin({ top: 20 })
        if (this.settingsDetail === 'privacy') {
          this.localLegalTextCard('privacy')
        } else if (this.settingsDetail === 'agreement') {
          this.localLegalTextCard('agreement')
        } else {
          Row() {
            Button(this.t('隐私详情', 'Privacy details'))
              .height(44)
              .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
              .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
                minFontSize: APP_TYPOGRAPHY.controlMin,
                maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
                heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
              .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
              .fontColor(this.palette().accent)
              .backgroundColor(this.palette().accentSoft)
              .borderRadius(10)
              .layoutWeight(1)
              .onClick(() => {
                this.settingsDetail = 'privacy'
              })
            Button(this.t('用户协议', 'User agreement'))
              .height(44)
              .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
              .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
                minFontSize: APP_TYPOGRAPHY.controlMin,
                maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
                heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
              .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
              .fontColor(this.palette().accent)
              .backgroundColor(this.palette().accentSoft)
              .borderRadius(10)
              .layoutWeight(1)
              .margin({ left: 8 })
              .onClick(() => {
                this.settingsDetail = 'agreement'
              })
          }
          .width('100%')
          .margin({ top: 12 })
        }
        Text(this.t('选择“同意并继续”会启用订阅联网、VPN 和诊断功能。你可以在设置中撤回；撤回不自动删除已有数据。',
          'Agree & continue enables profile network access, VPN and diagnostics. You can withdraw in Settings; withdrawal does not automatically delete existing data.'))
          .fontSize(10)
          .lineHeight(17)
          .fontColor(this.palette().textTertiary)
          .width('100%')
          .margin({ top: 16 })
        Button(this.t('同意并继续', 'Agree & continue'))
          .width('100%')
          .height(50)
          .fontSize(APP_TYPOGRAPHY.control)
          .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
            minFontSize: APP_TYPOGRAPHY.controlMin, maxFontSize: APP_TYPOGRAPHY.control,
            heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
          .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().accentForeground)
          .backgroundColor(this.palette().accent)
          .borderRadius(13)
          .margin({ top: 14 })
          .accessibilityDescription(this.t('启用订阅、VPN 和联网诊断',
            'Enable subscriptions, VPN and network diagnostics'))
          .onClick(() => this.savePrivacyConsent('accepted'))
        Button(this.t('不同意，仅离线浏览', 'Decline · Offline mode'))
          .width('100%')
          .height(48)
          .fontSize(APP_TYPOGRAPHY.control)
          .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
            minFontSize: APP_TYPOGRAPHY.controlMin, maxFontSize: APP_TYPOGRAPHY.control,
            heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
          .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
          .fontColor(this.palette().textSecondary)
          .backgroundColor(this.palette().surfaceElevated)
          .border({ width: 1, color: this.palette().border })
          .borderRadius(13)
          .margin({ top: 10, bottom: 112 })
          .accessibilityDescription(this.t('进入离线受限模式，不启用订阅联网、VPN 或联网诊断',
            'Enter offline limited mode without profile network access, VPN or network diagnostics'))
          .enabled(!this.settingsLoading && !this.isConnectionBusy())
          .onClick(() => this.declinePrivacyConsent())
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 28 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  appearanceSkeleton() {
    Column() {
      Row() {
        Column() {
          Row()
            .width(88)
            .height(9)
            .backgroundColor(this.palette().surfaceElevated)
            .borderRadius(5)
          Row()
            .width(166)
            .height(24)
            .backgroundColor(this.palette().surfaceElevated)
            .borderRadius(8)
            .margin({ top: 8 })
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
        Row()
          .width(66)
          .height(30)
          .backgroundColor(this.palette().surfaceElevated)
          .borderRadius(15)
      }
      .width('100%')
      .height(78)
      .padding({ left: 18, right: 18, top: 16 })
      Column() {
        Row()
          .width('100%')
          .height(156)
          .backgroundColor(this.palette().surface)
          .borderRadius(24)
        Row()
          .width('100%')
          .height(96)
          .backgroundColor(this.palette().surface)
          .borderRadius(22)
          .margin({ top: 14 })
        Row()
          .width('100%')
          .height(190)
          .backgroundColor(this.palette().surface)
          .borderRadius(22)
          .margin({ top: 14 })
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 })
      Row()
        .width('100%')
        .height(68)
        .backgroundColor(this.palette().navigation)
    }
    .width('100%')
    .height('100%')
    .accessibilityText(this.t('正在载入界面偏好', 'Loading interface preferences'))
  }

  @Builder
  releaseValueRow(field: string, value: string, valid: boolean) {
    Row() {
      Column() {
        Text(this.releaseFieldUiLabel(field))
          .fontSize(11)
          .fontColor(this.palette().textSecondary)
          .width('100%')
        Text(valid ? value.trim() : this.releaseBlockedText(value))
          .fontSize(10)
          .lineHeight(16)
          .fontColor(valid ? this.palette().textPrimary : this.palette().warning)
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .border({ width: { bottom: 1 }, color: this.palette().border })
    .accessibilityText(`${this.releaseFieldUiLabel(field)}：${valid ? value.trim() : this.releaseBlockedText(value)}`)
  }

  @Builder
  releaseLinkRow(field: string, url: string) {
    Row() {
      Column() {
        Text(this.releaseFieldUiLabel(field))
          .fontSize(11)
          .fontColor(this.palette().textSecondary)
          .width('100%')
        Text(this.isReleaseHttps(url) ? url.trim() : this.releaseBlockedText(url))
          .fontSize(10)
          .lineHeight(16)
          .fontColor(this.isReleaseHttps(url) ? this.palette().textPrimary : this.palette().warning)
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.isReleaseHttps(url)) {
        Button(this.t('打开', 'Open'))
          .height(44)
          .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
          .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
            minFontSize: APP_TYPOGRAPHY.controlMin,
            maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
            heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
          .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
          .fontColor(this.palette().accent)
          .backgroundColor(this.palette().accentSoft)
          .borderRadius(10)
          .margin({ left: 10 })
          .accessibilityText(this.t(`打开${this.releaseFieldUiLabel(field)}`,
            `Open ${this.releaseFieldUiLabel(field)}`))
          .accessibilityDescription(url.trim())
          .onClick(() => this.openReleaseLink(url))
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .border({ width: { bottom: 1 }, color: this.palette().border })
  }

  private settingsStatusLabel(field: string): string {
    if (field === 'platform') return this.t('开发目标', 'Platform target')
    if (field === 'vpnBaseline') return this.t('VPN 功能基线', 'VPN feature baseline')
    if (field === 'core') return this.t('代理核心库', 'Proxy core')
    if (field === 'ipv6') return this.t('IPv6 接管', 'IPv6 handling')
    if (field === 'consumerMode') return this.t('消费版模式', 'Consumer app mode')
    if (field === 'trafficScope') return this.t('接管范围', 'Traffic scope')
    if (field === 'strategy') return this.t('节点策略', 'Node strategy')
    return this.t('系统全局 HTTP 代理', 'System-wide HTTP proxy')
  }

  private trafficScopeValue(): string {
    const scope: string = this.applicationMode === 'allowlist' ?
      this.t(`${this.trustedApplications.length} 个所选应用`,
        `${this.trustedApplications.length} selected apps`) :
      this.t('全部应用', 'All apps')
    if (this.ipv6Enabled) {
      return this.connectionPhase === 'connected' ?
        this.t(`${scope} · IPv4 + IPv6`, `${scope} · IPv4 + IPv6`) :
        this.t(`${scope} · 连接时接管双栈`, `${scope} · dual stack on connect`)
    }
    return this.connectionPhase === 'connected' ?
      this.t(`${scope} · IPv4 代理 · IPv6 阻断`, `${scope} · IPv4 proxied · IPv6 blocked`) :
      this.t(`${scope} · 连接时接管并拒绝 IPv6`, `${scope} · capture and reject IPv6 on connect`)
  }

  private settingsStatusValue(field: string): string {
    if (field === 'platform') return 'HarmonyOS 6.0.2+ · API 22+'
    if (field === 'vpnBaseline') return 'API 22+'
    if (field === 'core') return this.coreInfo.version
    if (field === 'ipv6') return this.ipv6RuntimeLabel()
    if (field === 'consumerMode') return this.t('系统 VPN / TUN', 'System VPN / TUN')
    if (field === 'trafficScope') return this.trafficScopeValue()
    if (field === 'strategy') return this.selectionModeTitle()
    return this.t('消费版不可设置', 'Unavailable to consumer apps')
  }

  private settingsStatusColor(field: string): string {
    if (field === 'core') return this.coreInfo.available ? this.palette().accent : this.palette().warning
    if (field === 'ipv6') return this.connectionPhase === 'connected' ? this.palette().accent : this.palette().warning
    if (field === 'consumerMode' || field === 'strategy') return this.palette().accent
    if (field === 'systemProxy') return this.palette().warning
    return this.palette().textPrimary
  }

  @Builder
  settingsStatusRow(field: string, topMargin: number) {
    if (this.isCompactLayout()) {
      Column() {
        Text(this.settingsStatusLabel(field))
          .fontSize(12)
          .fontColor(this.palette().textSecondary)
          .width('100%')
        Text(this.settingsStatusValue(field))
          .fontSize(12)
          .lineHeight(18)
          .fontColor(this.settingsStatusColor(field))
          .width('100%')
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: topMargin })
    } else {
      Row() {
        Text(this.settingsStatusLabel(field))
          .fontSize(field === 'platform' || field === 'vpnBaseline' || field === 'core' || field === 'ipv6' ? 14 : 13)
          .fontColor(this.palette().textSecondary)
        Blank()
        Text(this.settingsStatusValue(field))
          .fontSize(field === 'core' || field === 'consumerMode' || field === 'trafficScope' ||
            field === 'strategy' || field === 'systemProxy' ? 13 : 14)
          .fontColor(this.settingsStatusColor(field))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .margin({ top: topMargin })
    }
  }

  @Builder
  settingsPage() {
    Scroll() {
      Column() {
        Column() {
          Text(this.t('外观与语言', 'Appearance & language'))
            .fontSize(APP_TYPOGRAPHY.sectionTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().textPrimary)
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.t('偏好保存在本机；“系统”会随设备语言和深浅色变化。',
            'Preferences stay on this device. System follows device language and color mode.'))
            .fontSize(11)
            .lineHeight(18)
            .fontColor(this.palette().textTertiary)
            .width('100%')
            .margin({ top: 6 })
          Text(this.t('语言', 'Language'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().textSecondary)
            .width('100%')
            .margin({ top: 18, bottom: 8 })
          Row() {
            this.languageChoiceButton('system')
            this.languageChoiceButton('zh')
            this.languageChoiceButton('en')
          }
          .width('100%')
          Text(this.t('主题', 'Theme'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().textSecondary)
            .width('100%')
            .margin({ top: 18, bottom: 8 })
          Row() {
            this.themeChoiceButton('system')
            this.themeChoiceButton('light')
            this.themeChoiceButton('dark')
          }
          .width('100%')
        }
        .width('100%')
        .padding(18)
        .backgroundColor(this.palette().surface)
        .border({ width: 1, color: this.palette().border })
        .borderRadius(22)
        .shadow({ radius: 14, color: this.palette().shadow, offsetY: 6 })

        Text(this.t('隐私、数据与许可', 'PRIVACY, DATA & LICENSES'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .margin({ top: 22, bottom: 10 })
        Column() {
          Row() {
            Column() {
              Text(this.t('允许联网功能', 'Allow network features'))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette().textPrimary)
              Text(this.privacyConsent === 'accepted' ?
                this.t('订阅更新、VPN 和联网诊断已启用',
                  'Profile updates, VPN and network diagnostics are enabled') :
                this.t('当前为离线受限模式', 'Currently in offline limited mode'))
                .fontSize(10)
                .fontColor(this.privacyConsent === 'accepted' ? this.palette().accent : this.palette().warning)
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            this.networkConsentSwitch()
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 13, bottom: 13 })
          .backgroundColor(this.palette().surfaceMuted)
          .borderRadius(13)
          Text(this.privacyConsent === 'accepted' ?
            this.t('关闭前需先断开 VPN，并通过确认与运行状态复核。',
              'Turn off VPN first. Withdrawal requires confirmation and authoritative runtime verification.') :
            this.t('重新开启表示同意本页列出的按需联网用途。',
              'Turning this on again accepts the on-demand network uses described on this page.'))
            .fontSize(10)
            .lineHeight(16)
            .fontColor(this.palette().textTertiary)
            .width('100%')
            .margin({ top: 8, bottom: 16 })
          Row() {
            Column() {
              Text(this.t('隐私与数据', 'Privacy & data'))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette().textPrimary)
              Text(this.t('本地处理、HUKS 加密、联网端点与数据清除',
                'Local processing, HUKS encryption, network endpoints and data clearing'))
                .fontSize(10)
                .fontColor(this.palette().textTertiary)
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Button(this.settingsDetail === 'privacy' ? this.t('收起', 'Close') : this.t('详情', 'Details'))
              .height(44)
              .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
              .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
                minFontSize: APP_TYPOGRAPHY.controlMin,
                maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
                heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
              .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
              .fontColor(this.palette().accent)
              .backgroundColor(this.palette().accentSoft)
              .borderRadius(10)
              .accessibilityText(this.t('隐私与数据详情', 'Privacy and data details'))
              .onClick(() => {
                this.settingsDetail = this.settingsDetail === 'privacy' ? '' : 'privacy'
              })
          }
          .width('100%')
          if (this.settingsDetail === 'privacy') {
            this.complianceDetailCard('privacy')
          }
          Row() {
            Column() {
              Text(this.t('用户协议', 'User agreement'))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette().textPrimary)
              Text(this.t('使用责任、运行边界、数据与开源条款',
                'User responsibilities, runtime boundaries, data and open-source terms'))
                .fontSize(10)
                .fontColor(this.palette().textTertiary)
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Button(this.settingsDetail === 'agreement' ? this.t('收起', 'Close') : this.t('详情', 'Details'))
              .height(44)
              .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
              .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
                minFontSize: APP_TYPOGRAPHY.controlMin,
                maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
                heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
              .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
              .fontColor(this.palette().accent)
              .backgroundColor(this.palette().accentSoft)
              .borderRadius(10)
              .accessibilityText(this.t('本地用户协议', 'Local user agreement'))
              .onClick(() => {
                this.settingsDetail = this.settingsDetail === 'agreement' ? '' : 'agreement'
              })
          }
          .width('100%')
          .margin({ top: 16 })
          if (this.settingsDetail === 'agreement') {
            this.localLegalTextCard('agreement')
          }
          Row() {
            Column() {
              Text(this.t('开源许可', 'Open-source licenses'))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette().textPrimary)
              Text(this.t('GPL、第三方组件、对应源码与非官方关联声明',
                'GPL, third-party components, corresponding source and non-affiliation'))
                .fontSize(10)
                .fontColor(this.palette().textTertiary)
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Button(this.settingsDetail === 'licenses' ? this.t('收起', 'Close') : this.t('详情', 'Details'))
              .height(44)
              .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
              .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
                minFontSize: APP_TYPOGRAPHY.controlMin,
                maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
                heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
              .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
              .fontColor(this.palette().accent)
              .backgroundColor(this.palette().accentSoft)
              .borderRadius(10)
              .accessibilityText(this.t('开源许可详情', 'Open-source license details'))
              .onClick(() => {
                this.settingsDetail = this.settingsDetail === 'licenses' ? '' : 'licenses'
              })
          }
          .width('100%')
          .margin({ top: 16 })
          if (this.settingsDetail === 'licenses') {
            this.complianceDetailCard('licenses')
          }
          if (this.settingsDetail === 'gpl') {
            this.localLegalTextCard('gpl')
          } else if (this.settingsDetail === 'notices') {
            this.localLegalTextCard('notices')
          }
          Text(this.t('公开发布信息', 'Public release information'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().textPrimary)
            .width('100%')
            .margin({ top: 18 })
          Text(this.releasePublicInfoReady() ?
            this.t('正式发布信息已配置；链接来自本次签名构建。',
              'Release information is configured. Links come from this signed build.') :
            this.t('当前开发构建未配置完整公开信息，正式发布保持阻塞；不会显示虚假链接或无效入口。',
              'This development build lacks complete public information. Release remains blocked; no fabricated links or inactive entries are shown.'))
            .fontSize(10)
            .lineHeight(17)
            .fontColor(this.releasePublicInfoReady() ? this.palette().accent : this.palette().warning)
            .width('100%')
            .padding(12)
            .backgroundColor(this.releasePublicInfoReady() ? this.palette().accentSoft : this.palette().warningSoft)
            .borderRadius(10)
            .margin({ top: 8 })
          this.releaseValueRow('operator', RELEASE_PUBLIC_INFO.operatorName,
            RELEASE_PUBLIC_INFO.operatorName.trim().length > 0)
          this.releaseLinkRow('privacy', this.isEnglish() ?
            RELEASE_PUBLIC_INFO.privacyUrlEn : RELEASE_PUBLIC_INFO.privacyUrl)
          this.releaseLinkRow('agreement', this.isEnglish() ?
            RELEASE_PUBLIC_INFO.userAgreementUrlEn : RELEASE_PUBLIC_INFO.userAgreementUrl)
          this.releaseLinkRow('support', RELEASE_PUBLIC_INFO.supportUrl)
          this.releaseValueRow('email', RELEASE_PUBLIC_INFO.supportEmail,
            this.isReleaseEmail(RELEASE_PUBLIC_INFO.supportEmail))
          this.releaseLinkRow('source', RELEASE_PUBLIC_INFO.correspondingSourceUrl)
        }
        .width('100%')
        .padding(18)
        .backgroundColor(this.palette().surface)
        .border({ width: 1, color: this.palette().border })
        .borderRadius(22)

        Column() {
          this.settingsStatusRow('platform', 0)
          this.settingsStatusRow('vpnBaseline', 18)
          this.settingsStatusRow('core', 18)
          this.settingsStatusRow('ipv6', 18)
        }
        .width('100%')
        .padding(18)
        .backgroundColor(this.palette().surface)
        .borderRadius(22)
        .border({ width: 1, color: this.palette().border })
        .margin({ top: 12 })

        Text(this.t('流量接管方式', 'TRAFFIC HANDLING'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .margin({ top: 22 })
        Column() {
          Row() {
            Column() {
              Text('VPN / TUN')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.connectionPhase === 'connected' ? this.palette().accentForeground : this.palette().textPrimary)
              Text(this.tunRuntimeLabel())
                .fontSize(9)
                .fontColor(this.connectionPhase === 'connected' ? this.palette().accentForeground : this.palette().warning)
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .height(62)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor(this.connectionPhase === 'connected' ? this.palette().accent : this.palette().surfaceElevated)
            .borderRadius(12)
            Column() {
              Text(this.t('系统代理', 'System proxy'))
                .fontSize(14)
                .fontColor(this.palette().textSecondary)
              Text(this.t('平台权限受限', 'Platform restricted'))
                .fontSize(9)
                .fontColor(this.palette().textDisabled)
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .height(62)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor(this.palette().surfaceElevated)
            .borderRadius(12)
            .margin({ left: 8 })
          }
          .width('100%')

          this.settingsStatusRow('consumerMode', 16)
          this.settingsStatusRow('trafficScope', 16)
          if (this.isCompactLayout()) {
            Column() {
              Text('IPv6')
                .fontSize(12)
                .fontColor(this.palette().textSecondary)
                .width('100%')
              Text(this.t('连接中修改会先安全停止，再按新 TUN 与系统路由自动重连',
                'Changing while connected safely stops and reconnects with new TUN routes'))
                .fontSize(9)
                .lineHeight(15)
                .fontColor(this.palette().textDisabled)
                .width('100%')
                .margin({ top: 3 })
              Text(this.t('请在首页设置', 'Configure on Home'))
                .fontSize(11)
                .fontColor(this.palette().textTertiary)
                .width('100%')
                .margin({ top: 5 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .margin({ top: 16 })
          } else {
            Row() {
              Column() {
                Text('IPv6')
                  .fontSize(13)
                  .fontColor(this.palette().textSecondary)
                  .width('100%')
                Text(this.t('连接中修改会先安全停止，再按新 TUN 与系统路由自动重连',
                  'Changing while connected safely stops and reconnects with new TUN routes'))
                  .fontSize(9)
                  .fontColor(this.palette().textDisabled)
                  .width('100%')
                  .margin({ top: 3 })
              }
              .layoutWeight(1)
              Text(this.t('请在首页设置', 'Configure on Home'))
                .fontSize(11)
                .fontColor(this.palette().textTertiary)
            }
            .width('100%')
            .margin({ top: 16 })
          }
          this.settingsStatusRow('strategy', 16)
          this.settingsStatusRow('systemProxy', 16)
          Text(this.t('HarmonyOS 普通消费应用没有修改系统全局代理的权限。本项目使用系统 VPN/TUN 接管流量；“全局代理”仅表示 TUN 内全部流量走当前节点，不伪造系统代理开关。',
            'HarmonyOS consumer apps cannot change the system-wide proxy. This app uses system VPN/TUN. Global means all TUN traffic uses the current node; no fake system proxy switch is shown.'))
            .fontSize(11)
            .lineHeight(18)
            .fontColor(this.palette().textTertiary)
            .width('100%')
            .margin({ top: 14 })
        }
        .width('100%')
        .padding(18)
        .backgroundColor(this.palette().surface)
        .borderRadius(22)
        .margin({ top: 10 })

        Row() {
          Text(this.t('应用接管白名单', 'APP TUNNEL ALLOWLIST'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().textPrimary)
          Blank()
          Text(`${this.trustedApplications.length} / ${MAX_TRUSTED_APPLICATIONS}`)
            .fontSize(10)
            .fontColor(this.palette().textTertiary)
        }
        .width('100%')
        .margin({ top: 22, bottom: 10 })
        Column() {
          Text(this.t('“仅所选应用”使用 HarmonyOS VPN 原生应用白名单。只有你选中的应用进入 TUN；其他应用直接使用系统网络，适合避免国内应用被代理链路影响。若希望所选应用的全部流量走节点，请同时选择“全局代理”；规则与直连模式仍按各自语义执行。',
            'Only selected apps mode uses the native HarmonyOS VPN allowlist. Selected apps enter TUN; every other app uses the system network directly. To send all selected-app traffic through the node, also choose Global proxy; Rule and Direct keep their own routing semantics.'))
            .fontSize(11)
            .lineHeight(18)
            .fontColor(this.palette().textSecondary)
            .width('100%')
          Row() {
            this.applicationModeButton('all')
            this.applicationModeButton('allowlist')
          }
          .width('100%')
          .margin({ top: 12 })
          Text(this.applicationMode === 'allowlist' ?
            this.t(`当前仅接管 ${this.trustedApplications.length} 个应用；未选择的应用不会进入 VPN。`,
              `Only ${this.trustedApplications.length} apps are tunneled. Unselected apps bypass VPN.`) :
            this.t('当前接管全部应用。已保存的白名单不会生效，直到切换为“仅所选应用”。',
              'All apps are tunneled. The saved allowlist applies only after switching to Only selected apps.'))
            .fontSize(10)
            .lineHeight(16)
            .fontColor(this.applicationMode === 'allowlist' ? this.palette().accent : this.palette().textTertiary)
            .width('100%')
            .margin({ top: 9 })
          Row() {
            Text(this.t('已选择应用', 'Selected apps'))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().textPrimary)
            Blank()
            Button(this.applicationEditorOpen ? this.t('收起', 'Close') : this.t('管理应用', 'Manage'))
              .height(44)
              .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
              .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
                minFontSize: APP_TYPOGRAPHY.controlMin,
                maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
                heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
              .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
              .fontColor(this.palette().accent)
              .backgroundColor(this.palette().accentSoft)
              .borderRadius(10)
              .enabled(this.runtimeConfigurationEditable())
              .onClick(() => this.openApplicationEditor())
          }
          .width('100%')
          .margin({ top: 14 })
          if (this.trustedApplications.length === 0) {
            Text(this.t('尚未选择应用。先点击“管理应用”添加，再启用白名单模式。',
              'No apps selected. Add apps under Manage before enabling allowlist mode.'))
              .fontSize(10)
              .lineHeight(16)
              .fontColor(this.palette().textDisabled)
              .width('100%')
              .margin({ top: 6 })
          } else {
            ForEach(this.trustedApplications, (bundleName: string) => {
              this.trustedApplicationRow(bundleName)
            }, (bundleName: string) => bundleName)
          }
          if (this.applicationEditorOpen) {
            TextInput({
              placeholder: this.t('搜索应用名称或包名', 'Search app name or bundle'),
              text: this.applicationSearch
            })
              .height(46)
              .fontSize(12)
              .fontColor(this.palette().textPrimary)
              .placeholderColor(this.palette().placeholder)
              .backgroundColor(this.palette().background)
              .borderRadius(11)
              .padding({ left: 13, right: 13 })
              .margin({ top: 12 })
              .enabled(this.runtimeConfigurationEditable())
              .onChange((value: string) => {
                this.applicationSearch = value
              })
            if (this.applicationCatalogLoading) {
              Text(this.t('正在读取可启动应用…', 'Loading launchable apps…'))
                .fontSize(10)
                .fontColor(this.palette().textTertiary)
                .width('100%')
                .margin({ top: 9 })
            } else {
              ForEach(this.visibleApplicationCatalog(), (application: SelectableApplication) => {
                this.applicationSelectionRow(application)
              }, (application: SelectableApplication) => application.bundleName)
              if (this.visibleApplicationCatalog().length === 40) {
                Text(this.t('最多显示 40 项，请继续输入名称或包名缩小范围。',
                  'Showing up to 40 apps. Refine the name or bundle search.'))
                  .fontSize(9)
                  .fontColor(this.palette().textTertiary)
                  .width('100%')
                  .margin({ top: 8 })
              }
            }
            Text(this.t('列表不包含无桌面入口的应用时，可手动填写其 Bundle Name。',
              'For apps without a Home entry, enter the Bundle Name manually.'))
              .fontSize(10)
              .lineHeight(16)
              .fontColor(this.palette().textTertiary)
              .width('100%')
              .margin({ top: 12 })
            Row() {
              TextInput({
                placeholder: this.t('例如 com.example.application', 'e.g. com.example.application'),
                text: this.applicationBundleDraft
              })
                .height(46)
                .fontSize(11)
                .fontColor(this.palette().textPrimary)
                .placeholderColor(this.palette().placeholder)
                .backgroundColor(this.palette().background)
                .borderRadius(11)
                .padding({ left: 12, right: 12 })
                .layoutWeight(1)
                .enabled(this.runtimeConfigurationEditable())
                .onChange((value: string) => {
                  this.applicationBundleDraft = value
                  this.applicationMessage = ''
                })
              Button(this.t('添加', 'Add'))
                .width(72)
                .height(44)
                .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
                .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
                  minFontSize: APP_TYPOGRAPHY.controlMin,
                  maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
                  heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
                .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
                .fontColor(this.runtimeConfigurationEditable() ? this.palette().accentForeground : this.palette().textDisabled)
                .backgroundColor(this.runtimeConfigurationEditable() ? this.palette().accent : this.palette().surfaceMuted)
                .borderRadius(10)
                .margin({ left: 8 })
                .enabled(this.runtimeConfigurationEditable())
                .onClick(() => this.addApplicationBundle())
            }
            .width('100%')
            .margin({ top: 8 })
          }
          if (this.applicationMessage.length > 0) {
            Text(this.applicationMessage)
              .fontSize(10)
              .lineHeight(16)
              .fontColor(this.palette().textTertiary)
              .width('100%')
              .margin({ top: 9 })
          }
          Text(this.t('切换范围或修改正在生效的白名单时，已连接 VPN 会先安全停止，再使用新的 trustedApplications 创建 TUN 并自动重连。',
            'Changing the active scope safely stops VPN, recreates TUN with the new trustedApplications, and reconnects.'))
            .fontSize(9)
            .lineHeight(15)
            .fontColor(this.palette().warning)
            .width('100%')
            .margin({ top: 12 })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.palette().surface)
        .borderRadius(20)

        Row() {
          Text(this.t('本地规则', 'LOCAL RULES'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().textPrimary)
          Blank()
          Text(`${this.localRules.length} / ${MAX_LOCAL_ROUTING_RULES}`)
            .fontSize(10)
            .fontColor(this.palette().textTertiary)
        }
        .width('100%')
        .margin({ top: 22, bottom: 10 })
        Column() {
          Text(this.t('本地规则优先于订阅规则，仅在“规则”路由模式下应用。订阅规则仍由订阅提供并在诊断页只读展示。',
            'Local rules take priority over subscription rules and apply only in Rule mode. Imported rules remain read-only under Diagnostics.'))
            .fontSize(10)
            .lineHeight(17)
            .fontColor(this.palette().textTertiary)
            .width('100%')
          Row() {
            this.localRuleKindButton('domain')
            this.localRuleKindButton('domain_suffix')
            this.localRuleKindButton('ip_cidr')
          }
          .width('100%')
          .margin({ top: 12 })
          TextInput({
            placeholder: this.localRuleKind === 'ip_cidr' ?
              this.t('例如 192.0.2.0/24', 'e.g. 192.0.2.0/24') :
              this.t('例如 example.com', 'e.g. example.com'),
            text: this.localRuleDraft
          })
            .height(46)
            .fontSize(12)
            .fontColor(this.palette().textPrimary)
            .placeholderColor(this.palette().placeholder)
            .backgroundColor(this.palette().background)
            .borderRadius(11)
            .padding({ left: 13, right: 13 })
            .margin({ top: 10 })
            .enabled(this.runtimeConfigurationEditable())
            .onChange((value: string) => {
              this.localRuleDraft = value
              this.localRuleMessage = ''
            })
          Row() {
            this.localRuleTargetButton('proxy')
            this.localRuleTargetButton('direct')
            this.localRuleTargetButton('reject')
          }
          .width('100%')
          .margin({ top: 10 })
          Button(this.t('新增规则', 'Add rule'))
            .width('100%')
            .height(44)
            .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
            .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
              minFontSize: APP_TYPOGRAPHY.controlMin,
              maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
              heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
            .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
            .fontColor(this.runtimeConfigurationEditable() ? this.palette().accentForeground : this.palette().textDisabled)
            .backgroundColor(this.runtimeConfigurationEditable() ? this.palette().accent : this.palette().surfaceMuted)
            .borderRadius(11)
            .margin({ top: 10 })
            .enabled(this.runtimeConfigurationEditable() && this.localRules.length < MAX_LOCAL_ROUTING_RULES)
            .onClick(() => this.addLocalRule())
          if (this.localRuleMessage.length > 0) {
            Text(this.localizedRuntimeText(this.localRuleMessage))
              .fontSize(10)
              .lineHeight(16)
              .fontColor(this.palette().textTertiary)
              .width('100%')
              .margin({ top: 8 })
          }
          if (this.localRules.length === 0) {
            Text(this.t('尚未添加本地规则', 'No local rules yet'))
              .fontSize(11)
              .fontColor(this.palette().textDisabled)
              .width('100%')
              .margin({ top: 12 })
          } else {
            ForEach(this.localRules, (rule: RoutingRule, index: number) => {
              this.localRuleRow(rule, index)
            }, (rule: RoutingRule, index: number) => `${index}-${rule.kind}-${rule.value}-${rule.target}`)
          }
          Text(this.t('当前不提供进程、GeoIP、远程规则集/provider 或关键字规则编辑；这些语义未完整接通前不会显示空壳入口。订阅含不支持规则时，规则模式仍会阻止启动。',
            'Process, GeoIP, remote rule-set/provider and keyword editing are intentionally unavailable. Rule mode remains blocked when an imported profile contains unsupported rules.'))
            .fontSize(9)
            .lineHeight(15)
            .fontColor(this.palette().warning)
            .width('100%')
            .margin({ top: 12 })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.palette().surface)
        .borderRadius(20)

        Text(this.t('核心日志', 'CORE LOGGING'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .margin({ top: 22, bottom: 10 })
        Column() {
          Row() {
            this.logLevelButton('Debug', 'debug')
            this.logLevelButton('Info', 'info')
            this.logLevelButton('Warn', 'warn')
            this.logLevelButton('Error', 'error')
          }
          .width('100%')
          Text(this.t('日志等级会写入 sing-box 运行配置；已连接时会安全停止并自动重连后立即应用。默认 Info；排查问题时可临时使用 Debug。',
            'The log level is written to the sing-box runtime configuration. While connected, the app safely stops and reconnects to apply it immediately. Use Debug temporarily for troubleshooting.'))
            .fontSize(11)
            .lineHeight(18)
            .fontColor(this.palette().textTertiary)
            .width('100%')
            .margin({ top: 10 })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.palette().surface)
        .borderRadius(20)

        Row() {
          Text('DNS')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().textPrimary)
          Blank()
          if (this.settingsLoading) {
            Text(this.t('正在恢复…', 'Restoring…'))
              .fontSize(11)
              .fontColor(this.palette().textTertiary)
          } else {
            Text(this.dnsPresetDisplayName(findDnsPreset(this.dnsPresetId)))
              .fontSize(11)
              .fontColor(this.palette().accent)
          }
        }
        .width('100%')
        .margin({ top: 22 })

        Column() {
          Text(this.t('安全 DNS 预设', 'Secure DNS presets'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().textPrimary)
            .width('100%')
          Text(this.t('应用的 DNS 请求先由 TUN 捕获，再通过 sing-box 的 hijack-dns 交给所选上游，减少绕过代理的 DNS 请求。',
            'TUN captures DNS first, then sing-box hijack-dns sends it to the selected upstream to reduce DNS bypass.'))
            .fontSize(11)
            .lineHeight(18)
            .fontColor(this.palette().textSecondary)
            .width('100%')
            .margin({ top: 7 })

          ForEach(DNS_PRESETS, (preset: DnsPreset) => {
            this.dnsPresetRow(preset)
          }, (preset: DnsPreset) => preset.id)

          if (this.dnsPresetId === 'custom' || this.customDnsEditorOpen) {
            TextInput({ placeholder: this.t('https://dns.example/dns-query 或 tls://dns.example',
              'https://dns.example/dns-query or tls://dns.example'), text: this.customDnsDraft })
              .height(46)
              .fontSize(13)
              .fontColor(this.palette().textPrimary)
              .placeholderColor(this.palette().placeholder)
              .backgroundColor(this.palette().background)
              .borderRadius(11)
              .padding({ left: 13, right: 13 })
              .margin({ top: 12 })
              .enabled(this.runtimeConfigurationEditable())
              .onChange((value: string) => {
                this.customDnsDraft = value
              })
            Button(this.t('校验并保存自定义 DNS', 'Validate and save custom DNS'))
              .width('100%')
              .height(44)
              .fontSize(this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control)
              .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1,
                minFontSize: APP_TYPOGRAPHY.controlMin,
                maxFontSize: this.isCompactLayout() ? APP_TYPOGRAPHY.controlCompact : APP_TYPOGRAPHY.control,
                heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
              .maxFontScale(APP_TYPOGRAPHY.controlMaxScale)
              .fontColor(this.runtimeConfigurationEditable() ? this.palette().accentForeground : this.palette().textTertiary)
              .backgroundColor(this.runtimeConfigurationEditable() ? this.palette().accent : this.palette().surfaceMuted)
              .borderRadius(11)
              .margin({ top: 10 })
              .enabled(this.runtimeConfigurationEditable())
              .onClick(() => this.saveCustomDns())
          }

          Text(this.localizedRuntimeText(this.dnsMessage))
            .fontSize(11)
            .lineHeight(17)
            .fontColor(this.dnsMessage.includes('不正确') || this.dnsMessage.includes('失败') ? this.palette().danger : this.palette().textTertiary)
            .width('100%')
            .margin({ top: 12 })
        }
        .width('100%')
        .padding(18)
        .backgroundColor(this.palette().surface)
        .borderRadius(22)
        .margin({ top: 10 })

        Text(this.t('连接安全边界', 'CONNECTION SAFETY'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .margin({ top: 22 })
        Text(this.coreInfo.available ?
          this.t('运行配置会原子写入应用私有目录。VPN 授权后，扩展先保护核心进程网络，再创建 TUN、校验并启动 sing-box；只有核心报告 running，首页才显示“已连接”。',
            'Runtime configuration is written atomically in the private app directory. After VPN permission, the extension protects core sockets, creates TUN, validates and starts sing-box. Home shows Connected only after the core reports running.') :
          this.localizedRuntimeText(this.coreInfo.reason))
          .fontSize(12)
          .lineHeight(19)
          .fontColor(this.palette().textSecondary)
          .width('100%')
          .margin({ top: 8, bottom: 112 })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  tabItem(icon: Resource, tab: string) {
    Column() {
      Stack() {
        SymbolGlyph(icon)
          .fontSize(21)
          .fontWeight(FontWeight.Regular)
          .fontColor([this.currentTab === tab ? this.palette().accent : this.palette().textSecondary])
      }
      .width(40)
      .height(28)
      .borderRadius(14)
      .backgroundColor(this.currentTab === tab ? this.palette().accentSoft : Color.Transparent)
      Text(this.primaryTabUiLabel(tab))
        .fontSize(this.isCompactLayout() ? 9 : 11)
        .fontWeight(this.currentTab === tab ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.currentTab === tab ? this.palette().accent : this.palette().textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 4 })
    }
    .height(54)
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Color.Transparent)
    .borderRadius(16)
    .margin({ left: 2, right: 2, top: 5, bottom: 5 })
    .accessibilityText(this.primaryTabUiLabel(tab))
    .accessibilityDescription(this.currentTab === tab ? this.t('当前标签', 'Current tab') : this.t('切换标签', 'Switch tab'))
    .onClick(() => {
      this.currentTab = tab
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (!this.appearanceReady) {
          this.appearanceSkeleton()
        } else if (this.privacyConsent === 'unknown') {
          this.privacyOnboarding()
        } else {
          Row() {
            Text(this.currentTab === 'home' ? 'HarmonyNet' : this.primaryTabUiLabel(this.currentTab))
              .fontSize(26).fontWeight(FontWeight.Bold).fontColor(this.palette().textPrimary)
              .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.connectionPhase === 'connected' ? this.t('已连接', 'Connected') :
              this.t('未连接', 'Disconnected'))
              .fontSize(12).fontColor(this.connectionColor())
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor(this.palette().surface).borderRadius(18)
          }.width('100%').height(68).padding({ left: 24, right: 24 })
          if (this.currentTab === 'home') {
            this.homePage()
          } else if (this.currentTab === 'proxy') {
            this.proxyPage()
          } else if (this.currentTab === 'subscription') {
            this.subscriptionPage()
          } else if (this.currentTab === 'activity') {
            this.activityPage()
          } else {
            this.settingsPage()
          }
        }
      }.width('100%').height('100%')
      if (this.appearanceReady && this.privacyConsent !== 'unknown') {
        Row() {
          this.tabItem($r('sys.symbol.house'), 'home')
          this.tabItem($r('sys.symbol.rectangle_stack'), 'subscription')
          this.tabItem($r('sys.symbol.diagnostic_analytics'), 'proxy')
          this.tabItem($r('sys.symbol.diagnostic_analytics'), 'activity')
          this.tabItem($r('sys.symbol.gearshape'), 'settings')
        }
        .width('92%').constraintSize({ maxWidth: 560 }).height(72)
        .padding({ left: 5, right: 5 }).margin({ bottom: 12 })
        .backgroundColor(this.reduceTransparency ? this.palette().surface : Color.Transparent)
        .backgroundBlurStyle(this.reduceTransparency ? BlurStyle.NONE : BlurStyle.COMPONENT_REGULAR, {
        colorMode: this.palette() === DARK_PALETTE ? ThemeColorMode.DARK : ThemeColorMode.LIGHT,
        adaptiveColor: AdaptiveColor.AVERAGE,
        policy: BlurStyleActivePolicy.FOLLOWS_WINDOW_ACTIVE_STATE,
        inactiveColor: this.palette().surface
      })
        .border({ width: 0.5, color: this.palette().borderStrong })
        .borderRadius(30).clip(true)
        .shadow({ radius: 16, color: this.palette().shadow, offsetY: 4 })
      }
    }
    .width('100%').height('100%')
    .backgroundColor(this.palette().background)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      if (typeof newArea.width === 'number' && newArea.width > 0 && this.viewportWidth !== newArea.width) {
        this.viewportWidth = newArea.width
      }
    })
  }
}
