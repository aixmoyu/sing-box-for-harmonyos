import { http } from '@kit.NetworkKit'
import { classifyWebsiteProbeErrorCode, classifyWebsiteResponse } from '../domain/WebsiteTests.ts'
import type { EgressInfo, WebsiteTestResult, WebsiteTestTarget } from '../domain/WebsiteTests.ts'

const WEBSITE_PROBE_TIMEOUT_MS: number = 15000

/**
 * Measures HTTPS reachability through the device's current network route.
 * When the system VPN is connected, this UI-process request is captured by
 * the TUN. A successful HTTP response proves reachability only; it does not
 * claim that a paid account or a streaming catalogue is unlocked.
 */
export class WebsiteProbeService {
  private async requestStatus(url: string, method: http.RequestMethod): Promise<number> {
    const request: http.HttpRequest = http.createHttp()
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: method,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        usingProtocol: http.HttpProtocol.HTTP1_1,
        connectTimeout: WEBSITE_PROBE_TIMEOUT_MS,
        readTimeout: WEBSITE_PROBE_TIMEOUT_MS,
        maxLimit: 64 * 1024,
        header: {
          'User-Agent': 'HarmonyNetAssistant/0.1 ReachabilityCheck',
          'Accept': 'text/plain,text/html;q=0.8,*/*;q=0.5'
        }
      })
      return response.responseCode
    } catch (error) {
      // Preserve the platform BusinessError object so probe() can reduce it to
      // a stable, non-sensitive category and numeric code.
      throw error
    } finally {
      request.destroy()
    }
  }

  async probe(target: WebsiteTestTarget): Promise<WebsiteTestResult> {
    const startedAt: number = Date.now()
    let preflightResponseCode: number = 0
    try {
      if (target.preflightUrl) {
        preflightResponseCode = await this.requestStatus(target.preflightUrl, http.RequestMethod.GET)
      }
      const responseCode: number = await this.requestStatus(target.url,
        target.method === 'GET' ? http.RequestMethod.GET : http.RequestMethod.HEAD)
      return {
        id: target.id,
        state: classifyWebsiteResponse(target, responseCode),
        latencyMs: Math.max(1, Date.now() - startedAt),
        responseCode: responseCode,
        preflightResponseCode: preflightResponseCode,
        errorCategory: 'none',
        errorCode: 0
      }
    } catch (error) {
      const businessError: BusinessError = error as BusinessError
      const errorCode: number = Number.isInteger(businessError.code) ? businessError.code : 0
      return {
        id: target.id,
        state: 'failed',
        latencyMs: Math.max(1, Date.now() - startedAt),
        responseCode: 0,
        preflightResponseCode: preflightResponseCode,
        errorCategory: classifyWebsiteProbeErrorCode(errorCode),
        errorCode: errorCode
      }
    }
  }

  async probeEgress(): Promise<EgressInfo> {
    const request: http.HttpRequest = http.createHttp()
    try {
      const response: http.HttpResponse = await request.request('https://www.cloudflare.com/cdn-cgi/trace', {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        connectTimeout: 8000,
        readTimeout: 8000,
        maxLimit: 32 * 1024,
        header: {
          'User-Agent': 'HarmonyNetAssistant/0.1 EgressCheck'
        }
      })
      if (response.responseCode < 200 || response.responseCode >= 300 || typeof response.result !== 'string') {
        throw new Error(`出口检测返回 HTTP ${response.responseCode}`)
      }
      let ip: string = ''
      let countryCode: string = ''
      let dataCenter: string = ''
      const lines: string[] = response.result.split('\n')
      for (let index: number = 0; index < lines.length; index++) {
        const separator: number = lines[index].indexOf('=')
        if (separator <= 0) continue
        const key: string = lines[index].slice(0, separator)
        const value: string = lines[index].slice(separator + 1).trim()
        if (key === 'ip') ip = value
        if (key === 'loc') countryCode = value
        if (key === 'colo') dataCenter = value
      }
      if (ip.length === 0) throw new Error('出口检测未返回 IP')
      return { ip: ip, countryCode: countryCode, dataCenter: dataCenter, checkedAtMillis: Date.now() }
    } catch (_) {
      throw new Error('出口 IP 检测失败，请稍后重试')
    } finally {
      request.destroy()
    }
  }
}
