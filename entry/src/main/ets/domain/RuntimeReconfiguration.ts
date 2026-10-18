export type RuntimeReconfigurationPlan = 'persist-only' | 'restart-runtime' | 'reject'

export type RuntimeReconfigurationRecovery = 'rollback-and-reconnect' | 'keep-new-unknown'

export interface RuntimeReconfigurationGate {
  configurationBusy: boolean
  settingsLoading: boolean
  subscriptionsLoading: boolean
  connectionBusy: boolean
  connectionPhase: string
}

/**
 * Pure gate used by the UI before a setting that changes the generated
 * sing-box/TUN configuration is accepted.
 *
 * An idle runtime only needs persistence. A connected runtime must be
 * restarted as one serialized transaction. Unknown/error/busy states remain
 * locked because changing labels there would not prove what is really active.
 */
export function planRuntimeReconfiguration(gate: RuntimeReconfigurationGate): RuntimeReconfigurationPlan {
  if (gate.configurationBusy || gate.settingsLoading || gate.subscriptionsLoading || gate.connectionBusy) {
    return 'reject'
  }
  if (gate.connectionPhase === 'idle') return 'persist-only'
  if (gate.connectionPhase === 'connected') return 'restart-runtime'
  return 'reject'
}

/**
 * A failed replacement start may be rolled back only when the coordinator has
 * authoritative proof that no TUN remains. With an unknown runtime outcome we
 * keep the newly persisted choice visible and lock the UI instead of starting
 * a second VPN or claiming that the old setting is active.
 */
export function reconfigurationRecovery(confirmedNoTun: boolean): RuntimeReconfigurationRecovery {
  return confirmedNoTun ? 'rollback-and-reconnect' : 'keep-new-unknown'
}
