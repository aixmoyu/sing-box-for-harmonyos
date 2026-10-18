import { normalizeVpnApplicationScope } from './NetworkSettings.ts'
import type { VpnApplicationScope } from './NetworkSettings.ts'

export function perAppScope(enabled: boolean, bypass: boolean, selected: string[]): VpnApplicationScope {
  // Matches v2rayNG: disabled or an empty selection captures all applications.
  return normalizeVpnApplicationScope({ mode: !enabled || selected.length === 0 ? 'all' : bypass ? 'blocklist' : 'allowlist', trustedApplications: selected })
}

export function invertApplicationSelection(selected: string[], visible: string[]): string[] {
  return [...selected.filter((name: string) => !visible.includes(name)), ...visible.filter((name: string) => !selected.includes(name))]
}
