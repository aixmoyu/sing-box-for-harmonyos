import { connection } from '@kit.NetworkKit'
import { SystemVpnBearerState } from './VpnRuntimeProtocol'

const INVENTORY_POLL_ATTEMPTS: number = 16
const INVENTORY_POLL_INTERVAL_MS: number = 250
const REQUIRED_ABSENT_SNAPSHOTS: number = 2

function delay(milliseconds: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, milliseconds)
  })
}

/**
 * Reads a complete system network inventory. A single failed capability read
 * makes the snapshot unknown: a network disappearing during enumeration must
 * never be reinterpreted as proof that no VPN exists.
 */
export async function readSystemVpnBearerState(): Promise<SystemVpnBearerState> {
  try {
    const networks: connection.NetHandle[] = await connection.getAllNets()
    for (let index: number = 0; index < networks.length; index++) {
      const capabilities: connection.NetCapabilities =
        await connection.getNetCapabilities(networks[index])
      if (capabilities.bearerTypes.indexOf(connection.NetBearType.BEARER_VPN) >= 0) {
        return 'present'
      }
    }
    return 'absent'
  } catch (_) {
    return 'unknown'
  }
}

/**
 * Waits for two consecutive complete snapshots without a VPN bearer. The
 * second snapshot closes the asynchronous gap between the Extension lifecycle
 * stop acknowledgement and NetManager removing the VPN network.
 */
export async function waitForSystemVpnBearerAbsent(): Promise<boolean> {
  let consecutiveAbsent: number = 0
  for (let attempt: number = 0; attempt < INVENTORY_POLL_ATTEMPTS; attempt++) {
    const state: SystemVpnBearerState = await readSystemVpnBearerState()
    if (state === 'absent') {
      consecutiveAbsent++
      if (consecutiveAbsent >= REQUIRED_ABSENT_SNAPSHOTS) return true
    } else {
      consecutiveAbsent = 0
    }
    await delay(INVENTORY_POLL_INTERVAL_MS)
  }
  return false
}
