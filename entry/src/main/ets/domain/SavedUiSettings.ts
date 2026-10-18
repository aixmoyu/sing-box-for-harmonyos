export interface SavedUiSettings { version: number; visibleCards: string[]; expandedGroups: string[]; showSystemApplications: boolean; logLevel: string }
export function defaultSavedUiSettings(): SavedUiSettings {
  return { version: 1, visibleCards: ['traffic', 'connections', 'mode', 'profiles', 'groups'], expandedGroups: [], showSystemApplications: true, logLevel: 'all' }
}
export function parseSavedUiSettings(text: string): SavedUiSettings {
  if (!text) return defaultSavedUiSettings()
  const value: SavedUiSettings = JSON.parse(text) as SavedUiSettings
  if (value.version !== 1 || !Array.isArray(value.visibleCards) || !Array.isArray(value.expandedGroups) ||
    typeof value.showSystemApplications !== 'boolean' || !['all', 'trace', 'debug', 'info', 'warn', 'error', 'fatal', 'panic'].includes(value.logLevel)) throw new Error('界面设置无法读取，原设置已保留')
  const allowed: string[] = defaultSavedUiSettings().visibleCards
  if (value.visibleCards.some((card: string) => !allowed.includes(card)) || value.expandedGroups.some((tag: string) => typeof tag !== 'string')) throw new Error('界面设置无法读取，原设置已保留')
  return value
}
