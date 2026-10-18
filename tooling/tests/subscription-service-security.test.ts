import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const source = readFileSync(new URL(
  '../../entry/src/main/ets/services/SubscriptionService.ts', import.meta.url), 'utf8')

test('subscription download applies the native 4 MiB transfer limit and an API 22 interceptor redirect budget', () => {
  assert.match(source, /const SUBSCRIPTION_MAX_BYTES: number = 4 \* 1024 \* 1024/)
  assert.match(source, /const SUBSCRIPTION_MAX_REDIRECTS: number = 3/)
  assert.match(source, /maxLimit: SUBSCRIPTION_MAX_BYTES/)
  assert.doesNotMatch(source, /maxRedirects\s*:/)
  assert.match(source, /this\.invocationCount \+= 1/)
  assert.match(source, /this\.invocationCount > this\.maximumInvocations/)
  assert.match(source, /http\.InterceptorType\.REDIRECTION, SUBSCRIPTION_MAX_REDIRECTS/)
  assert.match(source, /redirectGuard\.exceededInvocationLimit\(\)/)
  assert.match(source, /usingCache: false/)
})

test('initial, redirect and final subscription URLs are all fail-closed HTTPS checks', () => {
  assert.match(source, /function isAbsoluteHttpsUrl\(url: string\): boolean/)
  assert.match(source, /new HttpsUrlGuard\(\s*http\.InterceptorType\.REDIRECTION, SUBSCRIPTION_MAX_REDIRECTS\)/)
  assert.match(source, /new HttpsUrlGuard\(http\.InterceptorType\.FINAL_RESPONSE\)/)
  assert.match(source, /guardInstalled = interceptorChain\.addChain\(\[redirectGuard, finalResponseGuard\]\) &&/)
  assert.match(source, /interceptorChain\.apply\(request\)/)
  assert.match(source, /if \(!guardInstalled\)/)
  assert.match(source, /if \(!finalResponseGuard\.observedUrl\(\)\)/)
  assert.match(source, /return false/)
})
