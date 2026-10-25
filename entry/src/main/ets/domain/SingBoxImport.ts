import type { ProxyNode, ProxyProtocol, QueryItem } from './Models.ts'
import { emptyTls, emptyTransport } from './Models.ts'
import { nodeShareUri } from './QuickStart.ts'
import { SubscriptionParser } from './SubscriptionParser.ts'

const PROTOCOLS: string[] = ['shadowsocks', 'trojan', 'vless', 'vmess', 'hysteria2', 'hysteria', 'tuic', 'anytls',
  'shadowtls', 'snell', 'ssh', 'socks', 'http']

function textValue(value: Object | undefined): string {
  return typeof value === 'string' ? value as string : ''
}

function numberValue(value: Object | undefined): number {
  return typeof value === 'number' ? value as number : 0
}

function requireModeledFields(value: Record<string, Object>, allowed: string[], label: string): void {
  for (const key of Object.keys(value)) {
    if (!allowed.includes(key)) throw new Error(`${label} 包含无法完整转换的 ${key} 参数，请使用完整 JSON 配置`)
  }
}

function requireLosslessOutbound(outbound: Record<string, Object>): void {
  const label: string = textValue(outbound.tag) || textValue(outbound.type)
  requireModeledFields(outbound, ['type', 'tag', 'server', 'server_port', 'username', 'user', 'password', 'psk',
    'auth_str', 'uuid', 'security', 'method', 'alter_id', 'flow', 'tls', 'transport', 'version', 'up_mbps',
    'down_mbps', 'congestion_control', 'udp_relay_mode'], label)
  if (outbound.tls !== undefined) {
    const tls: Record<string, Object> = outbound.tls as Record<string, Object>
    if (!tls || Array.isArray(tls) || typeof tls !== 'object') throw new Error(`${label} 的 TLS 配置无效`)
    requireModeledFields(tls, ['enabled', 'server_name', 'insecure', 'alpn', 'utls', 'reality'], label + ' TLS')
    if (tls.utls !== undefined) requireModeledFields(tls.utls as Record<string, Object>, ['enabled','fingerprint'], label + ' uTLS')
    if (tls.reality !== undefined) requireModeledFields(tls.reality as Record<string, Object>, ['enabled','public_key','short_id'], label + ' Reality')
  }
  if (outbound.transport !== undefined) {
    const transport: Record<string, Object> = outbound.transport as Record<string, Object>
    if (!transport || Array.isArray(transport) || typeof transport !== 'object') throw new Error(`${label} 的传输配置无效`)
    requireModeledFields(transport, ['type','path','service_name','host','headers'], label + ' transport')
    if (Array.isArray(transport.host)) throw new Error(`${label} 的多 Host 参数不能转换，请使用完整 JSON 配置`)
    if (transport.headers !== undefined) requireModeledFields(transport.headers as Record<string, Object>, ['Host'], label + ' headers')
  }
}

function uriFromOutbound(outbound: Record<string, Object>): string {
  requireLosslessOutbound(outbound)
  const type: string = textValue(outbound.type)
  const tls = emptyTls()
  const tlsRaw: Object | undefined = outbound.tls
  if (tlsRaw !== undefined && tlsRaw !== null) {
    const source: Record<string, Object> = tlsRaw as Record<string, Object>
    tls.enabled = source.enabled !== false
    tls.serverName = textValue(source.server_name)
    tls.insecure = source.insecure === true
    if (Array.isArray(source.alpn)) tls.alpn = source.alpn as string[]
    const utlsRaw: Object | undefined = source.utls
    if (utlsRaw !== undefined && utlsRaw !== null) {
      const utls: Record<string, Object> = utlsRaw as Record<string, Object>
      if (utls.enabled === true) { tls.utls.enabled = true; tls.utls.fingerprint = textValue(utls.fingerprint) }
    }
    const realityRaw: Object | undefined = source.reality
    if (realityRaw !== undefined && realityRaw !== null) {
      const reality: Record<string, Object> = realityRaw as Record<string, Object>
      if (reality.enabled === true) {
        tls.reality.enabled = true
        tls.reality.publicKey = textValue(reality.public_key)
        tls.reality.shortId = textValue(reality.short_id)
      }
    }
  }

  const transport = emptyTransport()
  const transportRaw: Object | undefined = outbound.transport
  if (transportRaw !== undefined && transportRaw !== null) {
    const source: Record<string, Object> = transportRaw as Record<string, Object>
    transport.type = textValue(source.type)
    transport.path = textValue(source.path)
    transport.serviceName = textValue(source.service_name)
    if (typeof source.host === 'string') transport.host = source.host as string
    else if (source.headers !== undefined) transport.host = textValue((source.headers as Record<string, Object>).Host)
  }

  const query: QueryItem[] = []
  if (typeof outbound.version === 'number') query.push({ key: 'version', value: (outbound.version as number).toString() })
  if (typeof outbound.up_mbps === 'number') query.push({ key: 'upmbps', value: (outbound.up_mbps as number).toString() })
  if (typeof outbound.down_mbps === 'number') query.push({ key: 'downmbps', value: (outbound.down_mbps as number).toString() })
  if (typeof outbound.congestion_control === 'string') {
    query.push({ key: 'congestion_control', value: outbound.congestion_control as string })
  }
  if (typeof outbound.udp_relay_mode === 'string') {
    query.push({ key: 'udp_relay_mode', value: outbound.udp_relay_mode as string })
  }

  const node: ProxyNode = {
    id: '',
    name: textValue(outbound.tag).length > 0 ? textValue(outbound.tag) : type,
    protocol: type as ProxyProtocol,
    server: textValue(outbound.server),
    port: numberValue(outbound.server_port),
    username: textValue(outbound.user).length > 0 ? textValue(outbound.user) : textValue(outbound.username),
    password: textValue(outbound.password).length > 0 ? textValue(outbound.password) :
      (textValue(outbound.psk).length > 0 ? textValue(outbound.psk) : textValue(outbound.auth_str)),
    uuid: textValue(outbound.uuid),
    method: type === 'vmess' ? textValue(outbound.security) : textValue(outbound.method),
    alterId: numberValue(outbound.alter_id),
    flow: textValue(outbound.flow),
    tls: tls,
    transport: transport,
    query: query
  }
  const uri: string = nodeShareUri(node)
  const parsed: ProxyNode = new SubscriptionParser().parse(uri).nodes[0]
  // Some URI formats cannot represent every TLS/transport option. Compare the
  // actual parsed value so newly added fields cannot silently disappear.
  const parsedTransport = { type: parsed.transport.type || 'tcp', path: parsed.transport.path,
    host: parsed.transport.host, serviceName: parsed.transport.serviceName }
  const originalTransport = { type: node.transport.type || 'tcp', path: node.transport.path,
    host: node.transport.host, serviceName: node.transport.serviceName }
  if (JSON.stringify(parsed.tls) !== JSON.stringify(node.tls) ||
    JSON.stringify(parsedTransport) !== JSON.stringify(originalTransport) ||
    parsed.password !== node.password || parsed.username !== node.username || parsed.uuid !== node.uuid ||
    (node.method.length > 0 && parsed.method !== node.method) || parsed.flow !== node.flow ||
    (node.alterId !== undefined && parsed.alterId !== node.alterId)) {
    throw new Error(`${node.name} 的参数无法完整转换，请使用完整 JSON 配置`)
  }
  return uri
}

/**
 * Import nodes from a sing-box JSON config: every outbound whose type is a
 * supported proxy becomes a node. Selectors, URLTest, direct and block are
 * ignored, so the reference profile can be imported without its groups.
 */
export function nodeUrisFromSingBox(content: string): string[] {
  let config: Record<string, Object>
  try { config = JSON.parse(content.replace(/^\uFEFF/, '')) as Record<string, Object> } catch (_) { return [] }
  if (config === null || Array.isArray(config)) return []
  if (!Array.isArray(config.outbounds)) throw new Error('配置的 outbounds 必须是数组')
  const outbounds: Object[] = config.outbounds as Object[]
  const uris: string[] = []
  for (let index: number = 0; index < outbounds.length; index++) {
    const outbound: Record<string, Object> = outbounds[index] as Record<string, Object>
    if (!outbound || typeof outbound !== 'object') throw new Error('配置包含无效的出站条目')
    if (!PROTOCOLS.includes(textValue(outbound.type))) continue
    if (textValue(outbound.server).length === 0 || numberValue(outbound.server_port) <= 0) continue
    const uri: string = uriFromOutbound(outbound)
    if (uri.length > 0) uris.push(uri)
  }
  return uris
}
