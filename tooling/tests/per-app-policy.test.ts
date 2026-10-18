import test from 'node:test'
import assert from 'node:assert/strict'
import { perAppScope, invertApplicationSelection } from '../../entry/src/main/ets/domain/PerAppPolicy.ts'

test('v2rayNG modes: disabled/empty capture all, selected allow, bypass excluded', () => {
  const selected = ['com.example.browser']
  assert.equal(perAppScope(false, false, selected).mode, 'all')
  assert.equal(perAppScope(true, false, []).mode, 'all')
  assert.equal(perAppScope(true, true, []).mode, 'all')
  assert.deepEqual(perAppScope(true, false, selected), { mode: 'allowlist', trustedApplications: selected })
  assert.deepEqual(perAppScope(true, true, selected), { mode: 'blocklist', trustedApplications: selected })
})

test('inversion affects visible apps and retains hidden selections', () => {
  assert.deepEqual(invertApplicationSelection(['com.hidden.app','com.selected.app'], ['com.selected.app','com.new.app']), ['com.hidden.app','com.new.app'])
})
