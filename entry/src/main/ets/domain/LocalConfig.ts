import { applyTrafficPrivacy } from './TrafficPrivacy.ts'
import type { TrafficPrivacy } from './TrafficPrivacy.ts'
function hasRoutingMode(rules: Record<string, Object>[], mode: string): boolean {
  return rules.some((rule: Record<string, Object>): boolean =>
    (typeof rule.clash_mode === 'string' && (rule.clash_mode as string).toLowerCase() === mode) ||
    (Array.isArray(rule.rules) && hasRoutingMode(rule.rules as Record<string, Object>[], mode)))
}

export function prepareLocalConfig(text: string, privacy?: TrafficPrivacy): string {
  const config: Record<string, Object> = JSON.parse(text.replace(/^\uFEFF/, '')) as Record<string, Object>
  if (!config || Array.isArray(config) || !Array.isArray(config.outbounds) || (config.outbounds as Object[]).length === 0) {
    throw new Error('请选择完整 sing-box JSON：需要非空 outbounds')
  }
  const inbounds: Record<string, Object>[] = (config.inbounds || []) as Record<string, Object>[]
  if (!Array.isArray(inbounds)) throw new Error('inbounds 必须是数组')
  let tag: string = 'tun-in'
  let count: number = 0
  const adapted: Object[] = []
  for (const inbound of inbounds) {
    if (inbound.type === 'tun') {
      count++
      if (typeof inbound.tag === 'string') tag = inbound.tag as string
    } else {
      adapted.push(inbound)
    }
  }
  if (count > 1) throw new Error('鸿蒙 VPN 只支持一个 TUN 入站')
  const tun: Record<string, Object> = {
    type: 'tun', tag: tag, address: ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
    mtu: 1400, stack: 'gvisor'
  }
  adapted.push(tun)
  config.inbounds = adapted
  const route: Record<string, Object> = (config.route || {}) as Record<string, Object>
  config.route = route
  if (!route.rules) route.rules = []
  // Add real routing semantics for the three dashboard modes. Keep imported
  // rules intact in rule mode; do not merely expose decorative mode buttons.
  const outbounds: Record<string, Object>[] = config.outbounds as Record<string, Object>[]
  let direct: Record<string, Object> | undefined = outbounds.find((item: Record<string, Object>) => item.type === 'direct' && typeof item.tag === 'string')
  if (!direct) {
    let directTag: string = 'harmony-direct'
    while (outbounds.some((item: Record<string, Object>) => item.tag === directTag)) directTag += '-1'
    direct = { type: 'direct', tag: directTag }
    outbounds.push(direct)
  }
  const preferred: Record<string, Object> | undefined = outbounds.find((item: Record<string, Object>) => item.tag === route.final && item.type !== 'direct' && item.type !== 'block') ||
    outbounds.find((item: Record<string, Object>) => item.type === 'selector') ||
    outbounds.find((item: Record<string, Object>) => item.type !== 'direct' && item.type !== 'block' && typeof item.tag === 'string')
  if (preferred) {
    const rules: Record<string, Object>[] = route.rules as Record<string, Object>[]
    const supplemental: Object[] = []
    if (!hasRoutingMode(rules, 'direct')) {
      supplemental.push({ clash_mode: 'direct', port: 53, action: 'hijack-dns' })
      supplemental.push({ clash_mode: 'direct', outbound: direct.tag })
    }
    if (!hasRoutingMode(rules, 'global')) {
      supplemental.push({ clash_mode: 'global', port: 53, action: 'hijack-dns' })
      supplemental.push({ clash_mode: 'global', outbound: preferred.tag })
    }
    route.rules = [...supplemental, ...rules]
  }
  route.auto_detect_interface = false
  const runtime: string = JSON.stringify(config)
  return privacy ? applyTrafficPrivacy(runtime, privacy) : runtime
}
