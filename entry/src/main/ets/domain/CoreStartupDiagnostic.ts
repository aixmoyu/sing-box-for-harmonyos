export type CoreStartupErrorCode =
  'HNA-SOCKET-PROTECT' |
  'HNA-DNS-EMPTY-DIRECT' |
  'HNA-DNS-TRANSPORT' |
  'HNA-TUN-FD' |
  'HNA-TUN-NONBLOCK' |
  'HNA-TUN-FSTAT' |
  'HNA-TUN-EVENTFD' |
  'HNA-TUN-DISPATCHER' |
  'HNA-TUN-GVISOR' |
  'HNA-TUN-INTERFACE' |
  'HNA-PERMISSION' |
  'HNA-TLS-CERT' |
  'HNA-OUTBOUND' |
  'HNA-CORE-GENERIC'

export interface CoreStartupDiagnostic {
  stage: string
  code: CoreStartupErrorCode
  safePhrase: string
}

interface DiagnosticDefinition {
  code: CoreStartupErrorCode
  safePhrase: string
}

const DNS_EMPTY_DIRECT: DiagnosticDefinition = {
  code: 'HNA-DNS-EMPTY-DIRECT',
  safePhrase: 'DNS 直连出口配置无效'
}

const SOCKET_PROTECT: DiagnosticDefinition = {
  code: 'HNA-SOCKET-PROTECT',
  safePhrase: '代理出站未能绕过 VPN TUN'
}

const DNS_TRANSPORT: DiagnosticDefinition = {
  code: 'HNA-DNS-TRANSPORT',
  safePhrase: 'DNS 传输或分流初始化失败'
}

const TUN_FD: DiagnosticDefinition = {
  code: 'HNA-TUN-FD',
  safePhrase: 'TUN 文件描述符不可用'
}

const TUN_NONBLOCK: DiagnosticDefinition = {
  code: 'HNA-TUN-NONBLOCK',
  safePhrase: 'TUN 非阻塞模式初始化失败'
}

const TUN_FSTAT: DiagnosticDefinition = {
  code: 'HNA-TUN-FSTAT',
  safePhrase: 'TUN 描述符类型检测失败'
}

const TUN_EVENTFD: DiagnosticDefinition = {
  code: 'HNA-TUN-EVENTFD',
  safePhrase: 'TUN 停止事件初始化失败'
}

const TUN_DISPATCHER: DiagnosticDefinition = {
  code: 'HNA-TUN-DISPATCHER',
  safePhrase: 'TUN 数据分发器初始化失败'
}

const TUN_GVISOR: DiagnosticDefinition = {
  code: 'HNA-TUN-GVISOR',
  safePhrase: 'TUN gVisor 网络栈初始化失败'
}

const TUN_INTERFACE: DiagnosticDefinition = {
  code: 'HNA-TUN-INTERFACE',
  safePhrase: 'TUN 接口初始化失败'
}

const PERMISSION: DiagnosticDefinition = {
  code: 'HNA-PERMISSION',
  safePhrase: 'VPN 系统权限不足'
}

const TLS_CERT: DiagnosticDefinition = {
  code: 'HNA-TLS-CERT',
  safePhrase: 'TLS 证书校验或握手失败'
}

const OUTBOUND: DiagnosticDefinition = {
  code: 'HNA-OUTBOUND',
  safePhrase: '代理出站初始化或连接失败'
}

const CORE_GENERIC: DiagnosticDefinition = {
  code: 'HNA-CORE-GENERIC',
  safePhrase: '代理核心启动失败'
}

function includesAny(value: string, candidates: string[]): boolean {
  for (let index: number = 0; index < candidates.length; index++) {
    if (value.includes(candidates[index])) return true
  }
  return false
}

/**
 * Only fixed lifecycle stages may cross the Extension process boundary.
 * Although current callers own the stage value, this allowlist prevents a
 * future native or external value from becoming an accidental log channel.
 */
export function safeCoreStartupStage(stage: string): string {
  switch (stage) {
    case 'load-session':
    case 'read-config':
    case 'protect-process':
    case 'create-tun':
    case 'initialize-core':
    case 'validate-config':
    case 'start-core':
    case 'verify-core':
      return stage
    default:
      return 'startup'
  }
}

/**
 * Maps a potentially sensitive native error into a closed vocabulary. The
 * native text is used only for in-memory matching and is never retained in the
 * result, persisted to runtime status, or emitted to hilog.
 */
export function classifyCoreStartupFailure(stage: string, nativeMessage: string): CoreStartupDiagnostic {
  const value: string = nativeMessage.toLowerCase()
  let definition: DiagnosticDefinition = CORE_GENERIC

  if (includesAny(value, [
    'oh_netconn_', 'netconn result', 'underlay network',
    'vpn socket protection', 'protect socket', 'bind fd'
  ])) {
    definition = SOCKET_PROTECT
  } else if (value.includes('empty direct outbound') ||
    (value.includes('detour') && value.includes('empty') &&
      value.includes('direct') && value.includes('outbound'))) {
    definition = DNS_EMPTY_DIRECT
  } else if (includesAny(value, [
    'setnonblock', 'set nonblock', 'non-blocking', 'nonblocking'
  ])) {
    definition = TUN_NONBLOCK
  } else if (includesAny(value, ['fstat(', 'fstat failed', 'file status'])) {
    definition = TUN_FSTAT
  } else if (includesAny(value, [
    'eventfd', 'event fd', 'stopfd', 'stop fd'
  ])) {
    definition = TUN_EVENTFD
  } else if (includesAny(value, [
    'createinbounddispatcher', 'newreadvdispatcher', 'readv dispatcher',
    'packet dispatcher'
  ])) {
    definition = TUN_DISPATCHER
  } else if (includesAny(value, [
    'permission denied', 'not permitted', 'operation not permitted',
    'access denied', 'permission required', 'unauthorized'
  ])) {
    definition = PERMISSION
  } else if (includesAny(value, [
    'certificate', 'x509', 'unknown authority', 'tls handshake',
    'ssl handshake', 'certificate verify', 'certificate store'
  ])) {
    definition = TLS_CERT
  } else if (value.includes('dns') && includesAny(value, [
    'detour', 'transport', 'resolver', 'server', 'query', 'lookup',
    'initialize', 'start', 'dial', 'https', 'tls', 'udp'
  ])) {
    definition = DNS_TRANSPORT
  } else if (includesAny(value, [
    'tun fd', 'tun file descriptor', 'bad file descriptor',
    'invalid file descriptor', 'invalid tun descriptor'
  ])) {
    definition = TUN_FD
  } else if (includesAny(value, ['gvisor', 'gvisor stack', 'netstack'])) {
    definition = TUN_GVISOR
  } else if (includesAny(value, [
    'tun interface', 'tunnel interface', 'create tun', 'open tun',
    'interface name', 'interface unavailable', 'ioctl'
  ])) {
    definition = TUN_INTERFACE
  } else if (includesAny(value, ['tls', 'ssl'])) {
    definition = TLS_CERT
  } else if (includesAny(value, [
    'outbound', 'dial tcp', 'dial udp', 'proxy connection',
    'selected outbound', 'selector'
  ])) {
    definition = OUTBOUND
  }

  return {
    stage: safeCoreStartupStage(stage),
    code: definition.code,
    safePhrase: definition.safePhrase
  }
}

/** Safe for the cross-process status file and UI. Never includes native text. */
export function formatCoreStartupFailure(diagnostic: CoreStartupDiagnostic): string {
  return `VPN 启动失败（${diagnostic.stage} · ${diagnostic.code} · ${diagnostic.safePhrase}）`
}

/** Retain actionable errors in the app's private status, excluding credentials. */
export function startupFailureDetail(nativeMessage: string): string {
  return nativeMessage
    .replace(/https?:\/\/[^\s"'<>]+/gi, '[URL]')
    .replace(/\b(password|passwd|secret|token|authorization|uuid)\s*[:=]\s*[^\s,;]+/gi, '$1=[已隐藏]')
    .replace(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/gi, '[ID]')
    .replace(/[\u0000-\u0008\u000b-\u001f]/g, '')
    .slice(0, 4096)
}
