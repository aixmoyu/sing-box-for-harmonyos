export interface SavedUiSettings { version: number; ipv6Enabled?: boolean; protectWebRtc?: boolean; strictWebRtc?: boolean; visibleCards: string[]; expandedGroups: string[]; showSystemApplications: boolean; logLevel: string }
export const SAVED_UI_SETTINGS_VERSION: number = 2
export function defaultSavedUiSettings(): SavedUiSettings {
  // IPv6 now defaults to off: the plugin keeps capturing ::/0 and rejects IPv6
  // inside the tunnel, so a proxy profile without IPv6 support cannot leak
  // IPv6 past the VPN. Users who really need IPv6 can switch it back on.
  return { version: SAVED_UI_SETTINGS_VERSION, ipv6Enabled: false, protectWebRtc: true, strictWebRtc: false, visibleCards: ['traffic', 'connections', 'mode', 'profiles', 'groups'], expandedGroups: [], showSystemApplications: true, logLevel: 'all' }
}
export function parseSavedUiSettings(text: string): SavedUiSettings {
  if (!text) return defaultSavedUiSettings()
  const value: SavedUiSettings = JSON.parse(text) as SavedUiSettings
  if ((value.version !== 1 && value.version !== SAVED_UI_SETTINGS_VERSION) || !Array.isArray(value.visibleCards) || !Array.isArray(value.expandedGroups) ||
    typeof value.showSystemApplications !== 'boolean' || !['all', 'trace', 'debug', 'info', 'warn', 'error', 'fatal', 'panic'].includes(value.logLevel)) throw new Error('界面设置无法读取，原设置已保留')
  const allowed: string[] = defaultSavedUiSettings().visibleCards
  if (value.visibleCards.some((card: string) => !allowed.includes(card)) || value.expandedGroups.some((tag: string) => typeof tag !== 'string')) throw new Error('界面设置无法读取，原设置已保留')
  if (value.version === 1) {
    // Version 1 predates an explicit privacy choice: it always wrote the old
    // dual-stack default. Migrate once to the new IPv6-off default instead of
    // treating that inherited value as an explicit user decision.
    value.ipv6Enabled = false
    if (value.protectWebRtc === undefined) value.protectWebRtc = true
    value.version = SAVED_UI_SETTINGS_VERSION
  }
  if (value.ipv6Enabled === undefined) value.ipv6Enabled = false
  if (value.protectWebRtc === undefined) value.protectWebRtc = true
  if (value.strictWebRtc === undefined) value.strictWebRtc = false
  if (typeof value.strictWebRtc !== 'boolean') throw new Error('隐私设置无法读取，原设置已保留')
  if (typeof value.ipv6Enabled !== 'boolean' || typeof value.protectWebRtc !== 'boolean') throw new Error('隐私设置无法读取，原设置已保留')
  return value
}
