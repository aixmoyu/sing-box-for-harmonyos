import { connection } from '@kit.NetworkKit'

interface PhysicalCandidate { handle: connection.NetHandle; wifi: boolean }
interface PhysicalSignature { id: number; kind: string; interface: string; addresses: string[]; dns: string[] }

// Same deterministic underlay preference as the native socket binding code.
// The signature stays private and is never written to logs or runtime IPC.
export async function physicalNetworkSignature(): Promise<string> {
  const candidates: PhysicalCandidate[] = []
  for (const handle of await connection.getAllNets()) {
    const caps: connection.NetCapabilities = await connection.getNetCapabilities(handle)
    if (caps.bearerTypes.includes(connection.NetBearType.BEARER_VPN) ||
      !caps.networkCap?.includes(connection.NetCap.NET_CAPABILITY_INTERNET) ||
      !caps.networkCap?.includes(connection.NetCap.NET_CAPABILITY_NOT_VPN) ||
      !caps.networkCap?.includes(connection.NetCap.NET_CAPABILITY_VALIDATED)) continue
    const wifi: boolean = caps.bearerTypes.includes(connection.NetBearType.BEARER_WIFI)
    if (!wifi && !caps.bearerTypes.includes(connection.NetBearType.BEARER_CELLULAR)) continue
    candidates.push({ handle: handle, wifi: wifi })
  }
  candidates.sort((a: PhysicalCandidate, b: PhysicalCandidate): number =>
    a.wifi !== b.wifi ? (a.wifi ? -1 : 1) : a.handle.netId - b.handle.netId)
  if (candidates.length === 0) return 'none'
  const selected: PhysicalCandidate = candidates[0]
  const properties: connection.ConnectionProperties = await connection.getConnectionProperties(selected.handle)
  const signature: PhysicalSignature = { id: selected.handle.netId, kind: selected.wifi ? 'wifi' : 'cellular', interface: properties.interfaceName,
    addresses: properties.linkAddresses.map((item: connection.LinkAddress) => item.address.address + '/' + item.prefixLength).sort(),
    dns: properties.dnses.map((item: connection.NetAddress) => item.address).sort() }
  return JSON.stringify(signature)
}

// Bootstrap proxy hostnames against the physical network's DNS, never the
// active custom VPN's resolver (which may supply FakeIP or reject the node).
export async function physicalProbeDns(): Promise<string> {
  const text: string = await physicalNetworkSignature()
  if (text === 'none') throw new Error('网络不可用')
  const snapshot: PhysicalSignature = JSON.parse(text) as PhysicalSignature
  const servers: string[] = snapshot.dns.filter((address: string) => address.length > 0 && !address.includes('%'))
  const selected: string | undefined = servers.find((address: string) => !address.includes(':')) || servers[0]
  if (!selected) throw new Error('DNS 失败')
  return selected
}
