import { http } from '@kit.NetworkKit'
import type { SubscriptionBundle, SubscriptionHeaders } from '../domain/Models.ts'
import { SubscriptionParser } from '../domain/SubscriptionParser.ts'
import { parseSubscriptionHeaders } from '../domain/SubscriptionHeaders.ts'

const SUBSCRIPTION_MAX_BYTES: number = 4 * 1024 * 1024
const SUBSCRIPTION_MAX_REDIRECTS: number = 3

function isAbsoluteHttpsUrl(url: string): boolean {
  return /^https:\/\//i.test(url)
}

/**
 * HttpResponse does not expose the effective URL. API 22's interceptor
 * context does, so every redirect target and the final request URL are
 * checked before downloaded subscription credentials are accepted. Redirect
 * callbacks also provide the fail-closed budget that the API 23 native
 * redirect-count option cannot provide on the API 22 compatibility baseline.
 */
export class HttpsUrlGuard implements http.HttpInterceptor {
  interceptorType: http.InterceptorType
  private sawInvocation: boolean = false
  private rejectedUrl: boolean = false
  private invocationCount: number = 0
  private maximumInvocations: number
  private invocationLimitExceeded: boolean = false

  constructor(interceptorType: http.InterceptorType, maximumInvocations: number = 0) {
    this.interceptorType = interceptorType
    this.maximumInvocations = maximumInvocations
  }

  async interceptorHandle(
    requestContext: http.HttpRequestContext,
    _responseContext: http.HttpResponse
  ): Promise<http.ChainContinue> {
    this.sawInvocation = true
    this.invocationCount += 1
    if (this.maximumInvocations > 0 && this.invocationCount > this.maximumInvocations) {
      this.invocationLimitExceeded = true
      return false
    }
    if (!isAbsoluteHttpsUrl(requestContext.url)) {
      this.rejectedUrl = true
      return false
    }
    return true
  }

  rejectedInsecureUrl(): boolean {
    return this.rejectedUrl
  }

  observedUrl(): boolean {
    return this.sawInvocation
  }

  exceededInvocationLimit(): boolean {
    return this.invocationLimitExceeded
  }
}

export class SubscriptionService {
  private parser: SubscriptionParser = new SubscriptionParser()

  async downloadAndParse(url: string): Promise<SubscriptionBundle> {
    const normalized: string = url.trim()
    if (!isAbsoluteHttpsUrl(normalized)) {
      throw new Error('订阅包含节点凭据，首版只允许 https:// 地址')
    }
    let request: http.HttpRequest | undefined = undefined
    try {
      request = http.createHttp()
      const redirectGuard: HttpsUrlGuard = new HttpsUrlGuard(
        http.InterceptorType.REDIRECTION, SUBSCRIPTION_MAX_REDIRECTS)
      const finalResponseGuard: HttpsUrlGuard = new HttpsUrlGuard(http.InterceptorType.FINAL_RESPONSE)
      const interceptorChain: http.HttpInterceptorChain = new http.HttpInterceptorChain()
      let guardInstalled: boolean = false
      try {
        guardInstalled = interceptorChain.addChain([redirectGuard, finalResponseGuard]) &&
          interceptorChain.apply(request)
      } catch (_) {
        guardInstalled = false
      }
      if (!guardInstalled) {
        throw new Error('无法安装 HTTPS 重定向安全检查，已拒绝下载订阅')
      }
      let response: http.HttpResponse
      try {
        response = await request.request(normalized, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.STRING,
          usingCache: false,
          connectTimeout: 15000,
          readTimeout: 20000,
          maxLimit: SUBSCRIPTION_MAX_BYTES,
          header: {
            'User-Agent': 'HarmonyNetAssistant/0.1'
          }
        })
      } catch (_) {
        if (redirectGuard.exceededInvocationLimit()) {
          throw new Error(`订阅重定向超过 ${SUBSCRIPTION_MAX_REDIRECTS} 次，已拒绝下载`)
        }
        if (redirectGuard.rejectedInsecureUrl() || finalResponseGuard.rejectedInsecureUrl()) {
          throw new Error('订阅重定向试图离开 HTTPS，已拒绝下载')
        }
        throw new Error('订阅下载失败，请检查地址、网络或服务状态')
      }
      if (redirectGuard.rejectedInsecureUrl() || finalResponseGuard.rejectedInsecureUrl()) {
        throw new Error('订阅重定向试图离开 HTTPS，已拒绝下载')
      }
      if (redirectGuard.exceededInvocationLimit()) {
        throw new Error(`订阅重定向超过 ${SUBSCRIPTION_MAX_REDIRECTS} 次，已拒绝下载`)
      }
      if (!finalResponseGuard.observedUrl()) {
        throw new Error('无法确认订阅最终地址仍为 HTTPS，已拒绝下载')
      }
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`订阅服务器返回 HTTP ${response.responseCode}`)
      }
      if (typeof response.result !== 'string') {
        throw new Error('订阅服务器没有返回文本配置')
      }
      if (response.result.length > SUBSCRIPTION_MAX_BYTES) {
        throw new Error('订阅内容超过 4 MiB 安全上限')
      }
      const serializedHeaders: string = JSON.stringify(response.header)
      const headers: SubscriptionHeaders = parseSubscriptionHeaders(serializedHeaders)
      return this.parser.parse(response.result, headers)
    } finally {
      if (request !== undefined) {
        request.destroy()
      }
    }
  }
}
