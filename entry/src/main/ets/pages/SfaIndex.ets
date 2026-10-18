import { UiActivityLease } from '../domain/RuntimeActivity'
import { window } from '@kit.ArkUI'
import { scanBarcode, scanCore } from '@kit.ScanKit'
import { fileIo } from '@kit.CoreFileKit'
import { wifiManager } from '@kit.ConnectivityKit'
import { ScannedProfile, parseProfileQr } from '../domain/ProfileQr'
import { SsidPolicy, normalizeSsidPolicy } from '../domain/SsidPolicy'
import { invertApplicationSelection, perAppScope } from '../domain/PerAppPolicy'
import { writeAtomicText } from '../services/AtomicFileWriter'
import { trafficRates, TrafficSample, TrafficRates, delayColor } from '../domain/RuntimeTelemetry'
import { systemShare } from '@kit.ShareKit'
import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { http, connection } from '@kit.NetworkKit'
import { picker } from '@kit.CoreFileKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import type { CoreStatus } from '../core/CoreGateway'
import { ConnectionCoordinator } from '../services/ConnectionCoordinator'
import { SfaProfileStore } from '../services/SfaProfileStore'
import { readLocalDocument } from '../services/LocalDocumentReader'
import { LocalConfigStore } from '../services/LocalConfigStore'
import { prepareLocalConfig } from '../domain/LocalConfig'
import { SfaCatalog, SfaProfile, emptySfaCatalog, saveSfaProfile, deleteSfaProfile, validateSfaContent } from '../domain/SfaProfiles'
import { ApplicationCatalogResult, ApplicationCatalogService, SelectableApplication } from '../services/ApplicationCatalogService'
import { NetworkSettings, defaultNetworkSettings, vpnApplicationScope, normalizeVpnApplicationScope, validateApplicationBundleName } from '../domain/NetworkSettings'
import { DARK_PALETTE, LIGHT_PALETTE, AppPalette } from '../ui/DesignSystem'
import { HttpsUrlGuard } from '../services/SubscriptionService'

interface GroupItem { tag: string; type: string; urlTestDelay?: number }
interface GroupInfo { tag: string; type: string; selectable: boolean; selected: string; items: GroupItem[] }
interface GroupList { group: GroupInfo[] }
interface RuntimeMetrics { memory?: number; goroutines?: number; connectionsIn?: number; connectionsOut?: number; uplinkTotal?: number; downlinkTotal?: number }
interface LiveConnection { id: string; network?: string; domain?: string; destination?: string; inbound?: string; outbound?: string; rule?: string; uplinkTotal?: number; downlinkTotal?: number }
interface RuntimeSnapshot { suspended?: boolean; connections?: LiveConnection[]; sampledAt?: number; status?: RuntimeMetrics; groups?: GroupList; logs?: string[]; modes?: string[]; mode?: string }
interface RuntimeControl { id?: string; action: string; group?: string; outbound?: string; mode?: string }

@Entry
@Component
struct SfaIndex {
  @StorageProp('uiForeground') @Watch('onUiForegroundChanged') uiForeground: boolean = true
  @StorageProp('colorMode') @Watch('syncWindowTheme') colorMode: ColorMode = ColorMode.LIGHT
  @StorageProp('topInsetPx') topInsetPx: number = 0
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0
  @State showAddProfile: boolean = false
  @State excludedSsids: string[] = []
  @State selectedSsids: string[] = []
  @State showSsidEditor: boolean = false
  @State draftSsid: string = ''
  @State suspended: boolean = false
  @State ssidEnabled: boolean = false
  @State directSsids: string = ''
  @State proxySsids: string = ''
  @State ssidFallback: string = 'keep'
  @State ssidMessage: string = ''
  @State currentSsid: string = ''
  @State liveConnections: LiveConnection[] = []
  @State connectionQuery: string = ''
  @State perAppEnabled: boolean = false
  @State perAppBypass: boolean = false
  @State applicationLoading: boolean = false
  @State applicationDirty: boolean = false
  @State applicationSearchVisible: boolean = false
  @State showSystemApplications: boolean = true
  @State applicationCatalogState: string = ''
  @State applicationMode: string = 'all'
  @State selectedApplications: string[] = []
  @State applicationCatalog: SelectableApplication[] = []
  @State applicationQuery: string = ''
  @State applicationMessage: string = ''
  @State showGroups: boolean = false
  @State expandedGroups: string[] = []
  @State testingGroup: string = ''
  @State memoryBytes: number = 0
  @State goroutines: number = 0
  @State connectionsOut: number = 0
  @State uploadHistory: number[] = [0, 0]
  @State downloadHistory: number[] = [0, 0]
  @State chartWidth: number = 120
  private trafficSample: TrafficSample | null = null
  private lastGroupTestAt: number = 0
  private groupTestBusy: boolean = false
  @State showProfilePicker: boolean = false
  @State tab: string = 'dashboard'
  @State page: string = ''
  @State catalog: SfaCatalog = emptySfaCatalog()
  @State ready: boolean = false
  @State busy: boolean = false
  @State phase: string = 'checking'
  @State message: string = '正在检查服务状态'
  @State upload: number = 0
  @State download: number = 0
  @State uploadRate: number = 0
  @State downloadRate: number = 0
  @State connectionCount: number = 0
  @State groups: GroupInfo[] = []
  @State logs: string[] = []
  @State modes: string[] = []
  @State mode: string = ''
  @State logQuery: string = ''
  @State logLevel: string = 'all'
  @State theme: string = 'system'
  @State reduceTransparency: boolean = false
  @State editingId: string = ''
  @State draftName: string = ''
  @State draftKind: string = 'local'
  @State draftUrl: string = ''
  @State draftContent: string = ''
  @State groupTag: string = ''
  @State host: string = 'example.com'
  @State toolResult: string = ''
  @State startedAt: number = 0
  @State clockMillis: number = Date.now()
  @State visibleCards: string[] = ['traffic', 'connections', 'mode', 'profiles', 'groups']
  private coordinator: ConnectionCoordinator | null = null
  private store: SfaProfileStore | null = null
  private prefs: preferences.Preferences | null = null
  private networkSettings: NetworkSettings = defaultNetworkSettings()
  private leasePath: string = ''
  private leaseWrittenAt: number = 0
  private leaseQueue: Promise<void> = Promise.resolve()
  private pageAlive: boolean = true
  private timer: number = 0
  private polling: boolean = false
  private previousAt: number = 0
  private previousUpload: number = 0
  private previousDownload: number = 0
  private commandEpoch: number = 0

  aboutToAppear(): void {
    hilog.info(0, 'SfaUI', 'Constructed page without loading the native core')
    this.pageAlive = true
    this.initialize()
  }

  aboutToDisappear(): void {
    this.pageAlive = false
    this.publishUiActivity(false)
    if (this.timer !== 0) clearInterval(this.timer)
    this.timer = 0
    // The VPN extension retains ownership. Closing this page never disconnects.
  }

  private publishUiActivity(foreground: boolean): void {
    if (!this.leasePath) return
    const lease: UiActivityLease = { foreground: foreground, updatedAt: Date.now() }
    this.leaseWrittenAt = lease.updatedAt
    const path: string = this.leasePath
    this.leaseQueue = this.leaseQueue.then(() => writeAtomicText(path, JSON.stringify(lease))).catch(() => {})
  }

  private onUiForegroundChanged(): void {
    if (this.timer !== 0) clearInterval(this.timer)
    this.timer = 0
    const active: boolean = this.uiForeground && this.pageAlive
    this.publishUiActivity(active)
    if (active && this.ready) {
      this.poll()
      this.timer = setInterval(() => this.poll(), 1000)
    } else {
      this.trafficSample = null
      this.uploadHistory = [0, 0]; this.downloadHistory = [0, 0]
      this.liveConnections = []; this.logs = []
    }
  }

  onBackPress(): boolean {
    if (this.showSsidEditor) { this.showSsidEditor = false; return true }
    if (this.page === 'applications') { this.finishApplications(); return true }
    if (this.page.length > 0) { this.page = ''; return true }
    if (this.tab !== 'dashboard') { this.tab = 'dashboard'; return true }
    return false
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private palette(): AppPalette {
    return this.theme === 'dark' || (this.theme === 'system' && this.colorMode === ColorMode.DARK) ? DARK_PALETTE : LIGHT_PALETTE
  }

  private toast(text: string): void {
    this.getUIContext().getPromptAction().showToast({ message: text, duration: 2500 })
  }

  private async initialize(): Promise<void> {
    try {
      this.coordinator = new ConnectionCoordinator(this.context())
      this.store = new SfaProfileStore(this.context().filesDir)
      this.prefs = await preferences.getPreferences(this.context(), 'sfa-ui-v1')
      this.theme = this.prefs.getSync('theme', 'system') as string
      this.reduceTransparency = this.prefs.getSync('reduce-transparency', false) as boolean
      const savedScope: string = this.prefs.getSync('application-scope', '') as string
      if (savedScope.length > 0) {
        const scope = normalizeVpnApplicationScope(JSON.parse(savedScope))
        this.networkSettings.applicationMode = scope.mode
        this.networkSettings.trustedApplications = scope.trustedApplications
        this.applicationMode = scope.mode
        this.selectedApplications = scope.trustedApplications.slice()
      }
      this.perAppEnabled = this.prefs.getSync('per-app-enabled', this.applicationMode !== 'all') as boolean
      this.perAppBypass = this.prefs.getSync('per-app-bypass', this.applicationMode === 'blocklist') as boolean
      this.syncWindowTheme()
      this.loadSsidPolicy()
      this.catalog = await this.store.load()
      if (this.catalog.profiles.length === 0) {
        const previous: string | null = await new LocalConfigStore(this.context().filesDir).load()
        if (previous) {
          this.catalog = saveSfaProfile(this.catalog, { id: 'migrated-local', name: '本地配置', kind: 'local',
            url: '', content: previous, updatedAt: Date.now() })
          await this.store.save(this.catalog)
        }
      }
      const runtimePath: string = this.context().filesDir + '/runtime'
      if (!await fileIo.access(runtimePath)) await fileIo.mkdir(runtimePath, true)
      this.leasePath = runtimePath + '/ui-activity.json'
    } catch (failure) {
      this.phase = 'error'
      this.message = failure instanceof Error ? failure.message : '初始化失败'
      hilog.error(0, 'SfaUI', 'Initialization failed: %{public}s', this.message)
    } finally { this.ready = true; this.onUiForegroundChanged() }
  }

  private async poll(): Promise<void> {
    if (!this.uiForeground || !this.pageAlive || this.polling || !this.coordinator || this.busy) return
    if (Date.now() - this.leaseWrittenAt >= 10000) this.publishUiActivity(true)
    this.polling = true
    try {
      const status: CoreStatus = await this.coordinator.getStatus()
      this.applyStatus(status)
    } catch (failure) {
      this.phase = 'error'
      this.message = failure instanceof Error ? failure.message : '服务状态读取失败'
    } finally { this.polling = false }
  }

  private applyStatus(status: CoreStatus): void {
    const now: number = Date.now()
    this.clockMillis = now
    this.upload = status.uploadBytes
    this.download = status.downloadBytes
    this.connectionCount = status.activeConnections
    this.phase = status.lastError.length > 0 ? 'error' : (status.running ? 'running' : 'stopped')
    this.message = status.lastError || (status.running ? '已启动' : '已停止')
    if (status.running && this.startedAt === 0) this.startedAt = now
    if (!status.running) this.startedAt = 0
    if (status.snapshotJson) {
      try {
        const snapshot: RuntimeSnapshot = JSON.parse(status.snapshotJson) as RuntimeSnapshot
        this.suspended = snapshot.suspended === true
        if (this.suspended) { this.uploadRate = 0; this.downloadRate = 0 }
        this.groups = snapshot.groups?.group || []
        this.liveConnections = (snapshot.connections || []).sort((a: LiveConnection, b: LiveConnection): number => a.id.localeCompare(b.id))
        this.memoryBytes = snapshot.status?.memory || 0
        this.goroutines = snapshot.status?.goroutines || 0
        this.connectionsOut = snapshot.status?.connectionsOut || 0
        if (status.running && snapshot.sampledAt && !this.suspended) {
          const sample: TrafficSample = { session: status.sessionId || 'running', at: snapshot.sampledAt,
            upload: snapshot.status?.uplinkTotal || 0, download: snapshot.status?.downlinkTotal || 0 }
          const rates: TrafficRates | null = trafficRates(this.trafficSample, sample)
          if (rates) {
            this.uploadRate = rates.upload; this.downloadRate = rates.download
            this.uploadHistory = [...this.uploadHistory.slice(-29), rates.upload]
            this.downloadHistory = [...this.downloadHistory.slice(-29), rates.download]
            this.trafficSample = sample
          }
          this.upload = sample.upload; this.download = sample.download
        }
        this.logs = snapshot.logs || []
        this.modes = snapshot.modes || []
        this.mode = snapshot.mode || ''
      } catch (_) { this.message = '运行数据格式错误' }
    }
    if (!status.running) {
      this.liveConnections = []; this.groups = []; this.modes = []; this.mode = ''; this.trafficSample = null
      this.uploadRate = 0; this.downloadRate = 0; this.uploadHistory = [0, 0]; this.downloadHistory = [0, 0]
      this.showGroups = false; this.lastGroupTestAt = 0
    } else if (this.showGroups && now - this.lastGroupTestAt > 30000) { this.refreshGroupDelays() }
  }

  private openGroups(): void {
    this.showGroups = true
    this.refreshGroupDelays()
  }

  private toggleGroup(tag: string): void {
    this.expandedGroups = this.expandedGroups.includes(tag) ? this.expandedGroups.filter((value: string) => value !== tag) : [...this.expandedGroups, tag]
  }

  private async refreshGroupDelays(tag: string = ''): Promise<void> {
    if (!this.uiForeground || !this.pageAlive || this.suspended || !this.coordinator || this.groupTestBusy || this.phase !== 'running') return
    this.groupTestBusy = true; this.testingGroup = tag || '*'; this.lastGroupTestAt = Date.now()
    try {
      for (const group of this.groups) {
        if (!this.uiForeground || !this.pageAlive || this.suspended) break
        if (tag.length === 0 || group.tag === tag) {
          await this.coordinator.control(JSON.stringify({ action: 'urltest', group: group.tag } as RuntimeControl))
        }
      }
    } catch (failure) { this.toast(failure instanceof Error ? failure.message : '测速请求失败') }
    finally { this.groupTestBusy = false; this.testingGroup = ''; await this.poll() }
  }

  private nodeType(type: string): string {
    if (type === 'selector') return 'Selector'
    if (type === 'urltest') return 'URLTest'
    if (type === 'vless') return 'VLESS'
    if (type === 'hysteria2') return 'Hysteria2'
    if (type === 'direct') return 'Direct'
    if (type === 'block') return 'Block'
    return type
  }

  private chartPoints(values: number[]): number[][] {
    const max: number = Math.max(1, ...values)
    return values.map((value: number, index: number) => [index * this.chartWidth / Math.max(1, values.length - 1), 72 - value / max * 68])
  }

  private elapsed(): string {
    const seconds: number = Math.max(0, Math.floor((this.clockMillis - this.startedAt) / 1000))
    return Math.floor(seconds / 60).toString() + ':' + (seconds % 60).toString().padStart(2, '0')
  }

  private selectedProfile(): SfaProfile | undefined {
    return this.catalog.profiles.find((profile: SfaProfile) => profile.id === this.catalog.selectedId)
  }

  private async persist(catalog: SfaCatalog): Promise<void> {
    if (!this.store) throw new Error('配置存储尚未就绪')
    await this.store.save(catalog)
    this.catalog = catalog
  }

  private async toggleService(): Promise<void> {
    if (!this.coordinator || (this.busy && this.phase !== 'running') || !this.ready) return
    const epoch: number = ++this.commandEpoch
    this.busy = true
    try {
      if (this.phase === 'running' || this.phase === 'error') {
        this.phase = 'stopping'; this.message = '正在停止'
        this.applyStatus(await this.coordinator.disconnect())
      } else {
        const profile: SfaProfile | undefined = this.selectedProfile()
        if (!profile) { this.toast('请先添加配置'); this.page = 'profiles'; return }
        this.phase = 'starting'; this.message = '正在启动'
        const status: CoreStatus = await this.coordinator.connect(prepareLocalConfig(profile.content), vpnApplicationScope(this.networkSettings))
        if (epoch === this.commandEpoch) this.applyStatus(status)
      }
    } catch (failure) {
      this.phase = 'error'; this.message = failure instanceof Error ? failure.message : '启动失败'
      this.toast(this.message)
    } finally { this.busy = false }
  }

  private async selectProfile(id: string): Promise<void> {
    if (this.busy || id === this.catalog.selectedId) return
    const wasRunning: boolean = this.phase === 'running'
    const epoch: number = ++this.commandEpoch
    const previous: SfaCatalog = this.catalog
    this.busy = true
    try {
      if (wasRunning && this.coordinator) {
        this.phase = 'stopping'; this.message = '正在切换配置'
        this.applyStatus(await this.coordinator.disconnect())
      }
      await this.persist({ version: 1, profiles: this.catalog.profiles, selectedId: id })
      const profile: SfaProfile | undefined = this.selectedProfile()
      if (wasRunning && this.coordinator && profile && epoch === this.commandEpoch) {
        this.phase = 'starting'
        this.applyStatus(await this.coordinator.connect(prepareLocalConfig(profile.content), vpnApplicationScope(this.networkSettings)))
      }
    } catch (failure) {
      this.phase = 'error'; this.message = failure instanceof Error ? failure.message : '配置切换失败'
      if (this.catalog.selectedId === previous.selectedId) this.catalog = previous
      this.toast(this.message)
    } finally { this.busy = false }
  }

  private editProfile(profile?: SfaProfile): void {
    this.editingId = profile?.id || ''
    this.draftName = profile?.name || ''
    this.draftKind = profile?.kind || 'local'
    this.draftUrl = profile?.url || ''
    this.draftContent = profile?.content || ''
    this.page = 'editor'
  }

  private async downloadRaw(url: string): Promise<string> {
    if (!/^https:\/\//i.test(url.trim())) throw new Error('远程配置需要 HTTPS 地址')
    const request: http.HttpRequest = http.createHttp()
    try {
      const redirect: HttpsUrlGuard = new HttpsUrlGuard(http.InterceptorType.REDIRECTION, 3)
      const final: HttpsUrlGuard = new HttpsUrlGuard(http.InterceptorType.FINAL_RESPONSE)
      const chain: http.HttpInterceptorChain = new http.HttpInterceptorChain()
      if (!chain.addChain([redirect, final]) || !chain.apply(request)) throw new Error('无法设置下载安全检查')
      const response: http.HttpResponse = await request.request(url.trim(), {
        method: http.RequestMethod.GET, expectDataType: http.HttpDataType.STRING,
        maxLimit: 4194304, connectTimeout: 15000, readTimeout: 20000, usingCache: false,
        header: { 'User-Agent': 'sing-box/1.14.3 (HarmonyOS)' }
      })
      if (redirect.rejectedInsecureUrl() || final.rejectedInsecureUrl() || redirect.exceededInvocationLimit() || !final.observedUrl()) {
        throw new Error('远程配置重定向不符合 HTTPS 要求')
      }
      if (response.responseCode < 200 || response.responseCode >= 300 || typeof response.result !== 'string') {
        throw new Error(`配置下载失败：HTTP ${response.responseCode}`)
      }
      validateSfaContent(response.result)
      return response.result
    } finally { request.destroy() }
  }

  private async saveEditor(): Promise<void> {
    if (this.busy) return
    this.busy = true
    try {
      const restart: boolean = this.editingId.length > 0 && this.editingId === this.catalog.selectedId && this.phase === 'running'
      const content: string = this.draftKind === 'remote' ? await this.downloadRaw(this.draftUrl) : this.draftContent
      validateSfaContent(content)
      const profile: SfaProfile = { id: this.editingId || `profile-${Date.now()}`, name: this.draftName.trim() || '未命名配置',
        kind: this.draftKind, url: this.draftKind === 'remote' ? this.draftUrl.trim() : '', content: content, updatedAt: Date.now() }
      await this.persist(saveSfaProfile(this.catalog, profile))
      if (restart && this.coordinator) {
        this.phase = 'stopping'
        this.applyStatus(await this.coordinator.disconnect())
        this.phase = 'starting'
        this.applyStatus(await this.coordinator.connect(prepareLocalConfig(profile.content), vpnApplicationScope(this.networkSettings)))
      }
      this.page = 'profiles'; this.toast('配置已保存')
    } catch (failure) { this.toast(failure instanceof Error ? failure.message : '配置保存失败') }
    finally { this.busy = false }
  }

  private async importFile(): Promise<void> {
    if (this.busy) return
    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(this.context())
      const files: string[] = await documentPicker.select({ maxSelectNumber: 1 })
      if (files.length === 0) return
      this.draftContent = await readLocalDocument(files[0])
      validateSfaContent(this.draftContent)
      this.draftKind = 'local'
      this.page = 'editor'
      if (!this.draftName) this.draftName = decodeURIComponent(files[0].split('/').pop() || '本地配置').replace(/\.json$/i, '')
      this.toast('文件已读取，确认名称后保存')
    } catch (failure) { this.toast(failure instanceof Error ? failure.message : '文件读取失败') }
  }

  private async updateProfile(profile: SfaProfile): Promise<void> {
    if (this.busy || profile.kind !== 'remote') return
    this.busy = true
    try {
      const content: string = await this.downloadRaw(profile.url)
      await this.persist(saveSfaProfile(this.catalog, { id: profile.id, name: profile.name, kind: profile.kind,
        url: profile.url, content: content, updatedAt: Date.now() }))
      this.toast('配置已更新；运行中的服务继续使用原配置，重启后应用')
    } catch (failure) { this.toast(failure instanceof Error ? failure.message : '更新失败') }
    finally { this.busy = false }
  }

  private removeProfile(profile: SfaProfile): void {
    if (this.busy) return
    if (this.phase === 'running' && profile.id === this.catalog.selectedId) { this.toast('请先停止当前配置'); return }
    this.getUIContext().getPromptAction().showDialog({ title: '删除配置', message: profile.name,
      buttons: [{ text: '取消', color: '#666666' }, { text: '删除', color: '#BA1A1A' }] }).then(async (result) => {
      if (result.index === 1) {
        try { await this.persist(deleteSfaProfile(this.catalog, profile.id)) }
        catch (_) { this.toast('删除失败，原配置已保留') }
      }
    })
  }

  private async control(command: RuntimeControl): Promise<void> {
    if (!this.coordinator || this.busy || this.phase !== 'running') return
    this.busy = true
    try { await this.coordinator.control(JSON.stringify(command)) }
    catch (failure) { this.toast(failure instanceof Error ? failure.message : '操作失败') }
    finally { this.busy = false; await this.poll() }
  }

  private async testGroupItem(item: GroupItem): Promise<void> {
    if (!this.coordinator || this.busy) return
    this.busy = true
    try { const delay: number = await this.coordinator.urlTest(item.tag); this.toast(`${item.tag} · ${delay} ms`) }
    catch (failure) { this.toast(failure instanceof Error ? failure.message : '测速失败') }
    finally { this.busy = false }
  }

  private async saveAppearance(): Promise<void> {
    this.syncWindowTheme()
    if (!this.prefs) return
    try {
      this.prefs.putSync('theme', this.theme)
      this.prefs.putSync('reduce-transparency', this.reduceTransparency)
      await this.prefs.flush()
    } catch (_) { this.toast('外观设置未能保存') }
  }

  private formatBytes(value: number): string {
    if (value < 1024) return `${Math.round(value)} B`
    if (value < 1048576) return `${(value / 1024).toFixed(1)} KB`
    if (value < 1073741824) return `${(value / 1048576).toFixed(1)} MB`
    return `${(value / 1073741824).toFixed(2)} GB`
  }

  private title(): string {
    if (this.page === 'sources') return '开源项目与源码地址'
    if (this.page === 'ssid') return '按需连接'
    if (this.page === 'connections') return '连接'
    if (this.page === 'applications') return '分应用代理'
    if (this.page === 'profiles') return '配置'
    if (this.page === 'editor') return this.editingId ? '编辑配置' : '新建配置'
    if (this.page === 'groups') return this.groupTag || '代理组'
    if (this.page === 'appearance') return '应用设置'
    if (this.page === 'about') return '关于'
    if (this.page === 'cards') return '仪表盘项目'
    if (this.tab === 'log') return '日志'
    if (this.tab === 'tools') return '工具'
    if (this.tab === 'settings') return '设置'
    return '仪表'
  }

  @Builder
  icon(name: string, size: number = 24) {
    Image($rawfile(`sfa-${name}.svg`)).width(size).height(size).fillColor(this.palette().textPrimary)
  }

  @Builder
  appToolbar() {
    Row({ space: 12 }) {
      if (this.page.length > 0) {
        Button('‹').fontSize(30).width(44).height(44).backgroundColor(Color.Transparent)
          .fontColor(this.palette().textPrimary).onClick(() => { if (this.page === 'applications') this.finishApplications(); else this.page = this.page === 'editor' ? 'profiles' : '' })
      }
      Text(this.title()).fontSize(22).fontWeight(FontWeight.Normal).fontColor(this.palette().textPrimary)
        .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.page === 'applications') {
        Button('⌕').width(40).height(44).fontSize(26).backgroundColor(Color.Transparent).fontColor(this.palette().textPrimary)
          .onClick(() => { this.applicationSearchVisible = !this.applicationSearchVisible })
        Button('⋮').width(40).height(44).fontSize(25).backgroundColor(Color.Transparent).fontColor(this.palette().textPrimary)
          .bindMenu([
            { value: '全选', action: () => this.selectVisibleApplications(false) },
            { value: '反选', action: () => this.selectVisibleApplications(true) },
            { value: '显示 / 隐藏系统应用', action: () => { this.showSystemApplications = !this.showSystemApplications } },
            { value: '刷新应用列表', action: () => this.loadApplications() },
            { value: '导入包名名单', action: () => this.importApplications() }
          ])
      } else if (this.page === 'profiles') {
        Button('+').width(48).height(48).fontSize(28).backgroundColor(Color.Transparent)
          .fontColor(this.palette().textPrimary).onClick(() => { this.showAddProfile = true })
      } else if (this.page === 'editor') {
        Button('保存').fontSize(14).backgroundColor(Color.Transparent).fontColor(this.palette().accent)
          .enabled(!this.busy).onClick(() => this.saveEditor())
      } else if (this.tab === 'dashboard' && this.page === '') {
        Button('⋮').width(44).height(44).fontSize(26).backgroundColor(Color.Transparent)
          .fontColor(this.palette().textPrimary).onClick(() => { this.page = 'cards' })
      } else if (this.tab === 'log' && this.page === '') {
        Button('清空').fontSize(14).backgroundColor(Color.Transparent).fontColor(this.palette().accent)
          .enabled(this.phase === 'running' && !this.busy).onClick(() => this.control({ action: 'clear-logs' }))
      }
    }.width('100%').height(64).padding({ left: this.page.length > 0 ? 8 : 16, right: 12 })
  }

  @Builder
  statistic(title: string) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        this.icon(title === '上传' ? 'upload' : 'download', 20)
        Text(title).fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.palette().textPrimary)
      }.width('100%').margin({ bottom: 4 })
      Text(`${this.formatBytes(title === '上传' ? this.uploadRate : this.downloadRate)}/s`).fontSize(25).fontColor(this.palette().textPrimary).width('100%').maxLines(1)
      Text(this.formatBytes(title === '上传' ? this.upload : this.download)).fontSize(14).fontColor(this.palette().textSecondary).width('100%')
      Blank().height(16)
      Polyline().points(this.chartPoints(title === '上传' ? this.uploadHistory : this.downloadHistory))
        .width('100%').height(76).stroke(this.palette().accent).strokeWidth(2).fill(Color.Transparent)
        .onAreaChange((_old: Area, area: Area) => { this.chartWidth = Number(area.width) })
    }.layoutWeight(1).alignItems(HorizontalAlign.Start).padding(16)
      .backgroundColor(this.palette().surfaceElevated).borderRadius(12)
  }

  @Builder
  metricRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor(this.palette().textSecondary).layoutWeight(1)
      Text(value).fontSize(16).fontColor(this.palette().textPrimary)
    }.width('100%')
  }

  @Builder
  diagnosticsCard(debug: boolean) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        this.icon(debug ? 'debug' : 'connections', 20)
        Text(debug ? '调试' : '连接').fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.palette().textPrimary)
      }.width('100%').margin({ bottom: 4 })
      Row() {
        Text(debug ? '内存' : '入站').layoutWeight(1).fontColor(this.palette().textSecondary)
        Text(debug ? this.formatBytes(this.memoryBytes) : this.connectionCount.toString()).fontColor(this.palette().textPrimary)
      }.width('100%')
      Row() {
        Text(debug ? '协程' : '出站').layoutWeight(1).fontColor(this.palette().textSecondary)
        Text(debug ? this.goroutines.toString() : this.connectionsOut.toString()).fontColor(this.palette().textPrimary)
      }.width('100%')
    }.layoutWeight(1).padding(16).backgroundColor(this.palette().surfaceElevated).borderRadius(12)
      .onClick(() => { if (!debug) this.page = 'connections' })
  }

  private profileAge(profile: SfaProfile | undefined): string {
    if (!profile) return ''
    const minutes: number = Math.max(0, Math.floor((Date.now() - profile.updatedAt) / 60000))
    return minutes < 1 ? '刚刚' : minutes < 60 ? `${minutes} 分钟前` : minutes < 1440 ? `${Math.floor(minutes / 60)} 小时前` : `${Math.floor(minutes / 1440)} 天前`
  }

  private async shareSelectedProfile(): Promise<void> {
    const profile: SfaProfile | undefined = this.selectedProfile()
    if (!profile) return
    try {
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: 'general.plain-text', content: profile.content, title: profile.name
      })
      await new systemShare.ShareController(data).show(this.context(), {})
    } catch (_) { this.toast('无法打开分享面板') }
  }

  @Builder
  profilePicker() {
    Column({ space: 4 }) {
      Text('配置').fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.palette().textPrimary)
        .width('100%').padding({ left: 8, top: 16, bottom: 16 })
      ForEach(this.catalog.profiles, (profile: SfaProfile) => {
        Row({ space: 16 }) {
          this.icon('file', 24)
          Column({ space: 2 }) {
            Text(profile.name).fontSize(16).fontColor(this.palette().textPrimary).maxLines(1)
            Text(profile.kind === 'remote' ? '远程 · ' + this.profileAge(profile) : '本地')
              .fontSize(12).fontColor(this.palette().textSecondary)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (this.catalog.selectedId === profile.id) Text('✓').fontSize(24).fontColor(this.palette().accent)
          Button('⋮').fontSize(24).width(32).height(44).backgroundColor(Color.Transparent)
            .fontColor(this.palette().textPrimary)
            .bindMenu([
              { value: '编辑', action: () => { this.showProfilePicker = false; this.editProfile(profile) } },
              { value: '更新', enabled: profile.kind === 'remote', action: () => { this.updateProfile(profile) } },
              { value: '删除', action: () => { this.removeProfile(profile) } }
            ])
        }.width('100%').height(56).padding({ left: 16, right: 12 }).borderRadius(12)
          .backgroundColor(this.catalog.selectedId === profile.id ? this.palette().surfaceMuted : this.palette().surfaceElevated)
          .onClick(() => { this.showProfilePicker = false; this.selectProfile(profile.id) })
      }, (profile: SfaProfile) => profile.id)
    }.width('100%').padding({ left: 16, right: 16, bottom: 32 })
  }

  @Builder
  profilesCard() {
    Column() {
      Row({ space: 8 }) {
        this.icon('profiles', 20)
        Text('配置').fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.palette().textPrimary).layoutWeight(1)
        Button('+').fontSize(24).width(44).height(44).borderRadius(12).backgroundColor(this.palette().surfaceMuted)
          .fontColor(this.palette().textSecondary).onClick(() => { this.showAddProfile = true })
      }.width('100%').margin({ bottom: 12 })
      if (this.catalog.profiles.length === 0) {
        Text('没有配置').fontSize(14).fontColor(this.palette().textSecondary).padding({ top: 16, bottom: 16 })
          .width('100%').onClick(() => { this.showAddProfile = true })
      } else {
        Row({ space: 12 }) {
          this.icon('file', 20)
          Text(this.selectedProfile()?.name || '选择配置').fontSize(16).fontColor(this.palette().textPrimary)
            .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          this.icon('unfold', 20)
        }.width('100%').height(48).padding({ left: 16, right: 16 }).borderRadius(12)
          .backgroundColor(this.palette().surfaceMuted).onClick(() => { this.showProfilePicker = true })
        Row({ space: 6 }) {
          this.icon(this.selectedProfile()?.kind === 'remote' ? 'cloud' : 'file', 14)
          Text(this.selectedProfile()?.kind === 'remote' ? '远程' : '本地').fontSize(12).fontColor(this.palette().textSecondary)
          if (this.selectedProfile()?.kind === 'remote') {
            this.icon('clock', 14)
            Text(this.profileAge(this.selectedProfile())).fontSize(12).fontColor(this.palette().textSecondary)
          }
        }.width('100%').height(18).margin({ top: 12, bottom: 16 })
        Row({ space: 12 }) {
          Button() { this.icon('edit', 20) }.width(44).height(44).borderRadius(12)
            .backgroundColor(this.palette().surfaceMuted).accessibilityText('编辑配置')
            .onClick(() => this.editProfile(this.selectedProfile()))
          if (this.selectedProfile()?.kind === 'remote') {
            Button() { this.icon('refresh', 20) }.width(44).height(44).borderRadius(12)
              .backgroundColor(this.palette().surfaceMuted).enabled(!this.busy).accessibilityText('更新配置')
              .onClick(() => { const profile: SfaProfile | undefined = this.selectedProfile(); if (profile) this.updateProfile(profile) })
          }
          Button() { this.icon('share', 20) }.width(44).height(44).borderRadius(12)
            .backgroundColor(this.palette().surfaceMuted).accessibilityText('分享配置')
            .onClick(() => this.shareSelectedProfile())
        }.width('100%')
      }
    }.width('100%').padding(16).backgroundColor(this.palette().surfaceElevated).borderRadius(12)
      .bindSheet($$this.showProfilePicker, this.profilePicker(), {
        height: SheetSize.FIT_CONTENT, showClose: false, dragBar: true,
        backgroundColor: this.reduceTransparency ? this.palette().surface : (this.palette() === DARK_PALETTE ? '#661C1D21' : '#66F5F3FA'),
        blurStyle: this.reduceTransparency ? BlurStyle.NONE : BlurStyle.COMPONENT_THICK
      })
  }

  @Builder
  dashboard() {
    Scroll() {
      Column({ space: 16 }) {
        Blank().height(this.topInset() + 64)
        if (this.phase === 'running') {
          if (this.visibleCards.includes('traffic')) {
            Row({ space: 16 }) {
              this.statistic('上传')
              this.statistic('下载')
            }.width('100%')
          }
          if (this.visibleCards.includes('connections')) {
            Row({ space: 16 }) {
              this.diagnosticsCard(true)
              this.diagnosticsCard(false)
            }.width('100%')
          }
          if (this.modes.length > 0 && this.visibleCards.includes('mode')) {
            Column({ space: 12 }) {
              Text('模式').fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.palette().textPrimary).width('100%')
              Row() {
                ForEach(this.modes, (mode: string) => {
                  Button(mode.toLowerCase() === 'rule' ? '规则' : mode.toLowerCase() === 'global' ? '全局' : mode.toLowerCase() === 'direct' ? '直连' : mode).fontSize(14).layoutWeight(1).height(44)
                    .backgroundColor(this.mode === mode ? this.palette().accentSoft : Color.Transparent)
                    .fontColor(this.palette().textPrimary).enabled(!this.busy)
                    .onClick(() => this.control({ action: 'mode', mode: mode }))
                }, (mode: string) => mode)
              }.width('100%').borderRadius(22).border({ width: 1, color: this.palette().borderStrong })
            }.width('100%').padding(16).backgroundColor(this.palette().surfaceElevated).borderRadius(12)
          }
        }
        if (this.visibleCards.includes('profiles') || this.phase !== 'running') this.profilesCard()
        if (this.phase === 'error') {
          Text(this.message).fontSize(14).fontColor(this.palette().danger).lineHeight(21).width('100%').padding(16)
        }
      }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 160 })
    }.layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)
  }

  @Builder
  profilesPage() {
    Scroll() {
      Column({ space: 10 }) {
        Blank().height(this.topInset() + 64)
        ForEach(this.catalog.profiles, (profile: SfaProfile) => {
          Column({ space: 10 }) {
            Row({ space: 12 }) {
              Text(this.catalog.selectedId === profile.id ? '●' : '○').fontSize(20).fontColor(this.palette().accent)
              Column({ space: 4 }) {
                Text(profile.name).fontSize(16).fontColor(this.palette().textPrimary)
                Text(profile.kind === 'remote' ? '远程' : '本地').fontSize(12).fontColor(this.palette().textSecondary)
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }.width('100%').constraintSize({ minHeight: 48 }).onClick(() => this.selectProfile(profile.id))
            Row({ space: 8 }) {
              Button('编辑').fontSize(13).height(40).backgroundColor(Color.Transparent).fontColor(this.palette().accent)
                .onClick(() => this.editProfile(profile))
              if (profile.kind === 'remote') {
                Button('更新').fontSize(13).height(40).backgroundColor(Color.Transparent).fontColor(this.palette().accent)
                  .onClick(() => this.updateProfile(profile))
              }
              Blank()
              Button('删除').fontSize(13).height(40).backgroundColor(Color.Transparent).fontColor(this.palette().danger)
                .onClick(() => this.removeProfile(profile))
            }.width('100%')
          }.width('100%').padding(16).backgroundColor(this.palette().surfaceElevated).borderRadius(12)
        }, (profile: SfaProfile) => `${profile.id}-${profile.updatedAt}`)
        if (this.catalog.profiles.length === 0) {
          Text('没有配置').fontColor(this.palette().textSecondary).margin({ top: 64 })
          Button('新建配置').onClick(() => { this.showAddProfile = true })
        }
      }.width('100%').padding({ left: 16, right: 16, bottom: 32 })
    }.layoutWeight(1).align(Alignment.Top)
  }

  @Builder
  editor() {
    Scroll() {
      Column({ space: 16 }) {
        Blank().height(this.topInset() + 64)
        Text('基本信息').fontSize(14).fontColor(this.palette().accent).width('100%')
        TextInput({ placeholder: '名称', text: this.draftName }).height(52)
          .onChange((value: string) => { this.draftName = value })
        Text('配置类型').fontSize(14).fontColor(this.palette().accent).width('100%')
        Row({ space: 12 }) {
          Button('本地').layoutWeight(1).backgroundColor(this.draftKind === 'local' ? this.palette().accentSoft : this.palette().surface)
            .fontColor(this.palette().textPrimary).onClick(() => { this.draftKind = 'local' })
          Button('远程').layoutWeight(1).backgroundColor(this.draftKind === 'remote' ? this.palette().accentSoft : this.palette().surface)
            .fontColor(this.palette().textPrimary).onClick(() => { this.draftKind = 'remote' })
        }.width('100%')
        if (this.draftKind === 'remote') {
          TextInput({ placeholder: 'URL', text: this.draftUrl }).height(52).onChange((value: string) => { this.draftUrl = value })
          Text('下载完整 sing-box 配置，不进行 Clash/URI 转换。').fontSize(13).fontColor(this.palette().textSecondary).width('100%')
        } else {
          Text('配置来源').fontSize(14).fontColor(this.palette().accent).width('100%')
          Button('从文件导入').width('100%').onClick(() => this.importFile())
          TextArea({ placeholder: 'sing-box JSON 配置', text: this.draftContent }).height(360).fontSize(13)
            .fontFamily('monospace').maxLength(4194304).onChange((value: string) => { this.draftContent = value })
          Button('格式化').onClick(() => {
            try { this.draftContent = JSON.stringify(JSON.parse(this.draftContent), null, 2) }
            catch (_) { this.toast('JSON 格式无效') }
          })
        }
        if (this.busy) LoadingProgress().width(32).height(32)
      }.width('100%').padding({ left: 20, right: 20, bottom: 32 })
    }.layoutWeight(1).align(Alignment.Top)
  }

  @Builder
  groupNode(group: GroupInfo, item: GroupItem) {
    Column({ space: 4 }) {
      Text(item.tag).fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.palette().textPrimary)
        .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Row() {
        Text(this.nodeType(item.type)).fontSize(12).fontColor(this.palette().textSecondary).layoutWeight(1)
        if (item.urlTestDelay) Text(item.urlTestDelay.toString() + 'ms').fontSize(12).fontWeight(FontWeight.Bold)
          .fontColor(delayColor(item.urlTestDelay))
      }.width('100%')
    }.width('100%').height(64).padding(12).borderRadius(12)
      .backgroundColor(group.selected === item.tag ? this.palette().accentSoft : this.palette().background)
      .onClick(() => { if (group.selectable) this.control({ action: 'select', group: group.tag, outbound: item.tag }) })
  }

  @Builder
  groupsPage() {
    Column() {
      Row() {
        Text('组').fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.palette().textPrimary).layoutWeight(1)
        Button() { this.icon('unfold', 24) }.width(44).height(44).backgroundColor(Color.Transparent)
          .accessibilityText('全部展开或折叠').onClick(() => {
            this.expandedGroups = this.expandedGroups.length === this.groups.length ? [] : this.groups.map((group: GroupInfo) => group.tag)
          })
      }.width('100%').padding({ left: 24, right: 16, top: 16, bottom: 12 })
      Scroll() {
        Column({ space: 12 }) {
          ForEach(this.groups, (group: GroupInfo) => {
            Column({ space: 12 }) {
              Row({ space: 8 }) {
                Text(group.tag).fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.palette().textPrimary)
                Text(this.nodeType(group.type)).fontSize(14).fontColor(this.palette().textSecondary).layoutWeight(1)
                Text(group.items.length.toString()).fontSize(12).padding({ left: 8, right: 8, top: 2, bottom: 2 })
                  .backgroundColor(this.palette().surfaceMuted).borderRadius(12).fontColor(this.palette().textPrimary)
                Button() { this.icon('speed', 22) }.width(36).height(36).backgroundColor(Color.Transparent)
                  .accessibilityText('测速 ' + group.tag).enabled(this.testingGroup.length === 0)
                  .onClick(() => this.refreshGroupDelays(group.tag))
                Button() { this.icon(this.expandedGroups.includes(group.tag) ? 'up' : 'down', 22) }
                  .width(28).height(36).backgroundColor(Color.Transparent).accessibilityText('展开或折叠 ' + group.tag)
                  .onClick(() => this.toggleGroup(group.tag))
              }.width('100%')
              if (this.expandedGroups.includes(group.tag)) {
                Grid() {
                  ForEach(group.items, (item: GroupItem) => { GridItem() { this.groupNode(group, item) } }, (item: GroupItem) => item.tag)
                }.columnsTemplate('1fr 1fr').rowsGap(10).columnsGap(10).height(Math.ceil(group.items.length / 2) * 74 - 10)
              } else {
                Row({ space: 4 }) {
                  ForEach(group.items, (item: GroupItem) => {
                    Stack() {
                      if (group.selected === item.tag) Circle().width(4).height(4).fill(Color.White)
                    }.width(11).height(11).borderRadius(4).backgroundColor(delayColor(item.urlTestDelay || 0))
                  }, (item: GroupItem) => item.tag)
                }.width('100%').height(22).onClick(() => this.toggleGroup(group.tag))
              }
            }.width('100%').padding(16).borderRadius(16)
              .backgroundColor(this.palette() === DARK_PALETTE ? '#8025262B' : '#80EEEDF5')
          }, (group: GroupInfo) => group.tag + ':' + group.selected + ':' + group.items.map((item: GroupItem) => item.tag + (item.urlTestDelay || 0).toString()).join('|'))
          Text('延迟每 30 秒刷新').fontSize(12).fontColor(this.palette().textSecondary).padding(8)
        }.width('100%').padding({ left: 16, right: 16, bottom: 32 })
      }.layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)
    }.width('100%').height('100%')
  }

  @Builder
  logsPage() {
    Column({ space: 10 }) {
      TextInput({ placeholder: '搜索日志', text: this.logQuery }).height(44)
        .onChange((value: string) => { this.logQuery = value })
      Row({ space: 8 }) {
        ForEach(['all', 'info', 'warn', 'error', 'debug'], (level: string) => {
          Text(level === 'all' ? '全部' : level).fontSize(12).fontColor(this.palette().textPrimary)
            .padding(8).borderRadius(16).backgroundColor(this.logLevel === level ? this.palette().accentSoft : Color.Transparent)
            .onClick(() => { this.logLevel = level })
        }, (level: string) => level)
      }.width('100%')
      Scroll() {
        Column({ space: 8 }) {
          ForEach(this.logs.filter((line: string) => line.toLowerCase().includes(this.logQuery.toLowerCase()) &&
            (this.logLevel === 'all' || line.startsWith(this.logLevel + ' '))), (line: string) => {
            Text(line).fontSize(12).fontFamily('monospace').lineHeight(18).fontColor(this.palette().textPrimary).width('100%')
              .copyOption(CopyOptions.InApp)
          }, (_line: string, index: number) => index.toString())
          if (this.logs.length === 0) Text('暂无日志').fontColor(this.palette().textSecondary).margin({ top: 48 })
        }.width('100%').padding({ bottom: 100 })
      }.layoutWeight(1)
    }.layoutWeight(1).padding({ left: 16, right: 16, top: this.topInset() + 68, bottom: this.bottomInset() })
  }

  @Builder
  settingRow(title: string, detail: string, target: string) {
    Row() {
      Column({ space: 5 }) {
        Text(title).fontSize(16).fontColor(this.palette().textPrimary)
        if (detail.length > 0) Text(detail).fontSize(13).fontColor(this.palette().textSecondary)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text('›').fontSize(24).fontColor(this.palette().textSecondary)
    }.width('100%').constraintSize({ minHeight: 72 }).padding(16)
      .onClick(() => { this.page = target; if (target === 'applications') this.loadApplications(); if (target === 'ssid') this.readCurrentSsid() })
  }

  @Builder
  settingsPage() {
    Scroll() {
      Column({ space: 16 }) {
        Blank().height(this.topInset() + 64)
        Column() {
          this.settingRow('应用设置', '主题、透明效果', 'appearance')
          this.settingRow('配置', `${this.catalog.profiles.length} 个配置`, 'profiles')
          this.settingRow('按需连接', '连接排除的 Wi-Fi 时挂起，离开后恢复', 'ssid')
          this.settingRow('分应用代理', '启用分应用、绕行模式', 'applications')
          this.settingRow('仪表盘项目', '显示或隐藏卡片', 'cards')
        }.width('100%').backgroundColor(this.palette().surfaceElevated).borderRadius(12)
        Column() {
          this.settingRow('开源项目与源码地址', '项目来源、版本与许可证', 'sources')
          this.settingRow('关于', 'sing-box 1.14.3', 'about')
        }.width('100%').backgroundColor(this.palette().surfaceElevated).borderRadius(12)
      }.width('100%').padding({ left: 16, right: 16, bottom: 100 })
    }.layoutWeight(1).align(Alignment.Top)
  }

  @Builder
  toolsPage() {
    Scroll() {
      Column({ space: 16 }) {
        Blank().height(this.topInset() + 64)
        this.settingRow('编辑配置', '查看和编辑完整 sing-box JSON', 'profiles')
        Text('DNS 查询').fontSize(16).fontColor(this.palette().textPrimary).width('100%')
        TextInput({ text: this.host, placeholder: '域名' }).onChange((value: string) => { this.host = value })
        Button('查询').enabled(!this.busy).onClick(async () => {
          try {
            this.busy = true
            const addresses: connection.NetAddress[] = await connection.getAddressesByName(this.host.trim())
            this.toolResult = addresses.map((address: connection.NetAddress) => address.address).join('\n')
          } catch (failure) { this.toolResult = failure instanceof Error ? failure.message : '查询失败' }
          finally { this.busy = false }
        })
        Text(this.toolResult).fontSize(14).fontColor(this.palette().textPrimary).width('100%').copyOption(CopyOptions.InApp)
      }.width('100%').padding({ left: 20, right: 20, bottom: 100 })
    }.layoutWeight(1).align(Alignment.Top)
  }

  private topInset(): number { return this.getUIContext().px2vp(this.topInsetPx) }
  private bottomInset(): number { return this.getUIContext().px2vp(this.bottomInsetPx) }

  private async syncWindowTheme(): Promise<void> {
    try {
      const win: window.Window = await window.getLastWindow(this.context())
      const dark: boolean = this.palette() === DARK_PALETTE
      await win.setWindowSystemBarProperties({ statusBarColor: '#00000000', navigationBarColor: '#00000000',
        statusBarContentColor: dark ? '#FFFFFFFF' : '#FF17171C', navigationBarContentColor: dark ? '#FFFFFFFF' : '#FF17171C' })
    } catch (_) { }
  }

  private async scanProfile(): Promise<void> {
    this.showAddProfile = false
    try {
      const result: scanBarcode.ScanResult = await scanBarcode.startScanForResult(this.context(), {
        scanTypes: [scanCore.ScanType.QR_CODE], enableAlbum: true
      })
      if (!result.originalValue) return
      let profile: ScannedProfile
      try { profile = parseProfileQr(result.originalValue) }
      catch (_) {
        this.getUIContext().getPromptAction().showDialog({ title: '注意', message: '不是有效的 sing-box 远程配置链接', buttons: [{ text: '确定', color: this.palette().accent }] })
        return
      }
      this.editProfile()
      this.draftName = profile.name; this.draftKind = profile.kind
      this.draftUrl = profile.url; this.draftContent = profile.content
      this.toast('已识别配置，请检查后保存')
    } catch (failure) { this.toast(failure instanceof Error ? failure.message : '扫码已取消或不可用') }
    finally { this.syncWindowTheme() }
  }

  @Builder
  addProfileSheet() {
    Column({ space: 6 }) {
      Text('添加配置文件').fontSize(22).fontColor(this.palette().textPrimary).width('100%').padding({ top: 14, bottom: 12 })
      Row({ space: 18 }) {
        this.icon('upload', 24)
        Column({ space: 4 }) { Text('从文件导入').fontColor(this.palette().textPrimary); Text('从本地文件导入配置').fontSize(13).fontColor(this.palette().textSecondary) }.alignItems(HorizontalAlign.Start)
      }.width('100%').height(72).onClick(() => { this.showAddProfile = false; this.editProfile(); this.importFile() })
      Row({ space: 18 }) {
        Text('▦').fontSize(27).fontColor(this.palette().textPrimary)
        Column({ space: 4 }) { Text('扫描二维码').fontColor(this.palette().textPrimary); Text('扫描配置二维码').fontSize(13).fontColor(this.palette().textSecondary) }.alignItems(HorizontalAlign.Start)
      }.width('100%').height(72).onClick(() => this.scanProfile())
      Row({ space: 18 }) {
        this.icon('folder', 24)
        Column({ space: 4 }) { Text('手动创建').fontColor(this.palette().textPrimary); Text('从头创建新配置文件').fontSize(13).fontColor(this.palette().textSecondary) }.alignItems(HorizontalAlign.Start)
      }.width('100%').height(72).onClick(() => { this.showAddProfile = false; this.editProfile() })
    }.width('100%').padding({ left: 24, right: 24, bottom: this.bottomInset() + 16 })
  }

  private async importApplications(): Promise<void> {
    try {
      const files: string[] = await new picker.DocumentViewPicker(this.context()).select({ maxSelectNumber: 1 })
      if (files.length === 0) return
      const names: string[] = (await readLocalDocument(files[0])).split(/\r?\n/).map((line: string) => line.trim()).filter((line: string) => line.length > 0 && !line.startsWith('ID:'))
      if (names.length > 3000) throw new Error('应用清单过大')
      const apps: SelectableApplication[] = []
      for (const name of names) {
        try {
          const valid: string = validateApplicationBundleName(name)
          if (!apps.some((app: SelectableApplication) => app.bundleName === valid)) apps.push({ bundleName: valid, label: valid })
        } catch (_) { }
      }
      if (apps.length === 0) throw new Error('清单中没有有效鸿蒙包名；请使用每行一个包名的文本文件')
      this.prefs?.putSync('application-catalog', JSON.stringify(apps))
      await this.prefs?.flush()
      this.applicationCatalog = apps
      this.applicationCatalogState = 'imported'
      this.applicationMessage = `用户导入 ${apps.length} 个包名，未验证是否安装`
    } catch (failure) { this.applicationMessage = failure instanceof Error ? failure.message : '清单导入失败' }
  }

  private loadSsidPolicy(): void {
    try {
      const policy = normalizeSsidPolicy(JSON.parse(fileIo.readTextSync(this.context().filesDir + '/ssid-policy.json')))
      this.excludedSsids = policy.excluded || []; this.ssidEnabled = policy.enabled; this.directSsids = policy.direct.join('\n'); this.proxySsids = policy.proxy.join('\n'); this.ssidFallback = policy.fallback
    } catch (_) { }
  }

  private async readCurrentSsid(): Promise<void> {
    try {
      if (!wifiManager.isWifiActive()) { this.currentSsid = ''; this.ssidMessage = '当前未连接 Wi-Fi'; return }
      const linked: wifiManager.WifiLinkedInfo = await wifiManager.getLinkedInfo()
      this.currentSsid = linked.connState === wifiManager.ConnState.CONNECTED ? linked.ssid : ''
      this.ssidMessage = this.currentSsid ? `当前 Wi-Fi：${this.currentSsid}` : '当前未连接 Wi-Fi 或系统隐藏了 SSID'
    } catch (_) { this.currentSsid = ''; this.ssidMessage = '无法读取 SSID，请检查系统 Wi-Fi 信息权限' }
  }

  private async saveSsidPolicy(): Promise<void> {
    try {
      const policy: SsidPolicy = normalizeSsidPolicy({ enabled: true, direct: [], proxy: [], fallback: 'keep', excluded: this.excludedSsids })
      await writeAtomicText(this.context().filesDir + '/ssid-policy.json', JSON.stringify(policy))
      this.ssidMessage = '已保存，约 5 秒内生效'
    } catch (failure) {
      this.ssidMessage = failure instanceof Error ? failure.message : '保存失败'
      throw new Error(this.ssidMessage)
    }
  }

  private async addExcludedSsid(): Promise<void> {
    const previous: string[] = this.excludedSsids.slice()
    try {
      const next: SsidPolicy = normalizeSsidPolicy({ enabled: true, direct: [], proxy: [], fallback: 'keep', excluded: [...this.excludedSsids, this.draftSsid] })
      this.excludedSsids = next.excluded || []
      await this.saveSsidPolicy()
      this.showSsidEditor = false
    } catch (failure) { this.excludedSsids = previous; this.toast(failure instanceof Error ? failure.message : 'SSID 无效') }
  }

  private async deleteExcludedSsids(): Promise<void> {
    const previous: string[] = this.excludedSsids.slice()
    try {
      this.excludedSsids = this.excludedSsids.filter((ssid: string) => !this.selectedSsids.includes(ssid))
      await this.saveSsidPolicy()
      this.selectedSsids = []
    } catch (_) { this.excludedSsids = previous; this.toast('保存失败，请重试') }
  }

  @Builder
  ssidEditor() {
    Column({ space: 18 }) {
      Text('添加 SSID').fontSize(22).fontColor(this.palette().textPrimary).width('100%')
      TextInput({ text: this.draftSsid, placeholder: 'SSID' }).onChange((value: string) => { this.draftSsid = value }).maxLength(32)
      Row() {
        Button('取消').backgroundColor(Color.Transparent).fontColor(this.palette().textSecondary).onClick(() => { this.showSsidEditor = false })
        Blank()
        Button('提交').backgroundColor(this.palette().accentSoft).fontColor(this.palette().textPrimary).onClick(() => this.addExcludedSsid())
      }.width('100%')
    }.padding(24).width('88%').borderRadius(28).backgroundColor(this.palette().surface)
  }

  @Builder
  ssidPage() {
    Scroll() {
      Column({ space: 18 }) {
        Blank().height(this.topInset() + 64)
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text('排除 SSIDs').fontSize(16).fontColor(this.palette().textPrimary)
            Text('连接排除 SSID 的 Wi-Fi 时，将自动切换为挂起状态；离开后恢复运行。').fontSize(12).fontColor(this.palette().textSecondary)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (this.selectedSsids.length > 0) {
            Button('删除').fontSize(12).backgroundColor(this.palette().surfaceElevated).fontColor(this.palette().textPrimary)
              .onClick(() => this.deleteExcludedSsids())
            Button('全选').fontSize(12).backgroundColor(this.palette().accentSoft).fontColor(this.palette().textPrimary)
              .onClick(() => { this.selectedSsids = this.excludedSsids.slice() })
          } else {
            Button('添加').fontSize(12).backgroundColor(this.palette().surfaceElevated).fontColor(this.palette().textPrimary)
              .onClick(() => { this.draftSsid = ''; this.showSsidEditor = true })
          }
        }.width('100%')
        if (this.excludedSsids.length === 0) {
          Column({ space: 22 }) {
            Stack() { this.icon('folder', 72) }.width(144).height(144).borderRadius(72).backgroundColor(this.palette().surfaceElevated)
            Text('SSIDs 为空').fontSize(14).fontColor(this.palette().textSecondary)
          }.width('100%').padding({ top: 44, bottom: 36 })
        } else {
          ForEach(this.excludedSsids, (ssid: string) => {
            Row() {
              Text(ssid).fontSize(16).fontColor(this.palette().textPrimary).layoutWeight(1)
              if (this.selectedSsids.includes(ssid)) Text('✓').fontColor(this.palette().accent)
            }.width('100%').height(56).padding({ left: 18, right: 18 }).borderRadius(28)
              .backgroundColor(this.selectedSsids.includes(ssid) ? this.palette().accentSoft : this.palette().surfaceElevated)
              .onClick(() => { this.selectedSsids = this.selectedSsids.includes(ssid) ? this.selectedSsids.filter((item: string) => item !== ssid) : [...this.selectedSsids, ssid] })
          }, (ssid: string) => ssid)
        }
        Text(this.ssidMessage).fontSize(12).fontColor(this.palette().textSecondary)
      }.width('100%').padding({ left: 20, right: 20, bottom: this.bottomInset() + 20 })
    }.layoutWeight(1).align(Alignment.Top)
  }

  private async loadApplications(): Promise<void> {
    if (this.applicationLoading) return
    this.applicationLoading = true
    this.applicationMessage = '正在读取系统应用列表'
    try {
      const result: ApplicationCatalogResult = await new ApplicationCatalogService().readInstalledApplications(this.context())
      this.applicationCatalog = result.applications
      this.applicationCatalogState = result.state
      this.applicationMessage = result.message
    } catch (_) {
      this.applicationCatalog = []
      this.applicationCatalogState = 'error'
      this.applicationMessage = '读取应用列表失败，请检查签名权限后重试'
    } finally { this.applicationLoading = false }
  }

  private visibleApplications(): SelectableApplication[] {
    const query: string = this.applicationQuery.toLowerCase()
    return this.applicationCatalog.filter((app: SelectableApplication) =>
      (this.showSystemApplications || !app.systemApp) && (app.label.toLowerCase().includes(query) || app.bundleName.toLowerCase().includes(query)))
  }

  private toggleApplication(bundleName: string): void {
    const next: string[] = this.selectedApplications.includes(bundleName) ?
      this.selectedApplications.filter((name: string) => name !== bundleName) : [...this.selectedApplications, bundleName]
    try {
      normalizeVpnApplicationScope({ mode: 'all', trustedApplications: next })
      this.selectedApplications = next
      this.applicationDirty = true
    } catch (failure) { this.toast(failure instanceof Error ? failure.message : '选择失败') }
  }

  private selectVisibleApplications(invert: boolean): void {
    const names: string[] = this.visibleApplications().map((app: SelectableApplication) => app.bundleName)
    const next: string[] = invert ? invertApplicationSelection(this.selectedApplications, names) :
      [...this.selectedApplications, ...names.filter((name: string) => !this.selectedApplications.includes(name))]
    try {
      normalizeVpnApplicationScope({ mode: 'all', trustedApplications: next })
      this.selectedApplications = next; this.applicationDirty = true
    } catch (failure) { this.toast(failure instanceof Error ? failure.message : '选择失败') }
  }

  private async finishApplications(): Promise<void> {
    if (this.applicationDirty && !await this.saveApplications()) return
    this.page = ''
  }

  private async saveApplications(): Promise<boolean> {
    if (!this.prefs || !this.coordinator || this.busy) return false
    this.busy = true
    try {
      const scope = perAppScope(this.perAppEnabled, this.perAppBypass, this.selectedApplications)
      const running: boolean = this.phase === 'running'
      const profile: SfaProfile | undefined = this.selectedProfile()
      const config: string = running && profile ? prepareLocalConfig(profile.content) : ''
      if (running) this.applyStatus(await this.coordinator.disconnect())
      this.prefs.putSync('application-scope', JSON.stringify(scope))
      this.prefs.putSync('per-app-enabled', this.perAppEnabled)
      this.prefs.putSync('per-app-bypass', this.perAppBypass)
      await this.prefs.flush()
      this.networkSettings.applicationMode = scope.mode
      this.networkSettings.trustedApplications = scope.trustedApplications.slice()
      this.applicationMode = scope.mode
      if (running && config.length > 0) this.applyStatus(await this.coordinator.connect(config, scope))
      this.applicationDirty = false
      return true
    } catch (failure) { this.toast(failure instanceof Error ? failure.message : '保存失败'); return false }
    finally { this.busy = false }
  }

  @Builder
  applicationsPage() {
    Column({ space: 0 }) {
      Blank().height(this.topInset() + 64)
      Row({ space: 8 }) {
        Text('启用分应用').fontSize(13).fontColor(this.palette().textPrimary)
        Toggle({ type: ToggleType.Switch, isOn: this.perAppEnabled }).scale({ x: 0.8, y: 0.8 })
          .onChange((value: boolean) => { this.perAppEnabled = value; this.applicationDirty = true })
        Blank()
        Text('绕行模式').fontSize(13).fontColor(this.palette().textPrimary)
        Toggle({ type: ToggleType.Switch, isOn: this.perAppBypass }).scale({ x: 0.8, y: 0.8 })
          .onChange((value: boolean) => { this.perAppBypass = value; this.applicationDirty = true })
        Button('ⓘ').width(32).height(40).backgroundColor(Color.Transparent).fontColor(this.palette().textSecondary)
          .onClick(() => this.getUIContext().getPromptAction().showDialog({ title: '分应用代理',
            message: 'SSID 挂起优先：挂起时全部应用不代理。\n启用分应用后，勾选的应用走代理；开启绕行模式后，勾选的应用不代理。未选择应用时代理全部。返回时保存并应用。',
            buttons: [{ text: '确定', color: this.palette().accent }] }))
      }.width('100%').padding({ left: 16, right: 10 }).height(64)
      if (this.applicationSearchVisible) {
        TextInput({ text: this.applicationQuery, placeholder: '搜索应用名称或包名' }).margin({ left: 16, right: 16, bottom: 8 })
          .onChange((value: string) => { this.applicationQuery = value })
      }
      Divider().color(this.palette().border)
      if (this.applicationLoading) {
        LoadingProgress().width(36).height(36).margin(24)
      }
      List({ space: 0 }) {
        ForEach(this.visibleApplications(), (app: SelectableApplication) => {
          ListItem() {
            Row({ space: 14 }) {
              Stack() {
                Text(app.label.substring(0, 1)).fontSize(18).fontColor(this.palette().accent)
                if (app.icon) Image(app.icon).width(36).height(36).borderRadius(8)
              }.width(36).height(36).borderRadius(8).backgroundColor(this.palette().surfaceElevated)
              Column({ space: 4 }) {
                Text(app.label).fontSize(15).fontColor(this.palette().textPrimary).maxLines(1)
                Text(app.bundleName).fontSize(11).fontColor(this.palette().textSecondary).maxLines(1)
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Checkbox({ name: app.bundleName }).select(this.selectedApplications.includes(app.bundleName))
                .onChange((checked: boolean) => { if (checked !== this.selectedApplications.includes(app.bundleName)) this.toggleApplication(app.bundleName) })
            }.width('100%').height(72).padding({ left: 16, right: 10 })
          }
        }, (app: SelectableApplication) => app.bundleName)
      }.layoutWeight(1).width('100%').divider({ strokeWidth: 0.5, color: this.palette().border, startMargin: 66 })
      Text(this.applicationMessage).fontSize(12).fontColor(this.palette().textSecondary).width('100%').padding({ left: 16, right: 16, top: 10 })
      Row() {
        Text(`已选 ${this.selectedApplications.length} 个`).fontSize(12).fontColor(this.palette().textSecondary).layoutWeight(1)
        Button('完成').fontSize(14).backgroundColor(Color.Transparent).fontColor(this.palette().accent)
          .enabled(!this.busy).onClick(() => this.finishApplications())
      }.width('100%').padding({ left: 16, right: 12, bottom: this.bottomInset() + 12 })
    }.layoutWeight(1).width('100%')
  }

  @Builder
  connectionsPage() {
    Column({ space: 10 }) {
      TextInput({ text: this.connectionQuery, placeholder: '搜索域名、地址或出站' }).onChange((value: string) => { this.connectionQuery = value })
      Text(`活动连接 ${this.connectionCount} · 最多显示 100 条`).fontSize(13).fontColor(this.palette().textSecondary)
      List({ space: 10 }) {
        ForEach(this.liveConnections.filter((item: LiveConnection) => `${item.domain} ${item.destination} ${item.outbound}`.toLowerCase().includes(this.connectionQuery.toLowerCase())), (item: LiveConnection) => {
          ListItem() {
            Column({ space: 6 }) {
              Row() {
                Text(`${(item.network || '').toUpperCase()}  ${item.domain || item.destination || ''}`).layoutWeight(1).fontSize(14).fontColor(this.palette().textPrimary)
                Button('关闭').fontSize(12).height(30).enabled(!this.busy).onClick(() => this.control({ action: 'close-connection', id: item.id }))
              }
              Text(`↑ ${this.formatBytes(item.uplinkTotal || 0)}   ↓ ${this.formatBytes(item.downlinkTotal || 0)}`).fontSize(13).fontColor(this.palette().textSecondary)
              Text(`${item.inbound || ''} → ${item.outbound || ''}`).fontSize(13).fontColor(this.palette().textSecondary)
              if (item.rule) Text(item.rule).fontSize(12).fontColor(this.palette().textSecondary).maxLines(2)
            }.width('100%').alignItems(HorizontalAlign.Start).padding(14).backgroundColor(this.palette().surfaceElevated).borderRadius(12)
          }
        }, (item: LiveConnection) => `${item.id}:${item.uplinkTotal}:${item.downlinkTotal}`)
      }.layoutWeight(1).width('100%')
    }.padding({ left: 16, right: 16, top: this.topInset() + 68, bottom: this.bottomInset() + 20 }).layoutWeight(1)
  }

  @Builder
  appearancePage() {
    Column({ space: 20 }) {
      Text('主题').fontSize(16).fontColor(this.palette().textPrimary).width('100%')
      Row({ space: 8 }) {
        ForEach(['system', 'light', 'dark'], (theme: string) => {
          Button(theme === 'system' ? '跟随系统' : (theme === 'light' ? '浅色' : '深色')).layoutWeight(1)
            .fontSize(14).backgroundColor(this.theme === theme ? this.palette().accentSoft : this.palette().surface)
            .fontColor(this.palette().textPrimary).onClick(() => { this.theme = theme; this.saveAppearance() })
        }, (theme: string) => theme)
      }.width('100%')
      Row() {
        Text('减少透明效果').fontSize(16).fontColor(this.palette().textPrimary).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.reduceTransparency }).onChange((value: boolean) => {
          this.reduceTransparency = value; this.saveAppearance()
        })
      }.width('100%')
    }.padding({ left: 20, right: 20, top: this.topInset() + 84, bottom: this.bottomInset() + 20 }).layoutWeight(1)
  }

  @Builder
  cardsPage() {
    Column({ space: 18 }) {
      ForEach(['traffic', 'connections', 'mode', 'profiles', 'groups'], (card: string) => {
        Row() {
          Text(card === 'traffic' ? '流量' : card === 'connections' ? '连接' : card === 'mode' ? '模式' :
            card === 'profiles' ? '配置' : '代理组').fontSize(16).fontColor(this.palette().textPrimary).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.visibleCards.includes(card) }).onChange((enabled: boolean) => {
            this.visibleCards = enabled ? [...this.visibleCards, card] : this.visibleCards.filter((value: string) => value !== card)
          })
        }.width('100%')
      }, (card: string) => card)
    }.padding({ left: 20, right: 20, top: this.topInset() + 84, bottom: this.bottomInset() + 20 }).layoutWeight(1)
  }

  private async openSource(url: string): Promise<void> {
    try { await this.context().startAbility({ action: 'ohos.want.action.viewData', uri: url }) }
    catch (_) { this.toast('无法打开浏览器，可长按复制源码地址') }
  }

  @Builder
  sourceEntry(name: string, detail: string, url: string) {
    Column({ space: 8 }) {
      Text(name).fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.palette().textPrimary).width('100%')
      Text(detail).fontSize(13).fontColor(this.palette().textSecondary).width('100%')
      Text(url).fontSize(13).fontColor(this.palette().accent).width('100%').copyOption(CopyOptions.LocalDevice)
      Button('打开源码仓库').fontSize(13).onClick(() => this.openSource(url))
    }.width('100%').padding(16).borderRadius(16).backgroundColor(this.palette().surfaceElevated)
  }

  @Builder
  sourcesPage() {
    Scroll() {
      Column({ space: 16 }) {
        Blank().height(this.topInset() + 64)
        Text('本应用为非官方 HarmonyOS 移植。本版修改后的完整对应源码随 HAP 单独提供；以下为上游及参考项目地址。').fontSize(14).fontColor(this.palette().textSecondary)
        this.sourceEntry('本项目 / sing-box-for-harmonyos', '本移植版本的源码、更新记录和问题反馈。', 'https://github.com/being123321/sing-box-for-harmonyos')
        this.sourceEntry('SagerNet / sing-box', '实际使用内核 1.14.3，含鸿蒙平台适配。GPL-3.0-or-later。', 'https://github.com/SagerNet/sing-box')
        this.sourceEntry('SagerNet / sing-box-for-android', '安卓版 1.14.3 的界面、图标和配置导入格式参考；Android 代码未直接作为鸿蒙界面运行。', 'https://github.com/SagerNet/sing-box-for-android')
        this.sourceEntry('AI-Scarlett / HarmonyOS_VPN', '应用基础工程，基于 b7a75930d2bf 修改。许可证与声明见对应源码包。', 'https://github.com/AI-Scarlett/HarmonyOS_VPN')
        this.sourceEntry('SagerNet / gvisor', '实际使用网络栈，基于 e9989ea3436f 的兼容源码。Apache-2.0。', 'https://github.com/SagerNet/gvisor')
        this.sourceEntry('yourblacksky / ohos_golang_go', '实际使用 OHOS Go 工具链源码，基于 e7463379a44e，并保留本地运行时启动修复。', 'https://github.com/yourblacksky/ohos_golang_go')
        this.sourceEntry('tljk / FlClash-ohos', '用户提供的鸿蒙代理应用调研参考，未作为本版主界面框架。', 'https://github.com/tljk/FlClash-ohos')
        this.sourceEntry('2dust / v2rayNG', '分应用设置界面和启用／绕行语义参考。Android 应用枚举接口不能直接用于鸿蒙。', 'https://github.com/2dust/v2rayNG')
        this.sourceEntry('miramira8295 / TelegramForHarmony', '用户指定的毛玻璃视觉参考；本版采用 ArkUI 原生模糊材质实现。', 'https://github.com/miramira8295/TelegramForHarmony')
        Text('完整许可证及构建来源记录位于对应源码包的 LICENSE、THIRD_PARTY_NOTICES.md 和 BUILD-MANIFEST.json。').fontSize(13).fontColor(this.palette().textSecondary)
      }.width('100%').padding({ left: 16, right: 16, bottom: this.bottomInset() + 24 })
    }.layoutWeight(1).align(Alignment.Top)
  }

  @Builder
  aboutPage() {
    Scroll() {
      Column({ space: 16 }) {
        Blank().height(this.topInset() + 64)
        Image($r('app.media.sfa_launcher')).width(96).height(96)
        Text('sing-box').fontSize(26).fontWeight(FontWeight.Bold).fontColor(this.palette().textPrimary)
        Text('1.14.3 · HarmonyOS 移植版 0.2.9').fontSize(14).fontColor(this.palette().textSecondary)
        Text('非官方鸿蒙移植，未获 SagerNet 官方背书。').fontSize(14).fontColor(this.palette().textSecondary)
        Text('界面参照安卓版 SFA 1.14.3。Android 专有权限、Xposed、USB/IP 等能力不能直接移植；本版工具尚未与安卓版完全一致。')
          .fontSize(13).lineHeight(21).fontColor(this.palette().textSecondary)
        Text('配置在本机加密保存。远程配置仅在你点击保存或更新时下载。VPN 授权由系统处理。')
          .fontSize(13).lineHeight(21).fontColor(this.palette().textSecondary)
        Text('GPL-3.0-or-later · 开源许可与对应源码随安装包单独提供。')
          .fontSize(13).lineHeight(21).fontColor(this.palette().textSecondary)
      }.width('100%').padding(24)
    }.layoutWeight(1).align(Alignment.Top)
  }

  @Builder
  navItem(name: string, label: string) {
    Column({ space: 4 }) {
      Stack() {
        this.icon(name, 24)
      }.width(64).height(32).borderRadius(16).backgroundColor(this.tab === name ? this.palette().accentSoft : Color.Transparent)
      Text(label).fontSize(12).fontColor(this.palette().textPrimary)
    }.layoutWeight(1).height(72).justifyContent(FlexAlign.Center)
      .onClick(() => { this.tab = name; this.page = '' })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (!this.ready) {
          Column({ space: 16 }) {
            LoadingProgress().width(40).height(40)
            Text('正在加载配置').fontColor(this.palette().textSecondary)
          }.layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.page === 'profiles') this.profilesPage()
        else if (this.page === 'editor') this.editor()
        else if (this.page === 'groups') this.groupsPage()
        else if (this.page === 'sources') this.sourcesPage()
        else if (this.page === 'ssid') this.ssidPage()
        else if (this.page === 'connections') this.connectionsPage()
        else if (this.page === 'applications') this.applicationsPage()
        else if (this.page === 'appearance') this.appearancePage()
        else if (this.page === 'about') this.aboutPage()
        else if (this.page === 'cards') this.cardsPage()
        else if (this.tab === 'log') this.logsPage()
        else if (this.tab === 'tools') this.toolsPage()
        else if (this.tab === 'settings') this.settingsPage()
        else this.dashboard()
      }.width('100%').height('100%')

      Column() {
        Blank().height(this.topInset())
        this.appToolbar()
      }.width('100%').height(this.topInset() + 64).position({ x: 0, y: 0 })
        .backgroundColor(this.reduceTransparency ? this.palette().background : Color.Transparent)
        .backgroundEffect({ radius: this.reduceTransparency ? 0 : 20, saturation: 1.35, brightness: 1.02,
            color: this.reduceTransparency ? this.palette().surface : (this.palette() === DARK_PALETTE ? '#301C1D21' : '#18FFFFFF') })

      if (this.page.length === 0 && this.ready) {
        Column({ space: 0 }) {
          if (this.phase === 'running') {
            Row({ space: 10 }) {
              Text(this.suspended ? '挂起中…' : '已启动').fontSize(16).fontColor(this.palette().textPrimary).layoutWeight(1)
              Row({ space: 4 }) { Text(this.connectionCount.toString()).fontSize(14); this.icon('connections', 18) }
                .padding(10).borderRadius(10).backgroundColor(this.palette().accentSoft)
                .onClick(() => { this.page = 'connections' }).accessibilityText('打开连接列表')
              Button() {
                Row({ space: 4 }) { Text(this.groups.length.toString()).fontSize(14).fontColor(this.palette().textPrimary); this.icon('folder', 18) }
              }.height(36).borderRadius(10).backgroundColor(this.palette().accentSoft).accessibilityText('代理组')
                .onClick(() => this.openGroups())
                .bindSheet($$this.showGroups, this.groupsPage(), {
                  height: '100%', showClose: false, dragBar: true,
                  backgroundColor: this.reduceTransparency ? this.palette().surface : (this.palette() === DARK_PALETTE ? '#661C1D21' : '#66F5F3FA'),
                  blurStyle: this.reduceTransparency ? BlurStyle.NONE : BlurStyle.COMPONENT_THICK
                })
              Button(this.elapsed() + ' ■').fontSize(14).height(36).borderRadius(10)
                .fontColor(this.palette().textPrimary).backgroundColor(this.palette().accentSoft)
                .onClick(() => this.toggleService()).accessibilityText('停止')
            }.width('100%').height(56).padding({ left: 16, right: 16 }).borderRadius(22).clip(true)
          .backgroundColor(this.reduceTransparency ? this.palette().surface : Color.Transparent)
          .backgroundEffect({ radius: this.reduceTransparency ? 0 : 20, saturation: 1.35, brightness: 1.02,
            color: this.reduceTransparency ? this.palette().surface : (this.palette() === DARK_PALETTE ? '#301C1D21' : '#18FFFFFF') })
          } else {
          Row() {
            Blank()
            Button() { this.icon(this.phase === 'running' ? 'stop' : 'play', 24) }
              .width(56).height(56).borderRadius(16)
              .backgroundColor(this.palette().accentSoft)
              .shadow({ radius: 8, color: this.palette().shadow, offsetY: 4 })
              .enabled(!this.busy || this.phase === 'running')
              .accessibilityText(this.phase === 'running' ? '停止' : '启动')
              .onClick(() => this.toggleService())
          }.width('100%').padding({ right: 16, bottom: 16 })
          }
          Row() {
            this.navItem('dashboard', '仪表')
            this.navItem('log', '日志')
            this.navItem('tools', '工具')
            this.navItem('settings', '设置')
          }.width('100%').height(72).borderRadius(36)
          .border({ width: 0.8, color: this.palette() === DARK_PALETTE ? '#44FFFFFF' : '#99FFFFFF' }).shadow({ radius: 16, color: '#18000000', offsetY: 4 })
          .clip(true).margin({ top: 6, bottom: this.bottomInset() + 8 })
          .backgroundColor(this.reduceTransparency ? this.palette().surface : Color.Transparent)
          .backgroundEffect({ radius: this.reduceTransparency ? 0 : 20, saturation: 1.35, brightness: 1.02,
            color: this.reduceTransparency ? this.palette().surface : (this.palette() === DARK_PALETTE ? '#301C1D21' : '#18FFFFFF') })
        }.width('100%').padding({ left: 12, right: 12 })
      }
      if (this.showSsidEditor) {
        Stack({ alignContent: Alignment.Center }) {
          this.ssidEditor()
        }.width('100%').height('100%').backgroundColor('#66000000').align(Alignment.Center)
      }
    }.width('100%').height('100%').backgroundColor(this.palette().background)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.showAddProfile, this.addProfileSheet(), { height: SheetSize.FIT_CONTENT, dragBar: true, showClose: false,
        backgroundColor: this.reduceTransparency ? this.palette().background : (this.palette() === DARK_PALETTE ? '#661C1D21' : '#66F5F3FA'),
        blurStyle: this.reduceTransparency ? BlurStyle.NONE : BlurStyle.COMPONENT_THIN })
  }
}





