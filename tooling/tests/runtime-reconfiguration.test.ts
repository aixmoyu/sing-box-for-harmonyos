import assert from 'node:assert/strict'
import test from 'node:test'
import {
  planRuntimeReconfiguration,
  reconfigurationRecovery
} from '../../entry/src/main/ets/domain/RuntimeReconfiguration.ts'
import type { RuntimeReconfigurationGate } from '../../entry/src/main/ets/domain/RuntimeReconfiguration.ts'

function gate(connectionPhase: string): RuntimeReconfigurationGate {
  return {
    configurationBusy: false,
    settingsLoading: false,
    subscriptionsLoading: false,
    connectionBusy: false,
    connectionPhase: connectionPhase
  }
}

test('runtime-affecting settings persist directly while idle and restart while connected', () => {
  assert.equal(planRuntimeReconfiguration(gate('idle')), 'persist-only')
  assert.equal(planRuntimeReconfiguration(gate('connected')), 'restart-runtime')
})

test('runtime-affecting settings remain locked during races and unknown states', () => {
  const busy: RuntimeReconfigurationGate = gate('connected')
  busy.configurationBusy = true
  assert.equal(planRuntimeReconfiguration(busy), 'reject')

  const stopping: RuntimeReconfigurationGate = gate('stopping')
  stopping.connectionBusy = true
  assert.equal(planRuntimeReconfiguration(stopping), 'reject')
  assert.equal(planRuntimeReconfiguration(gate('unknown')), 'reject')
  assert.equal(planRuntimeReconfiguration(gate('error')), 'reject')
})

test('replacement failure rolls back only after authoritative no-TUN proof', () => {
  assert.equal(reconfigurationRecovery(true), 'rollback-and-reconnect')
  assert.equal(reconfigurationRecovery(false), 'keep-new-unknown')
})
