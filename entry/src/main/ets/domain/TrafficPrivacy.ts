export interface TrafficPrivacy { ipv6Enabled: boolean; protectWebRtc: boolean; strictWebRtc?: boolean }
function collectModes(rules: Record<string, Object>[], modes: string[]): void {
  for (const rule of rules) {
    if (typeof rule.clash_mode === 'string' && !modes.includes(rule.clash_mode)) modes.push(rule.clash_mode)
    if (Array.isArray(rule.rules)) collectModes(rule.rules as Record<string, Object>[], modes)
  }
}
export function applyTrafficPrivacy(text: string, privacy: TrafficPrivacy): string {
  const config: Record<string, Object> = JSON.parse(text) as Record<string, Object>
  const inbounds: Record<string, Object>[] = (config.inbounds || []) as Record<string, Object>[]
  const tags: string[] = inbounds.filter((item: Record<string, Object>) => item.type === 'tun' && typeof item.tag === 'string').map((item: Record<string, Object>) => item.tag as string)
  if (tags.length === 0) throw new Error('隐私保护需要有效的 TUN 入站')
  const route: Record<string, Object> = (config.route || {}) as Record<string, Object>
  const original: Record<string, Object>[] = (route.rules || []) as Record<string, Object>[]
  const outbounds: Record<string, Object>[] = (config.outbounds || []) as Record<string, Object>[]
  const proxy: Record<string, Object> | undefined = outbounds.find((item: Record<string, Object>) => item.tag === route.final && item.type !== 'direct' && item.type !== 'block') || outbounds.find((item: Record<string, Object>) => item.type === 'selector') || outbounds.find((item: Record<string, Object>) => item.type !== 'direct' && item.type !== 'block' && typeof item.tag === 'string')
  const modes: string[] = []
  collectModes(original, modes)
  const experimental: Record<string, Object> = (config.experimental || {}) as Record<string, Object>
  const clash: Record<string, Object> = (experimental.clash_api || {}) as Record<string, Object>
  if (typeof clash.default_mode === 'string' && !modes.includes(clash.default_mode)) modes.push(clash.default_mode)
  for (const mode of ['rule', 'global']) if (!modes.some((value: string) => value.toLowerCase() === mode)) modes.push(mode)
  const protectedModes: string[] = modes.filter((mode: string) => ['rule', 'global'].includes(mode.toLowerCase()))
  const sniff: Record<string, Object> = { inbound: tags, network: 'udp', action: 'sniff', sniffer: ['dns', 'stun'], timeout: '100ms' }
  const dnsPort: Record<string, Object> = { inbound: tags, port: 53, action: 'hijack-dns' }
  const stunRule = (mode: string, strict: boolean): Record<string, Object> => strict
    ? { inbound: tags, protocol: 'stun', clash_mode: mode, action: 'reject' }
    : { inbound: tags, protocol: 'stun', clash_mode: mode, action: 'route', outbound: proxy ? proxy.tag : '' }
  // Remove only the exact generated shapes; the original stored profile is
  // never rewritten. Include both policies so toggling remains idempotent.
  const knownModes: string[] = Array.from(new Set([...protectedModes, 'rule', 'Rule', 'global', 'Global']))
  const managed: string[] = [sniff, dnsPort, ...knownModes.map((mode: string) => stunRule(mode, false)), ...knownModes.map((mode: string) => stunRule(mode, true))].map((rule: Record<string, Object>) => JSON.stringify(rule))
  const rules: Record<string, Object>[] = original.filter((rule: Record<string, Object>) => !managed.includes(JSON.stringify(rule)))
  const strict: boolean = privacy.strictWebRtc === true
  const enabled: boolean = strict || (privacy.protectWebRtc && proxy !== undefined)
  const dns: Record<string, Object> = (config.dns || {}) as Record<string, Object>
  const prefix: Record<string, Object>[] = []
  if (enabled) prefix.push(sniff)
  if (Array.isArray(dns.servers) && (dns.servers as Object[]).length > 0) prefix.push(dnsPort)
  if (enabled) prefix.push(...protectedModes.map((mode: string) => stunRule(mode, strict)))
  route.rules = [...prefix, ...rules]
  config.route = route
  return JSON.stringify(config)
}
