export interface TrafficPrivacy { ipv6Enabled: boolean; protectWebRtc: boolean }

function collectModes(rules: Record<string, Object>[], modes: string[]): void {
  for (const rule of rules) {
    if (typeof rule.clash_mode === 'string' && !modes.includes(rule.clash_mode)) modes.push(rule.clash_mode)
    if (Array.isArray(rule.rules)) collectModes(rule.rules as Record<string, Object>[], modes)
  }
}

export function applyTrafficPrivacy(text: string, privacy: TrafficPrivacy): string {
  const config: Record<string, Object> = JSON.parse(text) as Record<string, Object>
  const inbounds: Record<string, Object>[] = (config.inbounds || []) as Record<string, Object>[]
  const tun: Record<string, Object> | undefined = inbounds.find((item: Record<string, Object>) => item.type === 'tun')
  if (!tun || typeof tun.tag !== 'string') throw new Error('隐私保护需要有效的 TUN 入站')
  const route: Record<string, Object> = (config.route || {}) as Record<string, Object>
  const outbounds: Record<string, Object>[] = (config.outbounds || []) as Record<string, Object>[]
  const proxy: Record<string, Object> | undefined = outbounds.find((item: Record<string, Object>) => item.tag === route.final && item.type !== 'direct' && item.type !== 'block') ||
    outbounds.find((item: Record<string, Object>) => item.type === 'selector') ||
    outbounds.find((item: Record<string, Object>) => item.type !== 'direct' && item.type !== 'block' && typeof item.tag === 'string')
  const ipv6: Record<string, Object> = { inbound: [tun.tag], ip_version: 6, action: 'reject' }
  const sniff: Record<string, Object> = { inbound: [tun.tag], network: 'udp', action: 'sniff', sniffer: ['dns', 'stun'], timeout: '100ms' }
  const dnsPort: Record<string, Object> = { inbound: [tun.tag], port: 53, action: 'hijack-dns' }
  const stunRule = (mode: string): Record<string, Object> => { return { inbound: [tun.tag], protocol: 'stun', clash_mode: mode, action: 'route', outbound: proxy ? proxy.tag : '' } }
  const managed: string[] = [ipv6, sniff, dnsPort, ...['rule', 'Rule', 'global', 'Global'].map(stunRule)].map((rule: Record<string, Object>) => JSON.stringify(rule))
  const rules: Record<string, Object>[] = ((route.rules || []) as Record<string, Object>[]).filter((rule: Record<string, Object>) => !managed.includes(JSON.stringify(rule)))
  const modes: string[] = []
  collectModes(rules, modes)
  const experimental: Record<string, Object> = (config.experimental || {}) as Record<string, Object>
  const clash: Record<string, Object> = (experimental.clash_api || {}) as Record<string, Object>
  if (typeof clash.default_mode === 'string' && !modes.includes(clash.default_mode)) modes.push(clash.default_mode)
  for (const mode of ['rule', 'global']) {
    if (!modes.some((value: string) => value.toLowerCase() === mode)) modes.push(mode)
  }
  const stun: Record<string, Object>[] = modes.filter((mode: string) => ['rule', 'global'].includes(mode.toLowerCase())).map(stunRule)
  const prefix: Record<string, Object>[] = []
  if (!privacy.ipv6Enabled) prefix.push(ipv6)
  const dns: Record<string, Object> = (config.dns || {}) as Record<string, Object>
  const hasDns: boolean = Array.isArray(dns.servers) && (dns.servers as Object[]).length > 0
  if (privacy.protectWebRtc && proxy) prefix.push(sniff)
  if (hasDns) prefix.push(dnsPort)
  if (privacy.protectWebRtc && proxy) prefix.push(...stun)
  route.rules = [...prefix, ...rules]
  config.route = route
  return JSON.stringify(config)
}
