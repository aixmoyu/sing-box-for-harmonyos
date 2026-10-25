import { http } from '@kit.NetworkKit'
import { GithubRelease, selectAppUpdate } from '../domain/AppUpdate'
import { APP_VERSION, CORE_VERSION } from '../domain/BuildInfo'
export async function checkAppUpdate(): Promise<GithubRelease | null> {
  const request: http.HttpRequest = http.createHttp()
  try {
    const response: http.HttpResponse = await request.request('https://api.github.com/repos/being123321/sing-box-for-harmonyos/releases?per_page=100', {
      method: http.RequestMethod.GET, expectDataType: http.HttpDataType.STRING, usingCache: false,
      connectTimeout: 10000, readTimeout: 10000, maxLimit: 1024 * 1024,
      header: { 'Accept': 'application/vnd.github+json', 'User-Agent': 'sing-box-for-harmonyos/' + APP_VERSION }
    })
    if (response.responseCode !== 200 || typeof response.result !== 'string') throw new Error('GitHub 暂时无法访问，请稍后重试')
    const releases: GithubRelease[] = JSON.parse(response.result) as GithubRelease[]
    if (!Array.isArray(releases)) throw new Error('更新信息格式无效')
    return selectAppUpdate(releases, APP_VERSION, CORE_VERSION)
  } finally { request.destroy() }
}
