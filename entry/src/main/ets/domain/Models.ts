export type ProxyProtocol = 'shadowsocks' | 'trojan' | 'vless' | 'vmess' | 'hysteria2'
export type SubscriptionFormat = 'sing-box-json' | 'clash-yaml' | 'uri-list'
export type RunMode = 'rule' | 'global' | 'direct'
export type NodeSelectionMode = 'manual' | 'auto' | 'failover'
export type CoreLogLevel = 'debug' | 'info' | 'warn' | 'error'
export type PolicyGroupType = 'select' | 'urltest'
export type RuleKind = 'domain' | 'domain_suffix' | 'domain_keyword' | 'ip_cidr' | 'rule_set' | 'unsupported' | 'final'
export type RuleTarget = 'proxy' | 'direct' | 'reject' | string

export interface QueryItem {
  key: string
  value: string
}

export interface TlsOptions {
  enabled: boolean
  serverName: string
  insecure: boolean
  alpn: string[]
  utls: UtlsOptions
  reality: RealityOptions
}

export interface UtlsOptions {
  enabled: boolean
  fingerprint: string
}

export interface RealityOptions {
  enabled: boolean
  publicKey: string
  shortId: string
}

export interface TransportOptions {
  type: string
  path: string
  host: string
  serviceName: string
}

export interface ProxyNode {
  id: string
  name: string
  protocol: ProxyProtocol
  server: string
  port: number
  username: string
  password: string
  uuid: string
  method: string
  alterId?: number
  flow: string
  tls: TlsOptions
  transport: TransportOptions
  query: QueryItem[]
}

export interface SubscriptionMetadata {
  title: string
  uploadBytes: number
  downloadBytes: number
  totalBytes: number
  expireAtSeconds: number
  sourceFormat: SubscriptionFormat
}

export interface PolicyGroup {
  name: string
  type: PolicyGroupType
  nodeIds: string[]
  selectedNodeId: string
}

export interface RoutingRule {
  kind: RuleKind
  value: string
  target: RuleTarget
  source: string
}

export interface DnsProfile {
  strategy: string
  servers: string[]
}

export interface SubscriptionBundle {
  metadata: SubscriptionMetadata
  nodes: ProxyNode[]
  policyGroups: PolicyGroup[]
  rules: RoutingRule[]
  dns: DnsProfile
  warnings: string[]
}

export interface SubscriptionRecord {
  id: string
  sourceUrl: string
  customName: string
  bundle: SubscriptionBundle
  selectedNodeId: string
  createdAtMillis: number
  updatedAtMillis: number
}

export interface SubscriptionStoreState {
  schemaVersion: number
  records: SubscriptionRecord[]
  activeSubscriptionId: string
}

export interface NodeLatency {
  nodeId: string
  milliseconds: number
}

export interface SubscriptionHeaders {
  title: string
  subscriptionUserInfo: string
}

export interface ConfigBuildRequest {
  bundle: SubscriptionBundle
  mode: RunMode
  selectedNodeId: string
  selectionMode?: NodeSelectionMode
  logLevel?: CoreLogLevel
  ipv6Enabled?: boolean
  /**
   * App-owned rules are stored separately from the imported subscription so
   * refreshing a profile can never overwrite them. The builder accepts only
   * the deliberately small, validated local rule subset.
   */
  localRules?: RoutingRule[]
}

export interface ConfigBuildResult {
  configJson: string
  warnings: string[]
}

export function emptyTls(): TlsOptions {
  return {
    enabled: false,
    serverName: '',
    insecure: false,
    alpn: [],
    utls: {
      enabled: false,
      fingerprint: ''
    },
    reality: {
      enabled: false,
      publicKey: '',
      shortId: ''
    }
  }
}

export function emptyTransport(): TransportOptions {
  return {
    type: '',
    path: '',
    host: '',
    serviceName: ''
  }
}

export function emptyMetadata(format: SubscriptionFormat): SubscriptionMetadata {
  return {
    title: '未命名订阅',
    uploadBytes: 0,
    downloadBytes: 0,
    totalBytes: 0,
    expireAtSeconds: 0,
    sourceFormat: format
  }
}
