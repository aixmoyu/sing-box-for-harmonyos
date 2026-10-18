export type ProxyUrlTestErrorCode =
  'HNA-URL-PROTECT' |
  'HNA-URL-DNS' |
  'HNA-URL-TLS' |
  'HNA-URL-TIMEOUT' |
  'HNA-URL-CONNECT' |
  'HNA-URL-HANDSHAKE' |
  'HNA-URL-OUTBOUND' |
  'HNA-URL-GENERIC'

export interface ProxyUrlTestDiagnostic {
  code: ProxyUrlTestErrorCode
  safePhrase: string
}

function includesAny(value: string, candidates: string[]): boolean {
  for (let index: number = 0; index < candidates.length; index++) {
    if (value.includes(candidates[index])) return true
  }
  return false
}

/**
 * Converts a native sing-box URLTest error to a closed, non-sensitive value.
 * Native text may contain a node host or credential and must never be written
 * to hilog, the bridge files, or the UI.
 */
export function classifyProxyUrlTestFailure(nativeMessage: string): ProxyUrlTestDiagnostic {
  const value: string = nativeMessage.toLowerCase()
  if (includesAny(value, [
    'oh_netconn_', 'netconn result', 'underlay network',
    'vpn socket protection', 'protect socket', 'bind fd'
  ])) {
    return { code: 'HNA-URL-PROTECT', safePhrase: '代理出站未能绕过 VPN TUN' }
  }
  if (includesAny(value, [
    'lookup ', 'resolve ', 'resolver', 'no such host', 'name not resolved',
    'dns query', 'dns transport'
  ])) {
    return { code: 'HNA-URL-DNS', safePhrase: '节点或测试目标 DNS 解析失败' }
  }
  if (includesAny(value, [
    'context deadline exceeded', 'i/o timeout', 'operation timed out',
    'connection timeout', 'deadline exceeded'
  ])) {
    return { code: 'HNA-URL-TIMEOUT', safePhrase: '代理连接或响应超时' }
  }
  if (includesAny(value, [
    'x509', 'certificate', 'unknown authority', 'tls handshake',
    'ssl handshake', 'certificate verify'
  ])) {
    return { code: 'HNA-URL-TLS', safePhrase: 'URLTest TLS 证书或握手失败' }
  }
  if (includesAny(value, [
    'connection refused', 'network is unreachable', 'no route to host',
    'connection reset', 'broken pipe', 'dial tcp', 'dial udp'
  ])) {
    return { code: 'HNA-URL-CONNECT', safePhrase: '代理服务器连接失败' }
  }
  if (includesAny(value, [
    'handshake', 'authentication', 'authenticate', 'bad response',
    'unexpected eof', 'eof', 'decrypt', 'invalid password'
  ])) {
    return { code: 'HNA-URL-HANDSHAKE', safePhrase: '代理握手失败或远端提前关闭' }
  }
  if (includesAny(value, [
    'outbound is unavailable', 'outbound not found', 'selected outbound',
    'not a member', 'selector'
  ])) {
    return { code: 'HNA-URL-OUTBOUND', safePhrase: '待测代理出站不可用' }
  }
  return { code: 'HNA-URL-GENERIC', safePhrase: '代理 URLTest 失败' }
}

export function formatProxyUrlTestFailure(diagnostic: ProxyUrlTestDiagnostic): string {
  return `${diagnostic.code} · ${diagnostic.safePhrase}`
}
