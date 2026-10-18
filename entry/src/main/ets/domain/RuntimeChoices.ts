export interface GroupChoice { group: string; outbound: string }
export interface ProfileChoices { profileId: string; mode: string; groups: GroupChoice[] }
export interface ChoicesCatalog { version: number; profiles: ProfileChoices[] }
export interface ChoiceCommand { action: string; group?: string; outbound?: string; mode?: string }

export function emptyChoices(profileId: string): ProfileChoices {
  return { profileId: profileId, mode: '', groups: [] }
}

export function parseChoices(text: string): ChoicesCatalog {
  const value: ChoicesCatalog = JSON.parse(text) as ChoicesCatalog
  if (value.version !== 1 || !Array.isArray(value.profiles) || value.profiles.length > 4096) throw new Error('节点选择记录格式无效，原记录已保留')
  const ids: string[] = []
  for (const profile of value.profiles) {
    if (!profile || typeof profile.profileId !== 'string' || profile.profileId.length === 0 || ids.includes(profile.profileId) ||
      !['', 'rule', 'global', 'direct'].includes(profile.mode) || !Array.isArray(profile.groups) || profile.groups.length > 4096) throw new Error('节点选择记录格式无效，原记录已保留')
    ids.push(profile.profileId)
    const tags: string[] = []
    for (const group of profile.groups) {
      if (!group || typeof group.group !== 'string' || group.group.length === 0 || typeof group.outbound !== 'string' || group.outbound.length === 0 || tags.includes(group.group)) throw new Error('节点选择记录格式无效，原记录已保留')
      tags.push(group.group)
    }
  }
  return value
}

export function recordChoice(previous: ProfileChoices, command: ChoiceCommand): ProfileChoices {
  const next: ProfileChoices = { profileId: previous.profileId, mode: previous.mode, groups: previous.groups.slice() }
  if (command.action === 'mode' && command.mode && ['rule', 'global', 'direct'].includes(command.mode)) next.mode = command.mode
  if (command.action === 'select' && command.group && command.outbound) {
    next.groups = next.groups.filter((item: GroupChoice) => item.group !== command.group)
    next.groups.push({ group: command.group, outbound: command.outbound })
  }
  return next
}

// Only change the derived launch configuration, never the user's JSON file.
// Explicit selector defaults otherwise override remembered choices in this core.
export function applyChoices(text: string, choices: ProfileChoices): string {
  const config: Record<string, Object> = JSON.parse(text) as Record<string, Object>
  const outbounds: Record<string, Object>[] = (config.outbounds || []) as Record<string, Object>[]
  for (const outbound of outbounds) {
    if (outbound.type !== 'selector' || !Array.isArray(outbound.outbounds)) continue
    const choice: GroupChoice | undefined = choices.groups.find((item: GroupChoice) => item.group === outbound.tag)
    if (choice && (outbound.outbounds as string[]).includes(choice.outbound)) outbound.default = choice.outbound
  }
  if (choices.mode) {
    const experimental: Record<string, Object> = (config.experimental || {}) as Record<string, Object>
    const clash: Record<string, Object> = (experimental.clash_api || {}) as Record<string, Object>
    clash.default_mode = choices.mode
    experimental.clash_api = clash; config.experimental = experimental
  }
  return JSON.stringify(config)
}
