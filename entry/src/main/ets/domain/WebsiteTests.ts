export type WebsiteTestState = 'idle' | 'testing' | 'reachable' | 'limited' | 'failed'
export type WebsiteTestMethod = 'GET' | 'HEAD'
export type WebsiteSuccessPolicy = 'http-2xx-3xx' | 'exact-204'
export type WebsiteProbeErrorCategory = 'none' | 'dns' | 'tcp' | 'timeout' | 'tls' | 'io' | 'unknown'

export interface WebsiteTestTarget {
  id: string
  name: string
  url: string
  method: WebsiteTestMethod
  successPolicy: WebsiteSuccessPolicy
  preflightUrl?: string
}

export interface WebsiteTestResult {
  id: string
  state: WebsiteTestState
  latencyMs: number
  responseCode: number
  preflightResponseCode: number
  errorCategory: WebsiteProbeErrorCategory
  errorCode: number
}

export interface EgressInfo {
  ip: string
  countryCode: string
  dataCenter: string
  checkedAtMillis: number
}

export function emptyEgressInfo(): EgressInfo {
  return { ip: '', countryCode: '', dataCenter: '', checkedAtMillis: 0 }
}

/**
 * Converts an HTTP status into an intentionally strict diagnostic result.
 * A response is not automatically usable merely because the remote endpoint
 * returned a 4xx status. Google generate_204 is even stricter: only the
 * expected 204 response passes. ChatGPT's common policy/rate-limit responses
 * are retained as a separate, non-success state so the UI can explain that
 * the endpoint answered while the page is still unavailable.
 */
export function classifyWebsiteResponse(target: WebsiteTestTarget, responseCode: number): WebsiteTestState {
  if (target.successPolicy === 'exact-204') {
    return responseCode === 204 ? 'reachable' : 'failed'
  }
  if (responseCode >= 200 && responseCode < 400) {
    return 'reachable'
  }
  if (target.id === 'chatgpt' &&
    (responseCode === 403 || responseCode === 429 || responseCode === 451)) {
    return 'limited'
  }
  return 'failed'
}

/**
 * Converts NetworkKit BusinessError codes into a small, stable diagnostic
 * vocabulary. The caller must never surface BusinessError.message: it may
 * contain the requested host name or lower-level implementation details.
 */
export function classifyWebsiteProbeErrorCode(errorCode: number): WebsiteProbeErrorCategory {
  if (errorCode === 2300005 || errorCode === 2300006) return 'dns'
  if (errorCode === 2300007) return 'tcp'
  if (errorCode === 2300028) return 'timeout'
  if (errorCode === 2300058 || errorCode === 2300059 ||
    errorCode === 2300060 || errorCode === 2300077) return 'tls'
  if (errorCode === 2300008 || errorCode === 2300009 || errorCode === 2300018 ||
    errorCode === 2300023 || errorCode === 2300025 || errorCode === 2300026 ||
    errorCode === 2300027 || errorCode === 2300052 || errorCode === 2300055 ||
    errorCode === 2300056 || errorCode === 2300061 || errorCode === 2300063 ||
    errorCode === 2300070 || errorCode === 2300073 || errorCode === 2300078 ||
    errorCode === 2300094 || errorCode === 2300999) return 'io'
  return 'unknown'
}

export const WEBSITE_TEST_TARGETS: WebsiteTestTarget[] = [
  { id: 'apple', name: 'Apple', url: 'https://www.apple.com/library/test/success.html', method: 'HEAD', successPolicy: 'http-2xx-3xx' },
  { id: 'github', name: 'GitHub', url: 'https://github.com/', method: 'HEAD', successPolicy: 'http-2xx-3xx' },
  { id: 'google', name: 'Google', url: 'https://www.google.com/generate_204', method: 'GET', successPolicy: 'exact-204' },
  { id: 'youtube', name: 'YouTube', url: 'https://www.youtube.com/generate_204', method: 'GET', successPolicy: 'exact-204' },
  { id: 'chatgpt', name: 'ChatGPT', url: 'https://chatgpt.com/', method: 'GET', successPolicy: 'http-2xx-3xx',
    preflightUrl: 'https://chatgpt.com/robots.txt' },
  { id: 'claude', name: 'Claude', url: 'https://claude.ai/robots.txt', method: 'GET', successPolicy: 'http-2xx-3xx' },
  { id: 'netflix', name: 'Netflix', url: 'https://www.netflix.com/robots.txt', method: 'GET', successPolicy: 'http-2xx-3xx' },
  { id: 'disney', name: 'Disney+', url: 'https://www.disneyplus.com/', method: 'HEAD', successPolicy: 'http-2xx-3xx' },
  { id: 'tiktok', name: 'TikTok', url: 'https://www.tiktok.com/', method: 'HEAD', successPolicy: 'http-2xx-3xx' }
]

export function emptyWebsiteTestResults(): WebsiteTestResult[] {
  return WEBSITE_TEST_TARGETS.map((target: WebsiteTestTarget) => ({
    id: target.id,
    state: 'idle',
    latencyMs: 0,
    responseCode: 0,
    preflightResponseCode: 0,
    errorCategory: 'none',
    errorCode: 0
  }))
}
