import { http } from '@kit.NetworkKit'
import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { writeFully } from '../domain/CompleteWrite'
import { HttpsUrlGuard } from './SubscriptionService'

export interface RuleSetUpdate { updatedAt: number; totalBytes: number }

const MAX_BYTES: number = 16 * 1024 * 1024
// Upstream binary rule-sets, the same sources the bundled files come from.
const TARGETS: string[][] = [
  ['cn.srs', 'https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/cn.srs'],
  ['geoip-cn.srs', 'https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/cn.srs'],
  ['gfw.srs', 'https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/gfw.srs']
]

async function downloadRuleSet(url: string): Promise<Uint8Array> {
  const request: http.HttpRequest = http.createHttp()
  try {
    const redirect: HttpsUrlGuard = new HttpsUrlGuard(http.InterceptorType.REDIRECTION, 3)
    const final: HttpsUrlGuard = new HttpsUrlGuard(http.InterceptorType.FINAL_RESPONSE)
    const chain: http.HttpInterceptorChain = new http.HttpInterceptorChain()
    if (!chain.addChain([redirect, final]) || !chain.apply(request)) throw new Error('无法设置下载安全检查')
    const response: http.HttpResponse = await request.request(url, {
      method: http.RequestMethod.GET, expectDataType: http.HttpDataType.ARRAY_BUFFER,
      maxLimit: MAX_BYTES, connectTimeout: 15000, readTimeout: 30000, usingCache: false,
      header: { 'User-Agent': 'sing-box/1.14.4 (HarmonyOS)' }
    })
    if (redirect.rejectedInsecureUrl() || final.rejectedInsecureUrl() || redirect.exceededInvocationLimit() || !final.observedUrl()) {
      throw new Error('规则集下载重定向不符合 HTTPS 要求')
    }
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error(`规则集下载失败：HTTP ${response.responseCode}`)
    }
    const result: Object = response.result
    if (!(result instanceof ArrayBuffer)) throw new Error('规则集下载结果不是二进制数据')
    const bytes: Uint8Array = new Uint8Array(result as ArrayBuffer)
    if (bytes.length < 8 || bytes[0] !== 0x53 || bytes[1] !== 0x52 || bytes[2] !== 0x53) {
      throw new Error('下载内容不是 sing-box 规则集')
    }
    return bytes
  } finally { request.destroy() }
}

/**
 * Refresh the GFW and mainland domain/IP rule-sets used by the base profile.
 * All files are staged first and only renamed after every download validates,
 * so a failed or truncated download keeps the previous rule-sets intact.
 */
let updateInFlight: Promise<RuleSetUpdate> | null = null

export function updateBuiltinRules(context: common.UIAbilityContext): Promise<RuleSetUpdate> {
  if (updateInFlight !== null) return updateInFlight
  updateInFlight = performUpdate(context).finally(() => { updateInFlight = null })
  return updateInFlight
}

async function performUpdate(context: common.UIAbilityContext): Promise<RuleSetUpdate> {
  const directory: string = context.filesDir + '/builtin-rules-v1'
  if (!await fileIo.access(directory)) await fileIo.mkdir(directory, true)
  const staged: string[] = []
  let totalBytes: number = 0
  try {
    for (const target of TARGETS) {
      const name: string = target[0]
      const bytes: Uint8Array = await downloadRuleSet(target[1])
      const candidate: string = directory + '/' + name + '.candidate'
      staged.push(name)
      const file: fileIo.File = await fileIo.open(candidate, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
      try {
        await writeFully(bytes, async (chunk: ArrayBuffer): Promise<number> => await fileIo.write(file.fd, chunk))
        await fileIo.fsync(file.fd)
      } finally { await fileIo.close(file) }
      totalBytes += bytes.length
    }
    for (const name of staged) await fileIo.rename(directory + '/' + name + '.candidate', directory + '/' + name)
  } catch (failure) {
    for (const name of staged) {
      try { await fileIo.unlink(directory + '/' + name + '.candidate') } catch (_) { }
    }
    throw failure
  }
  return { updatedAt: Date.now(), totalBytes: totalBytes }
}
