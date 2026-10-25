// A profile that declares an IPv6 TUN address takes over IPv6: the client
// captures it and routes it like any other traffic. Whether IPv6 actually
// works then depends on the proxy server (a VPS without IPv6 will simply fail
// those connections; it must never silently fall back to the physical link).
export function configIpv6Enabled(text: string): boolean {
  let config: Record<string, Object>
  try { config = JSON.parse(text.replace(/^\uFEFF/, '')) as Record<string, Object> } catch (_) { return false }
  const inbounds: Object[] = (config.inbounds || []) as Object[]
  for (let index: number = 0; index < inbounds.length; index++) {
    const inbound: Record<string, Object> = inbounds[index] as Record<string, Object>
    if (inbound.type !== 'tun') continue
    const address: Object = inbound.address
    if (Array.isArray(address)) {
      const list: string[] = address as string[]
      for (let item: number = 0; item < list.length; item++) {
        if (list[item].includes(':')) return true
      }
    }
  }
  const dns: Record<string, Object> = (config.dns || {}) as Record<string, Object>
  const servers: Object[] = (dns.servers || []) as Object[]
  for (let index: number = 0; index < servers.length; index++) {
    const entry: Record<string, Object> = servers[index] as Record<string, Object>
    const value: string = typeof entry.server === 'string' ? entry.server as string :
      (typeof entry.address === 'string' ? entry.address as string : '')
    if (value.includes(':') && !value.includes('://')) return true
  }
  const outbounds: Object[] = (config.outbounds || []) as Object[]
  for (let index: number = 0; index < outbounds.length; index++) {
    const outbound: Record<string, Object> = outbounds[index] as Record<string, Object>
    if (typeof outbound.server === 'string' && (outbound.server as string).includes(':')) return true
  }
  return false
}
