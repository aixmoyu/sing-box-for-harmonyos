import { coreIsPrerelease } from './BuildInfo.ts'
export interface GithubAsset { name: string; browser_download_url: string }
export interface GithubRelease { tag_name: string; name: string; body: string; html_url: string; draft: boolean; prerelease: boolean; assets: GithubAsset[] }
function versionParts(version: string): number[] {
  const match: RegExpMatchArray | null = version.match(/^v?(\d+)\.(\d+)(?:\.(\d+))?(?:-[a-zA-Z0-9.-]+)?$/)
  return match ? [Number(match[1]), Number(match[2]), Number(match[3] || 0)] : []
}
export function newerAppVersion(candidate: string, installed: string): boolean {
  const a: number[] = versionParts(candidate), b: number[] = versionParts(installed)
  if (a.length !== 3 || b.length !== 3) return false
  for (let i: number = 0; i < 3; i++) { if (a[i] !== b[i]) return a[i] > b[i] }
  return false
}
export function selectAppUpdate(releases: GithubRelease[], installed: string, core: string): GithubRelease | null {
  let best: GithubRelease | null = null
  for (const release of releases) {
    if (release.draft || release.prerelease !== coreIsPrerelease(core) || !newerAppVersion(release.tag_name, installed)) continue
    if (!/^https:\/\/github\.com\/being123321\/sing-box-for-harmonyos\/releases\/tag\/[^?#]+$/.test(release.html_url)) continue
    if (!Array.isArray(release.assets) || !release.assets.some((asset: GithubAsset) =>
      /^sing-box-HarmonyOS-.*-unsigned\.hap$/.test(asset.name) && asset.name.includes('-beta-') === coreIsPrerelease(core))) continue
    if (best === null || newerAppVersion(release.tag_name, best.tag_name)) best = release
  }
  return best
}
