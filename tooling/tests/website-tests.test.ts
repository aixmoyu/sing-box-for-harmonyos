import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import {
  classifyWebsiteProbeErrorCode,
  classifyWebsiteResponse,
  emptyWebsiteTestResults,
  WEBSITE_TEST_TARGETS
} from '../../entry/src/main/ets/domain/WebsiteTests.ts'
import type { WebsiteTestTarget } from '../../entry/src/main/ets/domain/WebsiteTests.ts'

function targetById(id: string): WebsiteTestTarget {
  const target: WebsiteTestTarget | undefined = WEBSITE_TEST_TARGETS.find((item: WebsiteTestTarget) => item.id === id)
  assert.ok(target, `missing website target: ${id}`)
  return target
}

test('Google generate_204 uses GET and only an exact 204 response passes', () => {
  const google: WebsiteTestTarget = targetById('google')
  assert.equal(google.url, 'https://www.google.com/generate_204')
  assert.equal(google.method, 'GET')
  assert.equal(google.successPolicy, 'exact-204')
  assert.equal(classifyWebsiteResponse(google, 204), 'reachable')
  assert.equal(classifyWebsiteResponse(google, 200), 'failed')
  assert.equal(classifyWebsiteResponse(google, 302), 'failed')
  assert.equal(classifyWebsiteResponse(google, 403), 'failed')
})

test('ChatGPT uses GET and only 2xx or 3xx responses count as available', () => {
  const chatgpt: WebsiteTestTarget = targetById('chatgpt')
  assert.equal(chatgpt.method, 'GET')
  assert.equal(chatgpt.preflightUrl, 'https://chatgpt.com/robots.txt')
  assert.equal(classifyWebsiteResponse(chatgpt, 200), 'reachable')
  assert.equal(classifyWebsiteResponse(chatgpt, 302), 'reachable')
  assert.equal(classifyWebsiteResponse(chatgpt, 399), 'reachable')
  assert.equal(classifyWebsiteResponse(chatgpt, 400), 'failed')
  assert.equal(classifyWebsiteResponse(chatgpt, 500), 'failed')
})

test('YouTube uses its lightweight GET generate_204 endpoint', () => {
  const youtube: WebsiteTestTarget = targetById('youtube')
  assert.equal(youtube.url, 'https://www.youtube.com/generate_204')
  assert.equal(youtube.method, 'GET')
  assert.equal(youtube.successPolicy, 'exact-204')
  assert.equal(classifyWebsiteResponse(youtube, 204), 'reachable')
  assert.equal(classifyWebsiteResponse(youtube, 200), 'failed')
})

test('ChatGPT policy and rate-limit responses are reported as reached but unusable', () => {
  const chatgpt: WebsiteTestTarget = targetById('chatgpt')
  assert.equal(classifyWebsiteResponse(chatgpt, 403), 'limited')
  assert.equal(classifyWebsiteResponse(chatgpt, 429), 'limited')
  assert.equal(classifyWebsiteResponse(chatgpt, 451), 'limited')
})

test('ordinary targets no longer treat all 100-499 responses as reachable', () => {
  const github: WebsiteTestTarget = targetById('github')
  assert.equal(classifyWebsiteResponse(github, 100), 'failed')
  assert.equal(classifyWebsiteResponse(github, 199), 'failed')
  assert.equal(classifyWebsiteResponse(github, 200), 'reachable')
  assert.equal(classifyWebsiteResponse(github, 399), 'reachable')
  assert.equal(classifyWebsiteResponse(github, 400), 'failed')
  assert.equal(classifyWebsiteResponse(github, 403), 'failed')
  assert.equal(classifyWebsiteResponse(github, 499), 'failed')
})

test('Claude and Netflix use small GET endpoints instead of unsupported HEAD requests', () => {
  const claude: WebsiteTestTarget = targetById('claude')
  const netflix: WebsiteTestTarget = targetById('netflix')
  assert.equal(claude.url, 'https://claude.ai/robots.txt')
  assert.equal(claude.method, 'GET')
  assert.equal(netflix.url, 'https://www.netflix.com/robots.txt')
  assert.equal(netflix.method, 'GET')
})

test('NetworkKit BusinessError codes map to stable safe categories', () => {
  assert.equal(classifyWebsiteProbeErrorCode(2300005), 'dns')
  assert.equal(classifyWebsiteProbeErrorCode(2300006), 'dns')
  assert.equal(classifyWebsiteProbeErrorCode(2300007), 'tcp')
  assert.equal(classifyWebsiteProbeErrorCode(2300028), 'timeout')
  assert.equal(classifyWebsiteProbeErrorCode(2300058), 'tls')
  assert.equal(classifyWebsiteProbeErrorCode(2300060), 'tls')
  assert.equal(classifyWebsiteProbeErrorCode(2300055), 'io')
  assert.equal(classifyWebsiteProbeErrorCode(2300999), 'io')
  assert.equal(classifyWebsiteProbeErrorCode(2300998), 'unknown')
  assert.equal(classifyWebsiteProbeErrorCode(0), 'unknown')
})

test('empty results include a non-error stable diagnostic envelope', () => {
  for (const result of emptyWebsiteTestResults()) {
    assert.equal(result.preflightResponseCode, 0)
    assert.equal(result.errorCategory, 'none')
    assert.equal(result.errorCode, 0)
  }
})

test('website service uses API 22-compatible HTTP/1.1 probes and never exposes BusinessError.message', () => {
  const source = readFileSync(new URL(
    '../../entry/src/main/ets/services/WebsiteProbeService.ts', import.meta.url), 'utf8')
  assert.match(source, /usingProtocol:\s*http\.HttpProtocol\.HTTP1_1/)
  assert.doesNotMatch(source, /reuseConnections\s*:/)
  assert.match(source, /connectTimeout:\s*WEBSITE_PROBE_TIMEOUT_MS/)
  assert.match(source, /readTimeout:\s*WEBSITE_PROBE_TIMEOUT_MS/)
  assert.match(source, /WEBSITE_PROBE_TIMEOUT_MS:\s*number\s*=\s*15000/)
  assert.match(source, /const businessError:\s*BusinessError/)
  assert.match(source, /classifyWebsiteProbeErrorCode\(errorCode\)/)
  assert.doesNotMatch(source, /businessError\.message|error\.message/)
  assert.match(source, /target\.preflightUrl/)
})
