import type {
  DnsProfile,
  PolicyGroup,
  ProxyNode,
  ProxyProtocol,
  QueryItem,
  RoutingRule,
  RuleKind,
  RuleTarget,
  SubscriptionBundle,
  SubscriptionFormat,
  SubscriptionHeaders,
  SubscriptionMetadata,
  TransportOptions
} from './Models.ts'
import { emptyMetadata, emptyTls, emptyTransport } from './Models.ts'
import { decodeBase64Bytes, decodeBase64Text, decodeUrlComponent, fnv1aId } from './TextCodec.ts'

interface ParsedAddress {
  host: string
  port: number
}

interface ParsedUri {
  scheme: string
  authority: string
  query: QueryItem[]
  name: string
}

interface VmessPayload {
  ps?: string
  add?: string
  port?: string
  id?: string
  aid?: string
  alterId?: string
  scy?: string
  net?: string
  type?: string
  host?: string
  path?: string
  tls?: string
  sni?: string
  alpn?: string
  fp?: string
}

interface SingBoxTls {
  enabled?: boolean
  server_name?: string
  insecure?: boolean
  alpn?: string[]
  utls?: SingBoxUtls
  reality?: SingBoxReality
}

interface SingBoxUtls {
  enabled?: boolean
  fingerprint?: string
}

interface SingBoxReality {
  enabled?: boolean
  public_key?: string
  short_id?: string
}

interface SingBoxHysteria2Obfs {
  type?: string
  password?: string
}

interface SingBoxTransport {
  type?: string
  path?: string
  host?: string[] | string
  headers?: SingBoxHeaders
  service_name?: string
  max_early_data?: number
  early_data_header_name?: string
}

interface SingBoxHeaders {
  Host?: string
  host?: string
}

interface SingBoxOutbound {
  type?: string
  tag?: string
  server?: string
  server_port?: number
  username?: string
  password?: string
  uuid?: string
  method?: string
  security?: string
  alter_id?: number
  flow?: string
  tls?: SingBoxTls
  transport?: SingBoxTransport
  outbounds?: string[]
  default?: string
  obfs?: SingBoxHysteria2Obfs
  plugin?: string
  plugin_opts?: string
}

interface SingBoxRule {
  type?: string
  domain?: string[] | string
  domain_suffix?: string[] | string
  domain_keyword?: string[] | string
  ip_cidr?: string[] | string
  rule_set?: string[] | string
  outbound?: string
  action?: string
}

interface SingBoxRoute {
  rules?: SingBoxRule[]
  final?: string
}

interface SingBoxDnsServer {
  address?: string
  server?: string
}

interface SingBoxDns {
  servers?: SingBoxDnsServer[]
  strategy?: string
}

interface SingBoxRoot {
  outbounds?: SingBoxOutbound[]
  route?: SingBoxRoute
  dns?: SingBoxDns
}

interface YamlMap {
  name: string
  values: QueryItem[]
}

interface SingBoxTargetResolution {
  target: RuleTarget
  issue: string
}

const SUPPORTED_SCHEMES: string[] = ['ss://', 'trojan://', 'vless://', 'vmess://', 'hysteria2://', 'hy2://']
const SUPPORTED_UTLS_FINGERPRINTS: string[] = [
  'chrome', 'chrome_psk', 'chrome_psk_shuffle', 'chrome_padding_psk_shuffle', 'chrome_pq', 'chrome_pq_psk',
  'firefox', 'edge', 'safari', '360', 'qq', 'ios', 'android', 'random', 'randomized'
]
const SUPPORTED_SHADOWSOCKS_METHODS: string[] = [
  'aes-128-ctr', 'aes-192-ctr', 'aes-256-ctr',
  'aes-128-cfb', 'aes-192-cfb', 'aes-256-cfb',
  'rc4-md5', 'chacha20-ietf', 'xchacha20',
  'aes-128-gcm', 'aes-192-gcm', 'aes-256-gcm',
  'chacha20-ietf-poly1305', 'xchacha20-ietf-poly1305',
  '2022-blake3-aes-128-gcm', '2022-blake3-aes-256-gcm',
  '2022-blake3-chacha20-poly1305'
]
const SUPPORTED_VMESS_SECURITY: string[] = [
  'auto', 'none', 'zero', 'aes-128-cfb', 'aes-128-gcm', 'chacha20-poly1305'
]
const SUPPORTED_TRANSPORTS: string[] = ['', 'tcp', 'http', 'ws', 'quic', 'grpc', 'httpupgrade']
const SUPPORTED_SING_BOX_RULE_KEYS: string[] = [
  'type', 'domain', 'domain_suffix', 'domain_keyword', 'ip_cidr', 'rule_set', 'outbound', 'action'
]

function queryValue(items: QueryItem[], key: string): string {
  for (let index: number = 0; index < items.length; index++) {
    if (items[index].key.toLowerCase() === key.toLowerCase()) {
      return items[index].value
    }
  }
  return ''
}

function hasQueryKey(items: QueryItem[], key: string): boolean {
  return items.some((item: QueryItem) => item.key.toLowerCase() === key.toLowerCase())
}

function isTrue(value: string): boolean {
  const normalized: string = value.trim().toLowerCase()
  return normalized === '1' || normalized === 'true' || normalized === 'yes'
}

function yamlValue(values: QueryItem[], key: string): string {
  return queryValue(values, key)
}

function parseInteger(value: string): number {
  const parsed: number = Number.parseInt(value, 10)
  return Number.isFinite(parsed) ? parsed : 0
}

function parseAlterId(value: string): number {
  const text: string = `${value}`.trim()
  if (text.length === 0) return 0
  const parsed: number = Number(text)
  if (!Number.isInteger(parsed) || parsed < 0) throw new Error('VMess alterId 必须是非负整数')
  return parsed
}

function stripQuotes(value: string): string {
  const trimmed: string = value.trim()
  if (trimmed.length >= 2 &&
    ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
      (trimmed.startsWith("'") && trimmed.endsWith("'")))) {
    return trimmed.slice(1, -1)
  }
  return trimmed
}

function splitInlineYamlFields(value: string): string[] {
  let source: string = value.trim()
  if (source.startsWith('{') && source.endsWith('}')) source = source.slice(1, -1)
  const fields: string[] = []
  let current: string = ''
  let quote: string = ''
  let escaped: boolean = false
  let squareDepth: number = 0
  let curlyDepth: number = 0
  for (let index: number = 0; index < source.length; index++) {
    const character: string = source.charAt(index)
    if (escaped) {
      current += character
      escaped = false
      continue
    }
    if (quote.length > 0 && character === '\\') {
      current += character
      escaped = true
      continue
    }
    if (character === '"' || character === "'") {
      if (quote.length === 0) quote = character
      else if (quote === character) quote = ''
      current += character
      continue
    }
    if (quote.length === 0) {
      if (character === '[') squareDepth++
      if (character === ']') squareDepth--
      if (character === '{') curlyDepth++
      if (character === '}') curlyDepth--
      if (character === ',' && squareDepth === 0 && curlyDepth === 0) {
        if (current.trim().length > 0) fields.push(current.trim())
        current = ''
        continue
      }
    }
    current += character
  }
  if (current.trim().length > 0) fields.push(current.trim())
  return fields
}

function findTopLevelColon(value: string): number {
  let quote: string = ''
  let escaped: boolean = false
  let squareDepth: number = 0
  let curlyDepth: number = 0
  for (let index: number = 0; index < value.length; index++) {
    const character: string = value.charAt(index)
    if (escaped) {
      escaped = false
      continue
    }
    if (quote.length > 0 && character === '\\') {
      escaped = true
      continue
    }
    if (character === '"' || character === "'") {
      if (quote.length === 0) quote = character
      else if (quote === character) quote = ''
      continue
    }
    if (quote.length > 0) continue
    if (character === '[') squareDepth++
    if (character === ']') squareDepth--
    if (character === '{') curlyDepth++
    if (character === '}') curlyDepth--
    if (character === ':' && squareDepth === 0 && curlyDepth === 0) return index
  }
  return -1
}

function parseInlineYamlValues(value: string): QueryItem[] {
  const values: QueryItem[] = []
  const fields: string[] = splitInlineYamlFields(value)
  for (let index: number = 0; index < fields.length; index++) {
    const colon: number = findTopLevelColon(fields[index])
    if (colon < 1) continue
    values.push({
      key: stripQuotes(fields[index].slice(0, colon)).trim(),
      value: stripQuotes(fields[index].slice(colon + 1)).trim()
    })
  }
  return values
}

function validateProtocolCredentials(
  protocol: ProxyProtocol,
  name: string,
  password: string,
  uuid: string,
  method: string
): void {
  const label: string = name.length > 0 ? name : protocol
  if (protocol === 'shadowsocks' && method.trim().length === 0) {
    throw new Error(`节点 ${label} 缺少 Shadowsocks 加密方式`)
  }
  if (protocol === 'shadowsocks' && password.length === 0) {
    throw new Error(`节点 ${label} 缺少 Shadowsocks 密码`)
  }
  if ((protocol === 'vless' || protocol === 'vmess') && uuid.trim().length === 0) {
    throw new Error(`节点 ${label} 缺少 UUID`)
  }
  if ((protocol === 'trojan' || protocol === 'hysteria2') && password.length === 0) {
    throw new Error(`节点 ${label} 缺少密码`)
  }
}

function normalizeTransportType(value: string): string {
  const normalized: string = value.trim().toLowerCase()
  if (normalized === 'websocket') return 'ws'
  if (normalized === 'h2') return 'http'
  return normalized
}

function validateNodeCompatibility(protocol: ProxyProtocol, name: string, password: string,
  method: string, flow: string, transport: TransportOptions): void {
  const label: string = name.length > 0 ? name : protocol
  if (protocol === 'shadowsocks' && !SUPPORTED_SHADOWSOCKS_METHODS.includes(method)) {
    throw new Error(`节点 ${label} 使用当前 sing-box 不支持的 Shadowsocks 加密方式`)
  }
  if (protocol === 'vmess' && !SUPPORTED_VMESS_SECURITY.includes(method)) {
    throw new Error(`节点 ${label} 使用当前 sing-box 不支持的 VMess 加密方式`)
  }
  if (protocol === 'vless' && flow.length > 0 && flow !== 'xtls-rprx-vision') {
    throw new Error(`节点 ${label} 使用当前 sing-box 不支持的 VLESS flow`)
  }
  if (!SUPPORTED_TRANSPORTS.includes(transport.type)) {
    throw new Error(`节点 ${label} 使用当前版本不支持的传输类型`)
  }
  if ((protocol === 'shadowsocks' || protocol === 'hysteria2') && transport.type.length > 0 &&
    transport.type !== 'tcp') {
    throw new Error(`节点 ${label} 的协议不支持当前传输配置`)
  }
  if (method.startsWith('2022-blake3-')) {
    const requiredLength: number = method === '2022-blake3-aes-128-gcm' ? 16 : 32
    const keys: string[] = password.split(':')
    for (let index: number = 0; index < keys.length; index++) {
      try {
        if (decodeBase64Bytes(keys[index]).length !== requiredLength) throw new Error('invalid key length')
      } catch (_) {
        throw new Error(`节点 ${label} 的 Shadowsocks 2022 密钥格式无效`)
      }
    }
  }
}

function validateUtlsFingerprint(value: string): string {
  const fingerprint: string = value.trim().toLowerCase()
  if (fingerprint.length === 0) return ''
  if (!SUPPORTED_UTLS_FINGERPRINTS.includes(fingerprint)) {
    throw new Error(`不支持的 uTLS fingerprint：${value}`)
  }
  return fingerprint
}

function singBoxTransportHost(transport: SingBoxTransport | undefined): string {
  if (!transport || transport.host === undefined) return ''
  if (typeof transport.host === 'string') return transport.host
  return transport.host.length > 0 ? transport.host[0] : ''
}

function hasUnsupportedSingBoxTransportHeaders(headers: SingBoxHeaders | undefined): boolean {
  if (!headers) return false
  const actual: string = JSON.stringify(headers)
  const allowed: SingBoxHeaders = {}
  if (headers.Host !== undefined) allowed.Host = headers.Host
  if (headers.host !== undefined) allowed.host = headers.host
  return actual !== JSON.stringify(allowed)
}

function validateRealityPublicKey(value: string): string {
  const publicKey: string = value.trim()
  if (publicKey.length === 0) throw new Error('Reality 节点缺少 public key')
  try {
    if (decodeBase64Bytes(publicKey).length !== 32) throw new Error('invalid length')
  } catch (_) {
    throw new Error('Reality public key 格式无效')
  }
  return publicKey
}

function validateRealityShortId(value: string): string {
  const shortId: string = value.trim().toLowerCase()
  if (shortId.length === 0) return ''
  if (shortId.length > 16 || shortId.length % 2 !== 0) throw new Error('Reality short id 格式无效')
  for (let index: number = 0; index < shortId.length; index++) {
    const code: number = shortId.charCodeAt(index)
    const digit: boolean = code >= 48 && code <= 57
    const hexLetter: boolean = code >= 97 && code <= 102
    if (!digit && !hexLetter) throw new Error('Reality short id 格式无效')
  }
  return shortId
}

function canonicalQuery(items: QueryItem[]): QueryItem[] {
  return items.slice().sort((left: QueryItem, right: QueryItem) => {
    const leftText: string = `${left.key.toLowerCase()}=${left.value}`
    const rightText: string = `${right.key.toLowerCase()}=${right.value}`
    if (leftText < rightText) return -1
    if (leftText > rightText) return 1
    return 0
  })
}

function splitCsv(value: string): string[] {
  let source: string = value.trim()
  if (source.startsWith('[') && source.endsWith(']')) {
    source = source.slice(1, -1)
  }
  if (source.length === 0) {
    return []
  }
  return source.split(',').map((item: string) => stripQuotes(item)).filter((item: string) => item.length > 0)
}

function parseQuery(value: string): QueryItem[] {
  if (value.length === 0) {
    return []
  }
  return value.split('&').filter((item: string) => item.length > 0).map((item: string) => {
    const equalsIndex: number = item.indexOf('=')
    if (equalsIndex < 0) {
      return { key: decodeUrlComponent(item), value: '' }
    }
    return {
      key: decodeUrlComponent(item.slice(0, equalsIndex)),
      value: decodeUrlComponent(item.slice(equalsIndex + 1))
    }
  })
}

function parseUri(value: string): ParsedUri {
  const schemeEnd: number = value.indexOf('://')
  if (schemeEnd < 1) {
    throw new Error('节点链接缺少协议名')
  }
  const scheme: string = value.slice(0, schemeEnd).toLowerCase()
  let rest: string = value.slice(schemeEnd + 3)
  let name: string = ''
  const hashIndex: number = rest.indexOf('#')
  if (hashIndex >= 0) {
    name = decodeUrlComponent(rest.slice(hashIndex + 1))
    rest = rest.slice(0, hashIndex)
  }
  let query: QueryItem[] = []
  const queryIndex: number = rest.indexOf('?')
  if (queryIndex >= 0) {
    query = parseQuery(rest.slice(queryIndex + 1))
    rest = rest.slice(0, queryIndex)
  }
  return { scheme: scheme, authority: rest, query: query, name: name }
}

function parseAddress(value: string): ParsedAddress {
  const authority: string = value.trim()
  if (authority.startsWith('[')) {
    const closing: number = authority.indexOf(']')
    if (closing < 0) {
      throw new Error('IPv6 地址缺少右方括号')
    }
    const portText: string = authority.slice(closing + 1).replace(/^:/, '')
    return { host: authority.slice(1, closing), port: parseInteger(portText) }
  }
  const colon: number = authority.lastIndexOf(':')
  if (colon < 1) {
    throw new Error('节点链接缺少端口')
  }
  return { host: authority.slice(0, colon), port: parseInteger(authority.slice(colon + 1)) }
}

function makeNode(
  protocol: ProxyProtocol,
  name: string,
  server: string,
  port: number,
  username: string,
  password: string,
  uuid: string,
  method: string,
  alterId: number,
  flow: string,
  query: QueryItem[],
  transport: TransportOptions
): ProxyNode {
  if (server.length === 0 || port < 1 || port > 65535) {
    throw new Error(`节点 ${name || protocol} 的地址或端口无效`)
  }
  if (protocol === 'hysteria2' && (hasQueryKey(query, 'obfs') || hasQueryKey(query, 'obfs-password') ||
    hasQueryKey(query, 'obfsPassword'))) {
    throw new Error(`节点 ${name || protocol} 使用 Hysteria2 obfs，当前版本未完整支持，已跳过`)
  }
  if (protocol === 'vmess' && (!Number.isInteger(alterId) || alterId < 0)) {
    throw new Error(`节点 ${name || protocol} 的 VMess alterId 无效`)
  }
  if (hasQueryKey(query, 'ed') || hasQueryKey(query, 'eh') || hasQueryKey(query, 'max_early_data') ||
    hasQueryKey(query, 'early_data_header_name')) {
    throw new Error(`节点 ${name || protocol} 使用 WebSocket early-data，当前版本未完整建模，已跳过`)
  }
  const resolvedMethod: string = method.trim().toLowerCase()
  const resolvedFlow: string = flow.trim().toLowerCase()
  transport.type = normalizeTransportType(transport.type)
  validateProtocolCredentials(protocol, name, password, uuid, resolvedMethod)
  validateNodeCompatibility(protocol, name, password, resolvedMethod, resolvedFlow, transport)

  const security: string = (queryValue(query, 'security') || queryValue(query, 'tls')).trim().toLowerCase()
  const realityEnabled: boolean = security === 'reality' || isTrue(queryValue(query, 'reality_enabled'))
  const tlsEnabled: boolean = security === 'tls' || isTrue(security) || realityEnabled ||
    protocol === 'trojan' || protocol === 'hysteria2'
  const serverName: string = queryValue(query, 'sni') || queryValue(query, 'peer')
  const insecureText: string = queryValue(query, 'allowInsecure') || queryValue(query, 'insecure')
  let fingerprint: string = validateUtlsFingerprint(queryValue(query, 'fp') || queryValue(query, 'fingerprint'))
  let utlsEnabled: boolean = fingerprint.length > 0 || isTrue(queryValue(query, 'utls_enabled'))
  if (realityEnabled && !utlsEnabled) {
    // sing-box requires uTLS for Reality. Chrome is its own default fingerprint
    // and is also the convention used by share links which omit `fp`.
    utlsEnabled = true
    fingerprint = 'chrome'
  }
  if (utlsEnabled && !tlsEnabled) throw new Error(`节点 ${name || protocol} 的 uTLS 未启用 TLS`)

  const tls = emptyTls()
  tls.enabled = tlsEnabled
  tls.serverName = serverName
  tls.insecure = isTrue(insecureText)
  tls.alpn = splitCsv(queryValue(query, 'alpn'))
  tls.utls.enabled = utlsEnabled
  tls.utls.fingerprint = fingerprint
  if (realityEnabled) {
    tls.reality.enabled = true
    tls.reality.publicKey = validateRealityPublicKey(queryValue(query, 'pbk') || queryValue(query, 'public_key') ||
      queryValue(query, 'public-key'))
    tls.reality.shortId = validateRealityShortId(queryValue(query, 'sid') || queryValue(query, 'short_id') ||
      queryValue(query, 'short-id'))
  }

  const resolvedName: string = name.length > 0 ? name : `${protocol}-${server}`
  const canonical: string = JSON.stringify({
    protocol: protocol,
    name: resolvedName,
    server: server,
    port: port,
    username: username,
    password: password,
    uuid: uuid,
    method: resolvedMethod,
    alterId: alterId > 0 ? alterId : undefined,
    flow: resolvedFlow,
    tls: tls,
    transport: transport,
    query: canonicalQuery(query)
  })
  return {
    id: fnv1aId(canonical),
    name: resolvedName,
    protocol: protocol,
    server: server,
    port: port,
    username: username,
    password: password,
    uuid: uuid,
    method: resolvedMethod,
    alterId: alterId,
    flow: resolvedFlow,
    tls: tls,
    transport: transport,
    query: query
  }
}

function parseVmess(value: string): ProxyNode {
  const encoded: string = value.slice('vmess://'.length).split('#')[0].split('?')[0]
  const payload: VmessPayload = JSON.parse(decodeBase64Text(encoded)) as VmessPayload
  const query: QueryItem[] = []
  if (payload.tls) query.push({ key: 'security', value: payload.tls })
  if (payload.sni) query.push({ key: 'sni', value: payload.sni })
  if (payload.alpn) query.push({ key: 'alpn', value: payload.alpn })
  if (payload.fp) query.push({ key: 'fp', value: payload.fp })
  const transport = emptyTransport()
  transport.type = payload.net || ''
  transport.path = payload.path || ''
  transport.host = payload.host || ''
  return makeNode(
    'vmess',
    payload.ps || '',
    payload.add || '',
    parseInteger(payload.port || ''),
    '',
    '',
    payload.id || '',
    payload.scy || 'auto',
    parseAlterId(payload.aid || payload.alterId || ''),
    '',
    query,
    transport
  )
}

function parseShadowsocks(value: string): ProxyNode {
  const parsed: ParsedUri = parseUri(value)
  if (hasQueryKey(parsed.query, 'plugin') || hasQueryKey(parsed.query, 'plugin-opts') ||
    hasQueryKey(parsed.query, 'plugin_opts')) {
    throw new Error('Shadowsocks SIP002/SIP003 plugin 当前版本尚未安全建模，已跳过')
  }
  let authority: string = parsed.authority
  if (authority.indexOf('@') < 0) {
    authority = decodeBase64Text(authority)
  }
  const at: number = authority.lastIndexOf('@')
  if (at < 0) {
    throw new Error('Shadowsocks 节点缺少服务器地址')
  }
  let credential: string = authority.slice(0, at)
  if (credential.indexOf(':') < 0) {
    credential = decodeBase64Text(credential)
  }
  const colon: number = credential.indexOf(':')
  if (colon < 1) {
    throw new Error('Shadowsocks 节点缺少加密方式')
  }
  const address: ParsedAddress = parseAddress(authority.slice(at + 1))
  return makeNode(
    'shadowsocks',
    parsed.name,
    address.host,
    address.port,
    '',
    decodeUrlComponent(credential.slice(colon + 1)),
    '',
    decodeUrlComponent(credential.slice(0, colon)),
    0,
    '',
    parsed.query,
    emptyTransport()
  )
}

function parseStandardUri(value: string): ProxyNode {
  const parsed: ParsedUri = parseUri(value)
  const at: number = parsed.authority.lastIndexOf('@')
  if (at < 0) {
    throw new Error(`${parsed.scheme} 节点缺少凭据`)
  }
  const credential: string = decodeUrlComponent(parsed.authority.slice(0, at))
  const address: ParsedAddress = parseAddress(parsed.authority.slice(at + 1))
  const protocol: ProxyProtocol = parsed.scheme === 'hy2' ? 'hysteria2' : parsed.scheme as ProxyProtocol
  const transport = emptyTransport()
  transport.type = queryValue(parsed.query, 'type')
  transport.path = queryValue(parsed.query, 'path')
  transport.host = queryValue(parsed.query, 'host')
  transport.serviceName = queryValue(parsed.query, 'serviceName')
  return makeNode(
    protocol,
    parsed.name,
    address.host,
    address.port,
    '',
    protocol === 'trojan' || protocol === 'hysteria2' ? credential : '',
    protocol === 'vless' ? credential : '',
    '',
    0,
    queryValue(parsed.query, 'flow'),
    parsed.query,
    transport
  )
}

function parseNodeUri(value: string): ProxyNode {
  if (value.startsWith('vmess://')) {
    return parseVmess(value)
  }
  if (value.startsWith('ss://')) {
    return parseShadowsocks(value)
  }
  return parseStandardUri(value)
}

function supportedProtocol(value: string): ProxyProtocol | null {
  if (value === 'ss' || value === 'shadowsocks') return 'shadowsocks'
  if (value === 'trojan') return 'trojan'
  if (value === 'vless') return 'vless'
  if (value === 'vmess') return 'vmess'
  if (value === 'hysteria2' || value === 'hy2') return 'hysteria2'
  return null
}

function parseUserInfo(value: string): SubscriptionMetadata {
  const metadata: SubscriptionMetadata = emptyMetadata('uri-list')
  const parts: string[] = value.split(';')
  for (let index: number = 0; index < parts.length; index++) {
    const pair: string[] = parts[index].trim().split('=')
    if (pair.length !== 2) continue
    const amount: number = Number.parseInt(pair[1].trim(), 10)
    if (!Number.isFinite(amount)) continue
    const key: string = pair[0].trim().toLowerCase()
    if (key === 'upload') metadata.uploadBytes = amount
    if (key === 'download') metadata.downloadBytes = amount
    if (key === 'total') metadata.totalBytes = amount
    if (key === 'expire') metadata.expireAtSeconds = amount
  }
  return metadata
}

function mergeMetadata(format: SubscriptionFormat, headers: SubscriptionHeaders): SubscriptionMetadata {
  const metadata: SubscriptionMetadata = parseUserInfo(headers.subscriptionUserInfo)
  metadata.sourceFormat = format
  metadata.title = headers.title.trim().length > 0 ? headers.title.trim() : '未命名订阅'
  return metadata
}

function defaultDns(): DnsProfile {
  return { strategy: 'prefer_ipv4', servers: ['https://1.1.1.1/dns-query'] }
}

function defaultGroup(nodes: ProxyNode[]): PolicyGroup[] {
  if (nodes.length === 0) return []
  return [{
    name: '自动选择',
    type: 'select',
    nodeIds: nodes.map((node: ProxyNode) => node.id),
    selectedNodeId: nodes[0].id
  }]
}

function finalizeBundle(bundle: SubscriptionBundle): SubscriptionBundle {
  const nodes: ProxyNode[] = []
  const validNodeIds: string[] = []
  let duplicateCount: number = 0
  for (let index: number = 0; index < bundle.nodes.length; index++) {
    const node: ProxyNode = bundle.nodes[index]
    if (validNodeIds.includes(node.id)) {
      duplicateCount++
      continue
    }
    nodes.push(node)
    validNodeIds.push(node.id)
  }

  const groups: PolicyGroup[] = []
  for (let index: number = 0; index < bundle.policyGroups.length; index++) {
    const source: PolicyGroup = bundle.policyGroups[index]
    const nodeIds: string[] = []
    for (let nodeIndex: number = 0; nodeIndex < source.nodeIds.length; nodeIndex++) {
      const nodeId: string = source.nodeIds[nodeIndex]
      if (validNodeIds.includes(nodeId) && !nodeIds.includes(nodeId)) nodeIds.push(nodeId)
    }
    if (nodeIds.length === 0) continue
    groups.push({
      name: source.name,
      type: source.type,
      nodeIds: nodeIds,
      selectedNodeId: nodeIds.includes(source.selectedNodeId) ? source.selectedNodeId : nodeIds[0]
    })
  }

  const warnings: string[] = bundle.warnings.slice()
  if (duplicateCount > 0) {
    warnings.push(`检测到 ${duplicateCount} 个重复节点，已按配置指纹稳定去重并保留首次出现项`)
  }
  return {
    metadata: bundle.metadata,
    nodes: nodes,
    policyGroups: groups.length > 0 ? groups : defaultGroup(nodes),
    rules: bundle.rules,
    dns: bundle.dns,
    warnings: warnings
  }
}

function normalizeTarget(value: string): RuleTarget {
  const upper: string = value.trim().toUpperCase()
  if (upper === 'DIRECT') return 'direct'
  if (upper.startsWith('REJECT')) return 'reject'
  if (upper === 'PROXY') return 'proxy'
  return stripQuotes(value)
}

function buildSingBoxTargetMap(outbounds: SingBoxOutbound[]): QueryItem[] {
  const targets: QueryItem[] = []
  for (let index: number = 0; index < outbounds.length; index++) {
    const outbound: SingBoxOutbound = outbounds[index]
    const tag: string = (outbound.tag || '').trim()
    if (tag.length === 0) continue
    const type: string = (outbound.type || '').trim().toLowerCase()
    let target: string = ''
    if (type === 'direct') target = 'direct'
    else if (type === 'block' || type === 'reject') target = 'reject'
    else if (type === 'selector' || type === 'urltest') target = tag
    else if (supportedProtocol(type) !== null) target = 'proxy'
    else target = `unsupported:${type.length > 0 ? type : 'unknown'}`
    targets.push({ key: tag, value: target })
  }
  return targets
}

function resolveSingBoxTarget(targetMap: QueryItem[], outboundTag: string): SingBoxTargetResolution {
  const tag: string = outboundTag.trim()
  if (tag.length === 0) return { target: 'proxy', issue: '规则未指定目标出站' }
  const mapped: string = queryValue(targetMap, tag)
  if (mapped === 'direct' || mapped === 'reject' || mapped === 'proxy') {
    return { target: mapped, issue: '' }
  }
  if (mapped.startsWith('unsupported:')) {
    return {
      target: 'proxy',
      issue: `目标出站 ${tag} 的类型 ${mapped.slice('unsupported:'.length)} 尚未支持规则映射`
    }
  }
  if (mapped.length > 0) return { target: mapped, issue: '' }
  return { target: 'proxy', issue: `目标出站 ${tag} 未在 outbounds 中定义` }
}

function singBoxStringList(values: string[] | string | undefined): string[] {
  if (values === undefined) return []
  if (typeof values === 'string') return values.length > 0 ? [values] : []
  return values
}

function addRuleValues(
  rules: RoutingRule[],
  kind: RuleKind,
  sourceValues: string[] | string | undefined,
  target: string,
  source: string
): void {
  const values: string[] = singBoxStringList(sourceValues)
  for (let index: number = 0; index < values.length; index++) {
    rules.push({ kind: kind, value: values[index], target: normalizeTarget(target), source: source })
  }
}

function singBoxRuleCompatibilityIssue(source: SingBoxRule): string {
  const keys: string[] = Object.keys(source)
  const unmodeled: string[] = keys.filter((key: string) => !SUPPORTED_SING_BOX_RULE_KEYS.includes(key))
  if (unmodeled.length > 0) return `未建模字段 ${unmodeled.join(', ')}`

  const ruleType: string = (source.type || '').trim().toLowerCase()
  if (ruleType.length > 0 && ruleType !== 'default') return `逻辑规则类型 ${ruleType}`

  const action: string = (source.action || '').trim().toLowerCase()
  if (action.length > 0 && action !== 'route' && action !== 'reject') return `规则动作 ${action}`

  const matchKinds: string[] = []
  if (singBoxStringList(source.domain).length > 0) matchKinds.push('domain')
  if (singBoxStringList(source.domain_suffix).length > 0) matchKinds.push('domain_suffix')
  if (singBoxStringList(source.domain_keyword).length > 0) matchKinds.push('domain_keyword')
  if (singBoxStringList(source.ip_cidr).length > 0) matchKinds.push('ip_cidr')
  if (singBoxStringList(source.rule_set).length > 0) matchKinds.push('rule_set')
  if (matchKinds.length === 0) return '缺少当前版本可表达的匹配条件'
  // Different match fields in one sing-box rule are conjunctive. Flattening
  // them into independent rules would broaden traffic matches, so block it.
  if (matchKinds.length > 1) return `复合匹配 ${matchKinds.join(' + ')}`
  return ''
}

function parseYamlSections(text: string, section: string): YamlMap[] {
  const lines: string[] = text.replace(/\r/g, '').split('\n')
  const maps: YamlMap[] = []
  let inside: boolean = false
  let current: YamlMap | null = null
  for (let index: number = 0; index < lines.length; index++) {
    const raw: string = lines[index]
    const trimmed: string = raw.trim()
    if (trimmed === `${section}:`) {
      inside = true
      current = null
      continue
    }
    if (!inside) continue
    if (trimmed.length > 0 && !raw.startsWith(' ') && !raw.startsWith('\t')) {
      break
    }
    if (trimmed.startsWith('- ')) {
      const first: string = trimmed.slice(2).trim()
      const values: QueryItem[] = first.startsWith('{') && first.endsWith('}') ? parseInlineYamlValues(first) : []
      current = { name: queryValue(values, 'name'), values: values }
      maps.push(current)
      if (values.length === 0) {
        const colon: number = findTopLevelColon(first)
        if (colon <= 0) continue
        const key: string = first.slice(0, colon).trim()
        const value: string = stripQuotes(first.slice(colon + 1))
        current.values.push({ key: key, value: value })
        if (key === 'name') current.name = value
      }
      continue
    }
    if (current && trimmed.length > 0 && !trimmed.startsWith('#')) {
      const colon: number = findTopLevelColon(trimmed)
      if (colon > 0) {
        const key: string = trimmed.slice(0, colon).trim()
        const value: string = stripQuotes(trimmed.slice(colon + 1))
        current.values.push({ key: key, value: value })
        if (key === 'name') current.name = value
      }
    }
  }
  return maps
}

function parseYamlList(text: string, section: string): string[] {
  const lines: string[] = text.replace(/\r/g, '').split('\n')
  const items: string[] = []
  let inside: boolean = false
  for (let index: number = 0; index < lines.length; index++) {
    const raw: string = lines[index]
    const trimmed: string = raw.trim()
    if (trimmed === `${section}:`) {
      inside = true
      continue
    }
    if (!inside) continue
    if (trimmed.length > 0 && !raw.startsWith(' ') && !raw.startsWith('\t')) break
    if (trimmed.startsWith('- ')) items.push(stripQuotes(trimmed.slice(2)))
  }
  return items
}

export class SubscriptionParser {
  parse(body: string, headers: SubscriptionHeaders = { title: '', subscriptionUserInfo: '' }): SubscriptionBundle {
    let payload: string = body.trim()
    if (payload.length === 0) {
      throw new Error('订阅内容为空')
    }

    if (!payload.startsWith('{') && payload.indexOf('proxies:') < 0 &&
      !SUPPORTED_SCHEMES.some((scheme: string) => payload.indexOf(scheme) >= 0)) {
      payload = decodeBase64Text(payload).trim()
    }

    if (payload.startsWith('{')) {
      return finalizeBundle(this.parseSingBox(payload, headers))
    }
    if (payload.indexOf('proxies:') >= 0) {
      return finalizeBundle(this.parseClash(payload, headers))
    }
    return finalizeBundle(this.parseUriList(payload, headers))
  }

  private parseUriList(payload: string, headers: SubscriptionHeaders): SubscriptionBundle {
    const warnings: string[] = []
    const nodes: ProxyNode[] = []
    const lines: string[] = payload.replace(/\r/g, '').split('\n')
    for (let index: number = 0; index < lines.length; index++) {
      const line: string = lines[index].trim()
      if (line.length === 0 || line.startsWith('#')) continue
      if (!SUPPORTED_SCHEMES.some((scheme: string) => line.startsWith(scheme))) {
        warnings.push(`第 ${index + 1} 行不是首版支持的节点协议，已跳过`)
        continue
      }
      try {
        nodes.push(parseNodeUri(line))
      } catch (error) {
        const message: string = error instanceof Error ? error.message : '无法解析'
        warnings.push(`第 ${index + 1} 行解析失败：${message}`)
      }
    }
    if (nodes.length === 0) {
      const detail: string = warnings.length > 0 ? `：${warnings[0]}` : ''
      throw new Error(`订阅中没有可用的首版节点${detail}`)
    }
    return {
      metadata: mergeMetadata('uri-list', headers),
      nodes: nodes,
      policyGroups: defaultGroup(nodes),
      rules: [],
      dns: defaultDns(),
      warnings: warnings
    }
  }

  private parseSingBox(payload: string, headers: SubscriptionHeaders): SubscriptionBundle {
    const root: SingBoxRoot = JSON.parse(payload) as SingBoxRoot
    const outbounds: SingBoxOutbound[] = root.outbounds || []
    const nodes: ProxyNode[] = []
    const tagToNodeId: QueryItem[] = []
    const warnings: string[] = []
    const tagToRuleTarget: QueryItem[] = buildSingBoxTargetMap(outbounds)

    for (let index: number = 0; index < outbounds.length; index++) {
      const outbound: SingBoxOutbound = outbounds[index]
      const protocol: ProxyProtocol | null = supportedProtocol(outbound.type || '')
      if (!protocol) continue
      try {
        if (protocol === 'shadowsocks' && (outbound.plugin !== undefined || outbound.plugin_opts !== undefined)) {
          throw new Error('Shadowsocks SIP002/SIP003 plugin 当前版本尚未安全建模，已跳过')
        }
        if (protocol === 'hysteria2' && outbound.obfs !== undefined) {
          throw new Error('Hysteria2 obfs 当前版本未完整支持，已跳过')
        }
        const query: QueryItem[] = []
        if (outbound.tls?.reality?.enabled) {
          query.push({ key: 'security', value: 'reality' })
          query.push({ key: 'pbk', value: outbound.tls.reality.public_key || '' })
          if (outbound.tls.reality.short_id) query.push({ key: 'sid', value: outbound.tls.reality.short_id })
        } else if (outbound.tls?.enabled) {
          query.push({ key: 'security', value: 'tls' })
        }
        if (outbound.tls?.server_name) query.push({ key: 'sni', value: outbound.tls.server_name })
        if (outbound.tls?.insecure) query.push({ key: 'insecure', value: 'true' })
        if (outbound.tls?.alpn) query.push({ key: 'alpn', value: outbound.tls.alpn.join(',') })
        if (outbound.tls?.utls?.enabled) {
          query.push({ key: 'utls_enabled', value: 'true' })
          if (outbound.tls.utls.fingerprint) query.push({ key: 'fp', value: outbound.tls.utls.fingerprint })
        }
        const transport = emptyTransport()
        if ((outbound.transport?.max_early_data || 0) > 0 ||
          (outbound.transport?.early_data_header_name || '').length > 0) {
          throw new Error('WebSocket early-data 当前版本未完整建模，已跳过')
        }
        if (hasUnsupportedSingBoxTransportHeaders(outbound.transport?.headers)) {
          throw new Error('transport 自定义 headers 当前版本未完整建模，已跳过')
        }
        transport.type = outbound.transport?.type || ''
        transport.path = outbound.transport?.path || ''
        transport.host = singBoxTransportHost(outbound.transport) || outbound.transport?.headers?.Host ||
          outbound.transport?.headers?.host || ''
        transport.serviceName = outbound.transport?.service_name || ''
        const node: ProxyNode = makeNode(
          protocol,
          outbound.tag || '',
          outbound.server || '',
          outbound.server_port || 0,
          outbound.username || '',
          outbound.password || '',
          outbound.uuid || '',
          protocol === 'vmess' ? (outbound.security || outbound.method || 'auto') : (outbound.method || ''),
          outbound.alter_id || 0,
          outbound.flow || '',
          query,
          transport
        )
        nodes.push(node)
        tagToNodeId.push({ key: outbound.tag || node.name, value: node.id })
      } catch (error) {
        const message: string = error instanceof Error ? error.message : '无法解析'
        warnings.push(`出站 ${outbound.tag || index + 1} 解析失败：${message}`)
      }
    }
    if (nodes.length === 0) {
      const detail: string = warnings.length > 0 ? `：${warnings[0]}` : ''
      throw new Error(`sing-box 配置中没有首版支持的代理出站${detail}`)
    }

    const groups: PolicyGroup[] = []
    for (let index: number = 0; index < outbounds.length; index++) {
      const outbound: SingBoxOutbound = outbounds[index]
      if (outbound.type !== 'selector' && outbound.type !== 'urltest') continue
      const nodeIds: string[] = (outbound.outbounds || []).map((tag: string) => queryValue(tagToNodeId, tag))
        .filter((id: string) => id.length > 0)
      if (nodeIds.length === 0) continue
      const selected: string = queryValue(tagToNodeId, outbound.default || '') || nodeIds[0]
      groups.push({
        name: outbound.tag || '代理',
        type: outbound.type === 'urltest' ? 'urltest' : 'select',
        nodeIds: nodeIds,
        selectedNodeId: selected
      })
    }

    const rules: RoutingRule[] = []
    const sourceRules: SingBoxRule[] = root.route?.rules || []
    for (let index: number = 0; index < sourceRules.length; index++) {
      const sourceRule: SingBoxRule = sourceRules[index]
      const action: string = (sourceRule.action || '').trim().toLowerCase()
      const targetResolution: SingBoxTargetResolution = action === 'reject' ? { target: 'reject', issue: '' } :
        resolveSingBoxTarget(tagToRuleTarget, sourceRule.outbound || '')
      const ruleCompatibilityIssue: string = singBoxRuleCompatibilityIssue(sourceRule)
      const compatibilityIssue: string = ruleCompatibilityIssue.length > 0 ? ruleCompatibilityIssue :
        targetResolution.issue
      if (compatibilityIssue.length > 0) {
        rules.push({
          kind: 'unsupported',
          value: `sing-box 规则 ${index + 1}：${compatibilityIssue}`,
          target: targetResolution.target,
          source: 'subscription'
        })
        warnings.push(`sing-box 规则 ${index + 1} 包含${compatibilityIssue}；规则模式已被安全阻止`)
        continue
      }
      addRuleValues(rules, 'domain', sourceRule.domain, targetResolution.target, 'subscription')
      addRuleValues(rules, 'domain_suffix', sourceRule.domain_suffix, targetResolution.target, 'subscription')
      addRuleValues(rules, 'domain_keyword', sourceRule.domain_keyword, targetResolution.target, 'subscription')
      addRuleValues(rules, 'ip_cidr', sourceRule.ip_cidr, targetResolution.target, 'subscription')
      addRuleValues(rules, 'rule_set', sourceRule.rule_set, targetResolution.target, 'subscription')
    }
    if (root.route?.final) {
      const finalResolution: SingBoxTargetResolution = resolveSingBoxTarget(tagToRuleTarget, root.route.final)
      if (finalResolution.issue.length > 0) {
        rules.push({
          kind: 'unsupported',
          value: `sing-box final：${finalResolution.issue}`,
          target: finalResolution.target,
          source: 'subscription'
        })
        warnings.push(`sing-box final 的${finalResolution.issue}；规则模式已被安全阻止`)
      } else {
        rules.push({ kind: 'final', value: '', target: finalResolution.target, source: 'subscription' })
      }
    }

    const dnsServers: string[] = []
    const sourceServers: SingBoxDnsServer[] = root.dns?.servers || []
    for (let index: number = 0; index < sourceServers.length; index++) {
      const address: string = sourceServers[index].address || sourceServers[index].server || ''
      if (address.length > 0) dnsServers.push(address)
    }
    return {
      metadata: mergeMetadata('sing-box-json', headers),
      nodes: nodes,
      policyGroups: groups.length > 0 ? groups : defaultGroup(nodes),
      rules: rules,
      dns: {
        strategy: root.dns?.strategy || 'prefer_ipv4',
        servers: dnsServers.length > 0 ? dnsServers : defaultDns().servers
      },
      warnings: warnings
    }
  }

  private parseClash(payload: string, headers: SubscriptionHeaders): SubscriptionBundle {
    const proxyMaps: YamlMap[] = parseYamlSections(payload, 'proxies')
    const nodes: ProxyNode[] = []
    const nameToNodeId: QueryItem[] = []
    const warnings: string[] = ['当前为 Clash/Mihomo YAML 常用字段解析器；复杂锚点和 provider 将在真机版接入完整解析器']

    for (let index: number = 0; index < proxyMaps.length; index++) {
      const map: YamlMap = proxyMaps[index]
      const protocol: ProxyProtocol | null = supportedProtocol(yamlValue(map.values, 'type').toLowerCase())
      if (!protocol) {
        warnings.push(`节点 ${map.name || index + 1} 的协议暂不支持`)
        continue
      }
      if (protocol === 'shadowsocks' && (hasQueryKey(map.values, 'plugin') ||
        hasQueryKey(map.values, 'plugin-opts') || hasQueryKey(map.values, 'plugin_opts'))) {
        warnings.push(`节点 ${map.name || index + 1} 使用 Shadowsocks SIP002/SIP003 plugin，当前版本尚未安全建模，已跳过`)
        continue
      }
      const query: QueryItem[] = []
      const realityInline: QueryItem[] = parseInlineYamlValues(yamlValue(map.values, 'reality-opts'))
      const realityPublicKey: string = queryValue(realityInline, 'public-key') ||
        queryValue(realityInline, 'public_key') || yamlValue(map.values, 'public-key') || yamlValue(map.values, 'public_key')
      const realityShortId: string = queryValue(realityInline, 'short-id') ||
        queryValue(realityInline, 'short_id') || yamlValue(map.values, 'short-id') || yamlValue(map.values, 'short_id')
      const hasReality: boolean = hasQueryKey(map.values, 'reality-opts') || realityPublicKey.length > 0
      const tlsValue: string = yamlValue(map.values, 'tls')
      if (hasReality) {
        query.push({ key: 'security', value: 'reality' })
        query.push({ key: 'pbk', value: realityPublicKey })
        if (realityShortId.length > 0) query.push({ key: 'sid', value: realityShortId })
      } else if (isTrue(tlsValue)) {
        query.push({ key: 'security', value: 'tls' })
      }
      const sni: string = yamlValue(map.values, 'servername') || yamlValue(map.values, 'sni')
      if (sni.length > 0) query.push({ key: 'sni', value: sni })
      if (isTrue(yamlValue(map.values, 'skip-cert-verify'))) query.push({ key: 'insecure', value: 'true' })
      const fingerprint: string = yamlValue(map.values, 'client-fingerprint') || yamlValue(map.values, 'fingerprint')
      if (fingerprint.length > 0) query.push({ key: 'fp', value: fingerprint })
      if (hasQueryKey(map.values, 'obfs') || hasQueryKey(map.values, 'obfs-password')) {
        query.push({ key: 'obfs', value: yamlValue(map.values, 'obfs') })
      }
      const wsInline: QueryItem[] = parseInlineYamlValues(yamlValue(map.values, 'ws-opts'))
      const wsHeadersInline: QueryItem[] = parseInlineYamlValues(queryValue(wsInline, 'headers'))
      const grpcInline: QueryItem[] = parseInlineYamlValues(yamlValue(map.values, 'grpc-opts'))
      const transport = emptyTransport()
      const wsEarlyData: string = queryValue(wsInline, 'max-early-data') || queryValue(wsInline, 'max_early_data') ||
        yamlValue(map.values, 'max-early-data') || yamlValue(map.values, 'max_early_data')
      const wsEarlyHeader: string = queryValue(wsInline, 'early-data-header-name') ||
        queryValue(wsInline, 'early_data_header_name') || yamlValue(map.values, 'early-data-header-name') ||
        yamlValue(map.values, 'early_data_header_name')
      if ((wsEarlyData.length > 0 && Number(wsEarlyData) > 0) || wsEarlyHeader.length > 0) {
        warnings.push(`节点 ${map.name || index + 1} 使用 WebSocket early-data，当前版本未完整建模，已跳过`)
        continue
      }
      transport.type = yamlValue(map.values, 'network')
      transport.path = queryValue(wsInline, 'path') || yamlValue(map.values, 'path')
      transport.host = queryValue(wsHeadersInline, 'Host') || queryValue(wsInline, 'host') ||
        yamlValue(map.values, 'Host') || yamlValue(map.values, 'host')
      transport.serviceName = queryValue(grpcInline, 'grpc-service-name') ||
        queryValue(grpcInline, 'service-name') || yamlValue(map.values, 'grpc-service-name') ||
        yamlValue(map.values, 'service-name') || yamlValue(map.values, 'serviceName')
      try {
        const node: ProxyNode = makeNode(
          protocol,
          map.name,
          yamlValue(map.values, 'server'),
          parseInteger(yamlValue(map.values, 'port')),
          yamlValue(map.values, 'username'),
          yamlValue(map.values, 'password'),
          yamlValue(map.values, 'uuid'),
          yamlValue(map.values, 'cipher'),
          parseAlterId(yamlValue(map.values, 'alterId') || yamlValue(map.values, 'alter-id')),
          yamlValue(map.values, 'flow'),
          query,
          transport
        )
        nodes.push(node)
        nameToNodeId.push({ key: node.name, value: node.id })
      } catch (error) {
        const message: string = error instanceof Error ? error.message : '无法解析'
        warnings.push(`节点 ${map.name || index + 1} 解析失败：${message}`)
      }
    }
    if (nodes.length === 0) {
      const detail: string = warnings.length > 1 ? `：${warnings[1]}` : ''
      throw new Error(`Clash/Mihomo 配置中没有首版支持的代理节点${detail}`)
    }

    const groups: PolicyGroup[] = []
    const groupMaps: YamlMap[] = parseYamlSections(payload, 'proxy-groups')
    for (let index: number = 0; index < groupMaps.length; index++) {
      const group: YamlMap = groupMaps[index]
      const type: string = yamlValue(group.values, 'type').toLowerCase()
      if (type !== 'select' && type !== 'url-test') continue
      const nodeIds: string[] = splitCsv(yamlValue(group.values, 'proxies'))
        .map((name: string) => queryValue(nameToNodeId, name))
        .filter((id: string) => id.length > 0)
      if (nodeIds.length > 0) {
        groups.push({
          name: group.name || '代理',
          type: type === 'url-test' ? 'urltest' : 'select',
          nodeIds: nodeIds,
          selectedNodeId: nodeIds[0]
        })
      }
    }

    const rules: RoutingRule[] = []
    const sourceRules: string[] = parseYamlList(payload, 'rules')
    for (let index: number = 0; index < sourceRules.length; index++) {
      const parts: string[] = sourceRules[index].split(',').map((item: string) => item.trim())
      const type: string = parts[0].toUpperCase()
      if ((type === 'MATCH' || type === 'FINAL') && parts.length >= 2) {
        rules.push({ kind: 'final', value: '', target: normalizeTarget(parts[1]), source: 'subscription' })
      } else if (parts.length >= 3) {
        let kind: RuleKind | null = null
        if (type === 'DOMAIN') kind = 'domain'
        if (type === 'DOMAIN-SUFFIX') kind = 'domain_suffix'
        if (type === 'DOMAIN-KEYWORD') kind = 'domain_keyword'
        if (type === 'IP-CIDR' || type === 'IP-CIDR6') kind = 'ip_cidr'
        if (type === 'RULE-SET') kind = 'rule_set'
        if (kind) {
          rules.push({ kind: kind, value: parts[1], target: normalizeTarget(parts[2]), source: 'subscription' })
        } else {
          rules.push({
            kind: 'unsupported',
            value: sourceRules[index],
            target: normalizeTarget(parts[parts.length - 1]),
            source: 'subscription'
          })
          warnings.push(`规则类型 ${type || '未知'} 尚不支持；规则模式已被安全阻止`)
        }
      } else if (sourceRules[index].trim().length > 0) {
        rules.push({ kind: 'unsupported', value: sourceRules[index], target: 'proxy', source: 'subscription' })
        warnings.push(`规则 ${sourceRules[index]} 格式不完整；规则模式已被安全阻止`)
      }
    }

    return {
      metadata: mergeMetadata('clash-yaml', headers),
      nodes: nodes,
      policyGroups: groups.length > 0 ? groups : defaultGroup(nodes),
      rules: rules,
      dns: defaultDns(),
      warnings: warnings
    }
  }
}
