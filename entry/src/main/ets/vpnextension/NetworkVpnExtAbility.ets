import { physicalNetworkSignature } from '../services/PhysicalNetwork'
import { UiActivityLease, isUiActive, telemetryInterval, heartbeatInterval } from '../domain/RuntimeActivity'
import { wifiManager } from '@kit.ConnectivityKit'
import { fileIo, WatchEvent } from '@kit.CoreFileKit'
import { normalizeSsidPolicy, shouldSuspendSsid } from '../domain/SsidPolicy'
import { Want } from '@kit.AbilityKit'
import { connection, vpnExtension, VpnExtensionAbility } from '@kit.NetworkKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { CoreGateway, CoreInfo, CoreStatus, ValidationResult } from '../core/CoreGateway'
import {
  classifyCoreStartupFailure,
  CoreStartupDiagnostic,
  formatCoreStartupFailure,
  startupFailureDetail
} from '../domain/CoreStartupDiagnostic'
import {
  classifyProxyUrlTestFailure,
  formatProxyUrlTestFailure,
  ProxyUrlTestDiagnostic
} from '../domain/ProxyUrlTestDiagnostic'
import { VpnApplicationScope } from '../domain/NetworkSettings'
import { VpnRuntimeBridgeStore } from '../services/VpnRuntimeBridgeStore'
import { VpnRuntimeConfigStore } from '../services/VpnRuntimeConfigStore'
import {
  decideRuntimeCommand,
  VpnRuntimeCommand,
  VpnRuntimeCommandDecision,
  VpnRuntimeResponse,
  VpnRuntimeState,
  VpnRuntimeStatus,
  VPN_RUNTIME_PROTOCOL_CURRENT
} from '../services/VpnRuntimeProtocol'

const DOMAIN: number = 0x0000
const TAG: string = 'HarmonyNetVpn'
const TUN_IPV4_ADDRESS: string = '172.19.0.1'
const TUN_IPV4_PREFIX_LENGTH: number = 30
const TUN_IPV4_DNS_ADDRESS: string = '172.19.0.2'
const TUN_IPV6_ADDRESS: string = 'fdfe:dcba:9876::1'
const TUN_IPV6_PREFIX_LENGTH: number = 126
const TUN_IPV6_DNS_ADDRESS: string = 'fdfe:dcba:9876::2'
const TUN_INTERFACE: string = 'vpn-tun'
const TUN_MTU: number = 1400
const HEARTBEAT_INTERVAL_MS: number = 1000
const COMMAND_POLL_INTERVAL_MS: number = 250
const COMMAND_WATCHDOG_INTERVAL_MS: number = 2000

interface RuntimeTunInbound {
  type: string
  address: string[]
}

interface RuntimeRouteRule {
  action: string
  ip_version?: number
}

interface RuntimeRoute {
  rules: RuntimeRouteRule[]
}

interface RuntimeCoreConfig {
  inbounds: RuntimeTunInbound[]
  route: RuntimeRoute
}

/**
 * Owns the complete API 22+ VPN lifecycle.
 *
 * The ordering is security-critical: protectProcessNet() must complete before
 * the Go core is initialized because libbox initialization may create sockets.
 * A TUN is never left alive when validation or core startup fails.
 *
 * This extension runs in a different process from UIAbility. Runtime state and
 * URLTest requests therefore cross that boundary only through atomic files in
 * the private application sandbox; native Go globals are never treated as IPC.
 */
interface SsidRuntimeModes { modes?: string[]; mode?: string }
interface SuspendedTraffic { uplinkTotal: number; downlinkTotal: number }
interface SuspendedSnapshot { suspended: boolean; sampledAt: number; connections: Object[]; status: SuspendedTraffic }

export default class NetworkVpnExtAbility extends VpnExtensionAbility {
  private vpnConnection: vpnExtension.VpnConnection | null = null
  private core: CoreGateway = new CoreGateway()
  private runtimeBridge: VpnRuntimeBridgeStore | null = null
  private startupTask: Promise<void> | null = null
  private shutdownTask: Promise<void> | null = null
  private stopRequested: boolean = false
  private coreInitialized: boolean = false
  private coreStarted: boolean = false
  private tunFd: number = -1
  private stage: string = 'idle'
  private sessionId: string = ''
  private runtimeState: VpnRuntimeState = 'starting'
  private runtimeVersion: string = ''
  private runtimeError: string = ''
  private runtimeUploadBytes: number = 0
  private runtimeDownloadBytes: number = 0
  private runtimeActiveConnections: number = 0
  private runtimeSelectedOutboundTag: string = ''
  private runtimeSnapshotJson: string = '{}'
  private heartbeatTimer: number = 0
  private commandTimer: number = 0
  private heartbeatBusy: boolean = false
  private healthCheckBusy: boolean = false
  private commandBusy: boolean = false
  private lastCommandId: string = ''
  private stoppedAcknowledged: boolean = false
  private commandWatcher: fileIo.Watcher | null = null
  private policyWatcher: fileIo.Watcher | null = null
  private commandPending: boolean = false
  private networkMonitor: connection.NetConnection | null = null
  private networkTimer: number = 0
  private networkRetryTimer: number = 0
  private networkRevision: number = 0
  private networkChangePending: boolean = false
  private lastNetworkSignature: string = ''
  private capabilityKeys: Map<number, string> = new Map()
  private networkEventsReady: boolean = false
  private wifiEventsReady: boolean = false
  private lastHealthSampleAt: number = 0
  private readonly wifiChanged = (state: number): void => { this.queueNetworkChange() }

  private uiActive(): boolean {
    try {
      return isUiActive(JSON.parse(fileIo.readTextSync(this.context.filesDir + '/runtime/ui-activity.json')) as UiActivityLease, Date.now())
    } catch (_) { return false }
  }

  private scheduleHeartbeat(delay: number): void {
    if (this.stopRequested || this.stoppedAcknowledged) return
    if (this.heartbeatTimer !== 0) clearTimeout(this.heartbeatTimer)
    this.heartbeatTimer = setTimeout(() => {
      this.heartbeatTimer = 0
      this.publishHeartbeat().catch(() => {}).finally(() => {
        if (!this.stopRequested && !this.stoppedAcknowledged && this.heartbeatTimer === 0) this.scheduleHeartbeat(heartbeatInterval(this.uiActive()))
      })
    }, delay)
  }

  private queueNetworkChange(): void {
    if (this.stopRequested || this.stoppedAcknowledged) return
    this.networkChangePending = true
    this.networkRevision++
    this.lastSsidCheck = 0
    if (this.networkTimer !== 0) clearTimeout(this.networkTimer)
    this.networkTimer = setTimeout(() => {
      this.networkTimer = 0
      this.checkCoreHealth().catch(() => {})
    }, 200)
    // SSID/validation state can settle after the first Wi-Fi callback.
    if (this.networkRetryTimer !== 0) clearTimeout(this.networkRetryTimer)
    this.networkRetryTimer = setTimeout(() => {
      this.networkRetryTimer = 0
      this.lastSsidCheck = 0
      this.networkChangePending = true
      this.networkRevision++
      this.checkCoreHealth().catch(() => {})
    }, 1200)
  }

  private async startNetworkObservers(): Promise<void> {
    try { this.lastNetworkSignature = await physicalNetworkSignature() } catch (_) { }
    if (this.stopRequested) return
    try { wifiManager.on('wifiConnectionChange', this.wifiChanged); this.wifiEventsReady = true } catch (_) { }
    try {
      const monitor: connection.NetConnection = connection.createNetConnection({ netCapabilities: {
        bearerTypes: [connection.NetBearType.BEARER_WIFI, connection.NetBearType.BEARER_CELLULAR],
        networkCap: [connection.NetCap.NET_CAPABILITY_INTERNET, connection.NetCap.NET_CAPABILITY_NOT_VPN]
      } })
      this.networkMonitor = monitor
      monitor.on('netAvailable', () => this.queueNetworkChange())
      monitor.on('netLost', () => this.queueNetworkChange())
      monitor.on('netCapabilitiesChange', (info: connection.NetCapabilityInfo): void => {
        const key: string = (info.netCap.networkCap || []).slice().sort().join(',') + '|' + info.netCap.bearerTypes.slice().sort().join(',')
        if (this.capabilityKeys.get(info.netHandle.netId) === key) return
        this.capabilityKeys.set(info.netHandle.netId, key)
        this.queueNetworkChange()
      })
      monitor.on('netConnectionPropertiesChange', () => this.queueNetworkChange())
      monitor.register((error) => {
        if (this.networkMonitor !== monitor || this.stopRequested || this.stoppedAcknowledged) {
          try { monitor.unregister(() => {}) } catch (_) { }
          return
        }
        this.networkEventsReady = !error
      })
    } catch (_) { this.networkEventsReady = false }
  }

  private stopNetworkObservers(): void {
    if (this.networkTimer !== 0) clearTimeout(this.networkTimer)
    if (this.networkRetryTimer !== 0) clearTimeout(this.networkRetryTimer)
    this.networkTimer = 0; this.networkRetryTimer = 0
    if (this.wifiEventsReady) { try { wifiManager.off('wifiConnectionChange', this.wifiChanged) } catch (_) { } }
    this.wifiEventsReady = false; this.networkEventsReady = false
    this.capabilityKeys.clear()
    const monitor: connection.NetConnection | null = this.networkMonitor
    this.networkMonitor = null
    if (monitor !== null) { try { monitor.unregister(() => {}) } catch (_) { } }
  }

  onCreate(want: Want): void {
    this.stopRequested = false
    this.stoppedAcknowledged = false
    this.lastCommandId = ''
    this.stage = 'create-connection'
    this.runtimeBridge = new VpnRuntimeBridgeStore(this.context.filesDir)
    try {
      this.vpnConnection = vpnExtension.createVpnConnection(this.context)
    } catch (_) {
      hilog.error(DOMAIN, TAG, 'VPN connection object creation failed')
    }
    hilog.info(DOMAIN, TAG, 'VPN extension lifecycle started')
    this.startupTask = this.startLifecycle()
  }

  onDestroy(): void {
    this.stopRequested = true
    this.stopBackgroundTasks()
    // Lifecycle destruction is only a last-resort cleanup path. Normal UI
    // disconnect sends a same-session stop command and waits for the stopped
    // status before it asks the system to destroy this Extension.
    hilog.info(DOMAIN, TAG, 'VPN extension fallback shutdown requested')
    if (this.stoppedAcknowledged) {
      // Core/TUN cleanup and its bridge acknowledgement already completed.
      // Re-publishing here could overwrite the UI's subsequent marker that
      // the system Extension lifecycle has also been finalized.
      return
    }
    this.beginShutdown().catch(() => {
      hilog.error(DOMAIN, TAG, 'VPN extension shutdown did not complete cleanly')
    })
  }

  /**
   * The generated sing-box TUN and IPv6 reject rule are the single source of
   * truth for the HarmonyOS VPN family. Both families are always captured;
   * "IPv6 off" means reject inside the TUN so physical IPv6 cannot bypass it.
   */
  private readIpv6Enabled(configJson: string): boolean {
    let decoded: RuntimeCoreConfig
    try {
      decoded = JSON.parse(configJson) as RuntimeCoreConfig
    } catch (_) {
      throw new Error('运行配置不是有效 JSON')
    }
    if (!Array.isArray(decoded.inbounds)) throw new Error('运行配置缺少 TUN 入站')
    if (!decoded.route || !Array.isArray(decoded.route.rules)) throw new Error('运行配置缺少路由规则')
    let tun: RuntimeTunInbound | null = null
    for (let index: number = 0; index < decoded.inbounds.length; index++) {
      if (decoded.inbounds[index].type === 'tun') {
        if (tun !== null) throw new Error('运行配置包含多个 TUN 入站')
        tun = decoded.inbounds[index]
      }
    }
    if (tun === null || !Array.isArray(tun.address)) throw new Error('运行配置缺少 TUN 地址')
    let hasIpv4: boolean = false
    let hasIpv6: boolean = false
    for (let index: number = 0; index < tun.address.length; index++) {
      const address: string = tun.address[index]
      if (address === `${TUN_IPV4_ADDRESS}/${TUN_IPV4_PREFIX_LENGTH}`) {
        hasIpv4 = true
      } else if (address === `${TUN_IPV6_ADDRESS}/${TUN_IPV6_PREFIX_LENGTH}`) {
        hasIpv6 = true
      } else {
        throw new Error('运行配置包含未授权的 TUN 地址')
      }
    }
    if (!hasIpv4 || !hasIpv6) throw new Error('运行配置必须接管 IPv4 与 IPv6')
    let ipv6Rejected: boolean = false
    for (let index: number = 0; index < decoded.route.rules.length; index++) {
      const rule: RuntimeRouteRule = decoded.route.rules[index]
      if (rule.ip_version === 6 && rule.action === 'reject') ipv6Rejected = true
    }
    return !ipv6Rejected
  }

  private buildVpnConfig(ipv6Enabled: boolean,
    applicationScope: VpnApplicationScope): vpnExtension.VpnConfig {
    const config: vpnExtension.VpnConfig = {
      addresses: [{
        address: {
          address: TUN_IPV4_ADDRESS,
          family: 1
        },
        prefixLength: TUN_IPV4_PREFIX_LENGTH
      }, {
        address: {
          address: TUN_IPV6_ADDRESS,
          family: 2
        },
        prefixLength: TUN_IPV6_PREFIX_LENGTH
      }],
      routes: [{
        interface: TUN_INTERFACE,
        destination: {
          address: {
            address: '0.0.0.0',
            family: 1
          },
          prefixLength: 0
        },
        gateway: {
          address: '0.0.0.0',
          family: 1
        },
        hasGateway: false,
        isDefaultRoute: true
      }, {
        interface: TUN_INTERFACE,
        destination: {
          address: {
            address: '::',
            family: 2
          },
          prefixLength: 0
        },
        gateway: {
          address: '::',
          family: 2
        },
        hasGateway: false,
        isDefaultRoute: true
      }],
      dnsAddresses: ipv6Enabled ? [TUN_IPV4_DNS_ADDRESS, TUN_IPV6_DNS_ADDRESS] : [TUN_IPV4_DNS_ADDRESS],
      mtu: TUN_MTU,
      isIPv4Accepted: true,
      isIPv6Accepted: true,
      isInternal: false,
      isBlocking: false
    }
    if (applicationScope.mode === 'allowlist') {
      // HarmonyOS applies trustedApplications at VPN creation time: only
      // these package names enter this TUN; every other application keeps its
      // ordinary system network. Never combine this with blockedApplications.
      config.trustedApplications = applicationScope.trustedApplications.slice()
    } else if (applicationScope.mode === 'blocklist' && applicationScope.trustedApplications.length > 0) {
      config.blockedApplications = applicationScope.trustedApplications.slice()
    }
    return config
  }

  private ensureStartAllowed(): void {
    if (this.stopRequested) throw new Error('VPN start cancelled')
  }

  private startupFailureMessage(fallback: string): string {
    let nativeMessage: string = ''
    try {
      nativeMessage = this.core.getLastError()
    } catch (_) {
      nativeMessage = ''
    }
    return nativeMessage.length > 0 ? nativeMessage : fallback
  }

  private async publishRuntimeStatus(state: VpnRuntimeState, stage: string, error: string = ''): Promise<void> {
    this.runtimeState = state
    this.stage = stage
    this.runtimeError = error
    const bridge: VpnRuntimeBridgeStore | null = this.runtimeBridge
    if (bridge === null || this.sessionId.length === 0) return
    const status: VpnRuntimeStatus = {
      protocolGeneration: VPN_RUNTIME_PROTOCOL_CURRENT,
      revision: 0,
      sessionId: this.sessionId,
      state: this.runtimeState,
      stage: this.stage,
      version: this.runtimeVersion,
      error: this.runtimeError,
      uploadBytes: this.runtimeUploadBytes,
      downloadBytes: this.runtimeDownloadBytes,
      activeConnections: this.runtimeActiveConnections,
      selectedOutboundTag: this.runtimeSelectedOutboundTag,
      snapshotJson: this.runtimeSnapshotJson,
      updatedAt: Date.now()
    }
    await bridge.publishStatus(status)
  }

  private startHeartbeat(): void {
    if (this.heartbeatTimer === 0) this.scheduleHeartbeat(HEARTBEAT_INTERVAL_MS)
  }

  private async publishHeartbeat(): Promise<void> {
    if (this.heartbeatBusy || this.stopRequested || this.sessionId.length === 0) return
    this.heartbeatBusy = true
    try {
      // Publish the cross-process heartbeat without waiting for the Go mutex.
      // URLTest intentionally holds that mutex for up to 15 seconds; coupling
      // the heartbeat to getStatus() would make the UI falsely declare the VPN
      // stale after eight seconds during a slow, otherwise valid test.
      await this.publishRuntimeStatus(this.runtimeState, this.stage, this.runtimeError)
      if (this.runtimeState === 'running' && !this.healthCheckBusy) {
        this.checkCoreHealth().catch(() => {
          // checkCoreHealth publishes a sanitized error when still relevant.
        })
      }
    } finally {
      this.heartbeatBusy = false
    }
  }

  private suspended: boolean = false
  private ssidTask: Promise<void> | null = null
  private resumeConfig: string = ''
  private resumeScope: VpnApplicationScope = { mode: 'all', trustedApplications: [] }
  private resumeMode: string = ''
  private lastSsidCheck: number = 0

  private async requestedSsidSuspension(): Promise<boolean | null> {
    try {
      const path: string = this.context.filesDir + '/ssid-policy.json'
      if (!await fileIo.access(path)) return false
      const policy = normalizeSsidPolicy(JSON.parse(fileIo.readTextSync(path)))
      if (!policy.enabled || (policy.excluded || []).length === 0) return false
      if (!wifiManager.isWifiActive()) return false
      const linked: wifiManager.WifiLinkedInfo = await wifiManager.getLinkedInfo()
      if (linked.connState !== wifiManager.ConnState.CONNECTED) return false
      if (!linked.ssid || linked.ssid === '<unknown ssid>') return null
      return shouldSuspendSsid(policy, linked.ssid)
    } catch (_) { return null }
  }

  private async publishSsidSuspension(): Promise<void> {
    this.suspended = true
    this.runtimeActiveConnections = 0
    const pausedSnapshot: SuspendedSnapshot = { suspended: true, sampledAt: Date.now(), connections: [], status: { uplinkTotal: this.runtimeUploadBytes, downlinkTotal: this.runtimeDownloadBytes } }
    this.runtimeSnapshotJson = JSON.stringify(pausedSnapshot)
    if (!this.stopRequested) await this.publishRuntimeStatus('running', 'ssid-suspended')
  }

  private async holdIfPolicyChanged(): Promise<boolean> {
    const decision: boolean | null = await this.requestedSsidSuspension()
    this.ensureStartAllowed()
    if (decision === false) return false
    if (this.tunFd >= 0 && this.vpnConnection !== null) {
      await this.vpnConnection.destroy()
      this.tunFd = -1
    }
    await this.publishSsidSuspension()
    return true
  }

  private async applySsidPolicy(snapshotJson: string): Promise<void> {
    if (this.stopRequested || this.commandBusy || Date.now() - this.lastSsidCheck < (this.networkEventsReady && this.wifiEventsReady ? 30000 : 5000)) return
    this.lastSsidCheck = Date.now()
    const suspend: boolean | null = await this.requestedSsidSuspension()
    if (suspend === null) return // Unknown information preserves the previous state.
    if (suspend === this.suspended || this.stopRequested) return
    const connection: vpnExtension.VpnConnection | null = this.vpnConnection
    if (connection === null) throw new Error('VPN connection unavailable')
    if (suspend) {
      const snapshot: SsidRuntimeModes = JSON.parse(snapshotJson) as SsidRuntimeModes
      this.resumeMode = snapshot.mode || ''
      await this.core.stop()
      this.coreStarted = false
      if (this.stopRequested) return
      if (this.tunFd >= 0) { await connection.destroy(); this.tunFd = -1 }
      await this.publishSsidSuspension()
    } else {
      // The Extension stays alive while suspended, with no TUN or proxy core.
      // A manual stop always wins; each awaited activation step checks it.
      this.ensureStartAllowed()
      const signature: string = await physicalNetworkSignature()
      this.ensureStartAllowed()
      if (signature === 'none') return // Wait for validation instead of losing the armed session.
      this.lastNetworkSignature = signature
      await connection.protectProcessNet()
      this.ensureStartAllowed()
      this.tunFd = await connection.create(this.buildVpnConfig(this.readIpv6Enabled(this.resumeConfig), this.resumeScope))
      if (this.tunFd < 0) throw new Error('VPN returned an invalid TUN descriptor')
      this.ensureStartAllowed()
      if (!this.coreInitialized) {
        const coreInfo: CoreInfo = await this.core.initialize(this.context.filesDir, this.context.cacheDir)
        if (!coreInfo.available) throw new Error('sing-box core unavailable')
        this.coreInitialized = true
        this.runtimeVersion = coreInfo.version
        this.ensureStartAllowed()
        const validation: ValidationResult = await this.core.validateConfig(this.resumeConfig)
        if (!validation.valid) throw new Error('sing-box configuration rejected')
        this.ensureStartAllowed()
      }
      if (await this.holdIfPolicyChanged()) return
      await this.core.start(this.tunFd, this.resumeConfig)
      this.coreStarted = true
      this.ensureStartAllowed()
      if (this.resumeMode) await this.core.control(JSON.stringify({ action: 'mode', mode: this.resumeMode }))
      this.ensureStartAllowed()
      this.suspended = false
      this.runtimeSnapshotJson = '{}'
      await this.publishRuntimeStatus('running', 'running')
    }
  }

  private async checkCoreHealth(): Promise<void> {
    if (this.healthCheckBusy || this.commandBusy || this.stopRequested || this.runtimeState !== 'running') return
    this.healthCheckBusy = true
    try {
      this.ssidTask = this.applySsidPolicy(this.runtimeSnapshotJson)
      try {
        await this.ssidTask
      } catch (_) {
        if (!this.stopRequested) {
          this.runtimeState = 'error'
          this.runtimeError = '按需运行切换失败，VPN 已停止，请重新连接'
          this.stage = 'ssid-transition'
          const acknowledged: boolean = await this.cleanupResources(false)
          if (!acknowledged) this.startCommandProcessor()
        }
        return
      }
      this.ssidTask = null
      if (this.stopRequested || this.suspended) return
      if (this.networkChangePending) {
        const revision: number = this.networkRevision
        try {
          const signature: string = await physicalNetworkSignature()
          if (this.stopRequested || this.suspended) return
          if (this.lastNetworkSignature && signature !== this.lastNetworkSignature) {
            await this.core.control(JSON.stringify({ action: 'network-change' }))
            this.lastHealthSampleAt = 0
          }
          this.lastNetworkSignature = signature
          if (revision === this.networkRevision) this.networkChangePending = false
        } catch (_) { /* A transient underlay read is retried on the next event/heartbeat. */ }
      }
      const active: boolean = this.uiActive()
      if (Date.now() - this.lastHealthSampleAt < telemetryInterval(active)) return
      this.lastHealthSampleAt = Date.now()
      const status: CoreStatus = active ? await this.core.getStatus() : await this.core.getStatusLite()
      if (this.stopRequested || this.runtimeState !== 'running') return
      if (!status.running) {
        await this.publishRuntimeStatus('error', 'runtime-health', 'VPN 代理核心意外停止')
        return
      }
      if (status.version.length > 0) this.runtimeVersion = status.version
      this.runtimeUploadBytes = status.uploadBytes
      this.runtimeDownloadBytes = status.downloadBytes
      this.runtimeActiveConnections = status.activeConnections
      this.runtimeSelectedOutboundTag = status.selectedOutboundTag
      this.runtimeSnapshotJson = status.snapshotJson || '{}'
      // The next independent heartbeat publishes this snapshot. Do not couple
      // heartbeat freshness to the Go mutex: URLTest intentionally holds that
      // mutex for up to 15 seconds.
    } catch (_) {
      if (!this.stopRequested && this.runtimeState === 'running') {
        await this.publishRuntimeStatus('error', 'runtime-health', '无法读取 VPN 代理核心状态')
      }
    } finally {
      this.ssidTask = null
      this.healthCheckBusy = false
    }
  }

  private startCommandProcessor(): void {
    if (this.commandTimer !== 0) return
    try {
      this.commandWatcher = fileIo.createWatcher(this.context.filesDir + '/runtime', 0x8 | 0x80 | 0x100,
        (event: WatchEvent): void => {
          const name: string = event.fileName.split('/').pop() || ''
          if (name === 'command.json') this.processRuntimeCommand().catch(() => {})
          if (name === 'ui-activity.json') { this.lastHealthSampleAt = 0; this.scheduleHeartbeat(0) }
        })
      this.commandWatcher.start()
    } catch (_) { this.commandWatcher = null }
    try {
      this.policyWatcher = fileIo.createWatcher(this.context.filesDir, 0x8 | 0x80 | 0x100,
        (event: WatchEvent): void => { if (event.fileName.endsWith('/ssid-policy.json') || event.fileName === 'ssid-policy.json') this.queueNetworkChange() })
      this.policyWatcher.start()
    } catch (_) { this.policyWatcher = null }
    this.commandTimer = setInterval(() => {
      this.processRuntimeCommand().catch(() => {})
    }, this.commandWatcher !== null ? COMMAND_WATCHDOG_INTERVAL_MS : COMMAND_POLL_INTERVAL_MS)
  }

  private stopCommandProcessor(): void {
    if (this.commandTimer !== 0) clearInterval(this.commandTimer)
    this.commandTimer = 0; this.commandPending = false
    if (this.commandWatcher !== null) { try { this.commandWatcher.stop() } catch (_) { }; this.commandWatcher = null }
    if (this.policyWatcher !== null) { try { this.policyWatcher.stop() } catch (_) { }; this.policyWatcher = null }
  }

  private stopBackgroundTasks(): void {
    if (this.heartbeatTimer !== 0) clearTimeout(this.heartbeatTimer)
    this.heartbeatTimer = 0
    this.stopCommandProcessor()
    this.stopNetworkObservers()
  }

  private async writeRuntimeResponse(response: VpnRuntimeResponse): Promise<void> {
    const bridge: VpnRuntimeBridgeStore | null = this.runtimeBridge
    if (bridge !== null) await bridge.writeResponse(response)
  }

  private async processRuntimeCommand(): Promise<void> {
    if (this.commandBusy) { this.commandPending = true; return }
    const bridge: VpnRuntimeBridgeStore | null = this.runtimeBridge
    if (bridge === null || this.sessionId.length === 0) return
    this.commandBusy = true
    try {
      const command: VpnRuntimeCommand | null = await bridge.loadCommand(this.sessionId)
      if (command === null) return
      const decision: VpnRuntimeCommandDecision = decideRuntimeCommand(
        command, this.sessionId, this.lastCommandId, Date.now())
      if (decision === 'duplicate' || decision === 'session-mismatch') return
      this.lastCommandId = command.requestId
      if (decision === 'expired') {
        // A stale stop is deliberately ignored. The UI will time out without
        // a same-session stopped acknowledgement and therefore will not ask
        // the system to destroy an Extension whose cleanup was never run.
        if (command.type === 'stop') return
        await this.writeRuntimeResponse({
          sessionId: this.sessionId,
          requestId: command.requestId,
          success: false,
          latencyMs: 0,
          selectedOutboundTag: '',
          error: command.type === 'select-outbound' ? '代理节点切换请求已过期' : '代理 URLTest 请求已过期',
          completedAt: Date.now()
        })
        return
      }

      if (command.type === 'stop') {
        this.stopRequested = true
        this.stopBackgroundTasks()
        try {
          await this.beginShutdown()
        } finally {
          // A core/TUN or status-write failure must remain retryable. The UI
          // keeps the session locked and a later tap writes a new requestId.
          if (!this.stoppedAcknowledged) this.startCommandProcessor()
        }
        return
      }

      // A stop written after this non-stop request was loaded wins before any
      // new native operation begins. The next poll consumes that exact stop.
      const latestCommand: VpnRuntimeCommand | null = await bridge.loadCommand(this.sessionId)
      if (latestCommand !== null && latestCommand.type === 'stop' &&
        latestCommand.requestId !== command.requestId) {
        return
      }

      if (this.runtimeState !== 'running' || !this.coreStarted || this.stopRequested || this.ssidTask !== null) {
        await this.writeRuntimeResponse({
          sessionId: this.sessionId,
          requestId: command.requestId,
          success: false,
          latencyMs: 0,
          selectedOutboundTag: '',
          error: command.type === 'select-outbound' ?
            'VPN 连接正在停止或不可用，无法切换节点' :
            'VPN 连接正在停止或不可用，无法完成代理 URLTest',
          completedAt: Date.now()
        })
        return
      }


      if (command.type === 'control') {
        let error: string = ''
        try { await this.core.control(command.nodeTag) }
        catch (failure) { error = failure instanceof Error ? failure.message : '内核运行命令失败' }
        await this.writeRuntimeResponse({ sessionId: this.sessionId, requestId: command.requestId,
          success: error.length === 0, latencyMs: 0, selectedOutboundTag: '', error: error, completedAt: Date.now() })
        return
      }
      if (command.type === 'select-outbound') {
        let selectedTag: string = ''
        try {
          selectedTag = await this.core.selectOutbound(command.nodeTag)
          if (selectedTag.length === 0) throw new Error('empty selector result')
        } catch (_) {
          await this.writeRuntimeResponse({
            sessionId: this.sessionId,
            requestId: command.requestId,
            success: false,
            latencyMs: 0,
            selectedOutboundTag: '',
            error: '代理节点切换失败',
            completedAt: Date.now()
          })
          return
        }
        const commandAfterSelection: VpnRuntimeCommand | null = await bridge.loadCommand(this.sessionId)
        if (commandAfterSelection !== null && commandAfterSelection.type === 'stop' &&
          commandAfterSelection.requestId !== command.requestId) {
          // Do not publish a transient running/status success after stop won.
          // The next command poll consumes the stop request.
          return
        }
        this.runtimeSelectedOutboundTag = selectedTag
        // Publish before replying so the UI can prove the same-session
        // selected tag by reading runtime status after the response.
        await this.publishRuntimeStatus('running', 'running')
        await this.writeRuntimeResponse({
          sessionId: this.sessionId,
          requestId: command.requestId,
          success: true,
          latencyMs: 0,
          selectedOutboundTag: selectedTag,
          error: '',
          completedAt: Date.now()
        })
        return
      }

      try {
        const latencyMs: number = await this.core.urlTest(command.nodeTag)
        const commandAfterTest: VpnRuntimeCommand | null = await bridge.loadCommand(this.sessionId)
        if (commandAfterTest !== null && commandAfterTest.type === 'stop' &&
          commandAfterTest.requestId !== command.requestId) {
          return
        }
        await this.writeRuntimeResponse({
          sessionId: this.sessionId,
          requestId: command.requestId,
          success: true,
          latencyMs: latencyMs,
          selectedOutboundTag: '',
          error: '',
          completedAt: Date.now()
        })
      } catch (_) {
        let nativeMessage: string = ''
        try {
          nativeMessage = this.core.getLastError()
        } catch (_) {
          nativeMessage = ''
        }
        const diagnostic: ProxyUrlTestDiagnostic = classifyProxyUrlTestFailure(nativeMessage)
        await this.writeRuntimeResponse({
          sessionId: this.sessionId,
          requestId: command.requestId,
          success: false,
          latencyMs: 0,
          selectedOutboundTag: '',
          error: formatProxyUrlTestFailure(diagnostic),
          completedAt: Date.now()
        })
      }
    } finally {
      this.commandBusy = false
      if (this.commandPending && !this.stoppedAcknowledged) {
        this.commandPending = false
        setTimeout(() => { this.processRuntimeCommand().catch(() => {}) }, 0)
      }
    }
  }

  private async loadRuntimeSession(): Promise<void> {
    const bridge: VpnRuntimeBridgeStore | null = this.runtimeBridge
    if (bridge === null) throw new Error('VPN runtime bridge unavailable')
    const status: VpnRuntimeStatus | null = await bridge.loadLatestStatus()
    if (status === null || status.sessionId.length === 0) {
      throw new Error('VPN runtime session unavailable')
    }
    // File.lock(true) serializes this claim against UI close/discard. The
    // locked method also re-reads freshness before publishing claim-session.
    const claimed: VpnRuntimeStatus | null = await bridge.claimFreshStartTicket(status.sessionId)
    if (claimed === null) throw new Error('VPN runtime session unavailable')
    this.sessionId = claimed.sessionId
    this.runtimeVersion = claimed.version
    this.runtimeState = 'starting'
    this.runtimeError = ''
    this.runtimeUploadBytes = 0
    this.runtimeDownloadBytes = 0
    this.runtimeActiveConnections = 0
    this.runtimeSelectedOutboundTag = ''
    this.startHeartbeat()
    // Start accepting stop as soon as the Extension owns the session, not
    // only after the core reaches running. This lets a user cancel safely
    // during protect/TUN/core startup without killing the lifecycle first.
    this.startCommandProcessor()
    await this.startNetworkObservers()
  }

  private async startLifecycle(): Promise<void> {
    try {
      this.stage = 'load-session'
      await this.loadRuntimeSession()
      await this.publishRuntimeStatus('starting', 'read-config')
      const configStore: VpnRuntimeConfigStore = new VpnRuntimeConfigStore(this.context.filesDir)
      const configJson: string = await configStore.load()
      const applicationScope: VpnApplicationScope = await configStore.loadApplicationScope()
      this.resumeConfig = configJson
      this.resumeScope = applicationScope
      const ipv6Enabled: boolean = this.readIpv6Enabled(configJson)
      this.ensureStartAllowed()

      // SSID exclusion outranks every application mode, including save/restart.
      // A suspended startup must never briefly create TUN or start the core.
      const suspendAtStart: boolean | null = await this.requestedSsidSuspension()
      this.ensureStartAllowed()
      if (suspendAtStart === null) throw new Error('无法确认 Wi-Fi SSID，按需运行暂不能启动')
      if (suspendAtStart) { await this.publishSsidSuspension(); return }

      const connection: vpnExtension.VpnConnection | null = this.vpnConnection
      if (connection === null) throw new Error('VPN connection unavailable')

      // Protect every socket created after this point from looping into TUN.
      await this.publishRuntimeStatus('starting', 'protect-process')
      await connection.protectProcessNet()
      this.ensureStartAllowed()

      await this.publishRuntimeStatus('starting', 'create-tun')
      this.tunFd = await connection.create(this.buildVpnConfig(ipv6Enabled, applicationScope))
      if (this.tunFd < 0) throw new Error('VPN returned an invalid TUN descriptor')
      this.ensureStartAllowed()

      // Do not move initialization before protectProcessNet()/create().
      await this.publishRuntimeStatus('starting', 'initialize-core')
      const coreInfo: CoreInfo = await this.core.initialize(this.context.filesDir, this.context.cacheDir)
      if (!coreInfo.available) throw new Error('sing-box core unavailable')
      this.runtimeVersion = coreInfo.version
      this.coreInitialized = true
      this.ensureStartAllowed()

      await this.publishRuntimeStatus('starting', 'validate-config')
      const validation: ValidationResult = await this.core.validateConfig(configJson)
      if (!validation.valid) throw new Error('sing-box configuration rejected')
      this.ensureStartAllowed()

      await this.publishRuntimeStatus('starting', 'start-core')
      if (await this.holdIfPolicyChanged()) return
      await this.core.start(this.tunFd, configJson)
      this.coreStarted = true
      this.ensureStartAllowed()

      await this.publishRuntimeStatus('starting', 'verify-core')
      const status: CoreStatus = await this.core.getStatus()
      if (!status.running) throw new Error('sing-box core did not enter running state')
      if (status.version.length > 0) this.runtimeVersion = status.version
      this.runtimeUploadBytes = status.uploadBytes
      this.runtimeDownloadBytes = status.downloadBytes
      this.runtimeActiveConnections = status.activeConnections
      this.runtimeSelectedOutboundTag = status.selectedOutboundTag
      this.runtimeSnapshotJson = status.snapshotJson || '{}'
      await this.publishRuntimeStatus('running', 'running')
      hilog.info(DOMAIN, TAG, 'VPN TUN and core are running')
    } catch (failure) {
      if (!this.stopRequested) {
        const failedStage: string = this.stage
        const nativeMessage: string = this.startupFailureMessage(failure instanceof Error ? failure.message : '')
        const diagnostic: CoreStartupDiagnostic = classifyCoreStartupFailure(failedStage, nativeMessage)
        const detail: string = startupFailureDetail(nativeMessage)
        const safeMessage: string = formatCoreStartupFailure(diagnostic) + (detail.length > 0 ? `\n${detail}` : '')
        hilog.error(DOMAIN, TAG, 'stage=%{public}s code=%{public}s', diagnostic.stage, diagnostic.code)
        // Do not publish a pre-cleanup error. The UI used to stop the Extension
        // as soon as it observed that state, racing onDestroy against this
        // rollback and leaving a permanent error ticket. Keep the sanitized
        // failure in memory, finish core/TUN cleanup, then publish one
        // authoritative stopped acknowledgement from cleanupResources().
        this.runtimeState = 'error'
        this.stage = diagnostic.stage
        this.runtimeError = safeMessage
      }
      this.stopBackgroundTasks()
      const stoppedAcknowledged: boolean = await this.cleanupResources(false)
      if (!stoppedAcknowledged && !this.stopRequested) {
        // Startup rollback could not prove cleanup (or could not persist the
        // proof). Keep the live Extension able to accept a fresh stop command.
        this.startCommandProcessor()
      }
    }
  }

  private async beginShutdown(): Promise<void> {
    if (this.shutdownTask !== null) return this.shutdownTask
    const task: Promise<void> = this.stopLifecycle()
    this.shutdownTask = task
    try {
      await task
    } finally {
      // A failed cleanup or stopped-status write must be retryable with a new
      // requestId. Successful cleanup stays memoized for onDestroy fallback.
      if (!this.stoppedAcknowledged && this.shutdownTask === task) {
        this.shutdownTask = null
      }
    }
  }

  private async stopLifecycle(): Promise<void> {
    if (this.startupTask !== null) {
      try {
        await this.startupTask
      } catch (_) {
        // startLifecycle owns its rollback and never exposes sensitive errors.
      }
    }
    if (this.ssidTask !== null) { try { await this.ssidTask } catch (_) { } }
    await this.cleanupResources(true)
  }

  private async cleanupResources(publishStopped: boolean): Promise<boolean> {
    this.stopBackgroundTasks()
    let coreStopConfirmed: boolean = !this.coreInitialized && !this.coreStarted
    let tunDestroyConfirmed: boolean = this.tunFd < 0

    this.stage = 'stop-core'
    if (this.coreInitialized || this.coreStarted) {
      // Preserve the final session totals when possible, but never let an
      // optional statistics read prevent the security-critical core stop.
      if (this.coreStarted) {
        try {
          const finalStatus: CoreStatus = await this.core.getStatus()
          this.runtimeUploadBytes = finalStatus.uploadBytes
          this.runtimeDownloadBytes = finalStatus.downloadBytes
          this.runtimeSelectedOutboundTag = finalStatus.selectedOutboundTag
        } catch (_) {
          // Keep the last successful tracker snapshot and continue cleanup.
        }
      }
      try {
        await this.core.stop()
        coreStopConfirmed = true
        this.coreStarted = false
        this.coreInitialized = false
        this.runtimeActiveConnections = 0
      } catch (_) {
        hilog.error(DOMAIN, TAG, 'sing-box core stop failed')
      }
    }

    this.stage = 'destroy-tun'
    const connection: vpnExtension.VpnConnection | null = this.vpnConnection
    // A connection object is created before authorization, but there is no
    // system VPN to destroy until create() returned a valid descriptor.
    if (this.tunFd >= 0 && connection !== null) {
      try {
        await connection.destroy()
        tunDestroyConfirmed = true
        this.vpnConnection = null
        this.tunFd = -1
      } catch (_) {
        hilog.error(DOMAIN, TAG, 'VPN TUN destroy failed')
      }
    } else if (this.tunFd < 0) {
      tunDestroyConfirmed = true
      this.vpnConnection = null
    }

    // Never forge a stopped acknowledgement. Keeping failed handles/flags
    // allows the second cleanup pass (or a later safe-stop request) to retry.
    if (!coreStopConfirmed || !tunDestroyConfirmed) {
      try {
        await this.publishRuntimeStatus('error', 'cleanup-failed', 'VPN 清理尚未确认，请再次执行安全停止')
      } catch (_) {
        hilog.error(DOMAIN, TAG, 'VPN cleanup failure status write failed')
      }
      return false
    }

    // A startup error is retained only while cleanup is unconfirmed. Once the
    // core and TUN rollback both succeed, publish the same authoritative
    // stopped acknowledgement used by an explicit shutdown. This lets a
    // future UI process distinguish a safe failed start from cleanup-failed.
    if (publishStopped || this.runtimeState === 'error') {
      try {
        const startupError: string = publishStopped ? '' : this.runtimeError
        await this.publishRuntimeStatus('stopped',
          publishStopped ? 'stopped' : 'startup-rollback-complete', startupError)
        this.stoppedAcknowledged = true
      } catch (_) {
        hilog.error(DOMAIN, TAG, 'VPN stopped status write failed')
        return false
      }
    }
    hilog.info(DOMAIN, TAG, 'VPN core stopped and TUN destroyed')
    return this.stoppedAcknowledged
  }
}
