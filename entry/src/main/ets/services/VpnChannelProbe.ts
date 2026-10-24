import { connection } from '@kit.NetworkKit'
export type VpnChannelState = 'owned' | 'absent' | 'foreign' | 'unknown'
export interface VpnChannelSample { state: VpnChannelState; netId: number }

// A failed inventory is unknown, never evidence that a VPN disappeared.
// Discovery is allowed only while this Extension owns a successfully created TUN.
export async function probeVpnChannel(ownedId: number): Promise<VpnChannelSample> {
  try {
    let vpnCount: number = 0
    let matched: number = -1
    for (const handle of await connection.getAllNets()) {
      const caps: connection.NetCapabilities = await connection.getNetCapabilities(handle)
      if (!caps.bearerTypes.includes(connection.NetBearType.BEARER_VPN)) continue
      vpnCount++
      const properties: connection.ConnectionProperties = await connection.getConnectionProperties(handle)
      const ours: boolean = properties.linkAddresses.some((item: connection.LinkAddress) => item.address.address === '172.19.0.1' || item.address.address === 'fdfe:dcba:9876::1')
      if (ours && (ownedId === -1 || ownedId === handle.netId)) matched = handle.netId
    }
    if (vpnCount === 0) return { state: 'absent', netId: -1 }
    if (matched >= 0) return vpnCount === 1 ? { state: 'owned', netId: matched } : { state: 'unknown', netId: -1 }
    return { state: 'foreign', netId: -1 }
  } catch (_) { return { state: 'unknown', netId: -1 } }
}
