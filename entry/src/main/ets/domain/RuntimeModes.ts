// Keep the core's exact mode value: imported configurations may use capitals.
export function dashboardModes(modes: string[], current: string): string[] {
  const unique: string[] = []
  for (const value of modes) {
    const key: string = value.toLowerCase()
    const index: number = unique.findIndex((item: string) => item.toLowerCase() === key)
    if (index < 0) unique.push(value)
    else if (value === current) unique[index] = value
  }
  const ordered: string[] = []
  for (const key of ['direct', 'rule', 'global']) {
    const value: string | undefined = unique.find((item: string) => item.toLowerCase() === key)
    if (value) ordered.push(value)
  }
  return [...ordered, ...unique.filter((item: string) => !['direct', 'rule', 'global'].includes(item.toLowerCase()))]
}
