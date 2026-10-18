import test from 'node:test'
import assert from 'node:assert/strict'
import { ConnectionStateMachine } from '../../entry/src/main/ets/domain/ConnectionStateMachine.ts'

test('runs the normal connect and stop lifecycle', () => {
  const machine = new ConnectionStateMachine()
  assert.equal(machine.dispatch('CONNECT'), 'preparing')
  assert.equal(machine.dispatch('PREPARED'), 'authorizing')
  assert.equal(machine.dispatch('AUTHORIZED'), 'connecting')
  assert.equal(machine.dispatch('CONNECTED'), 'connected')
  assert.equal(machine.dispatch('STOP'), 'stopping')
  assert.equal(machine.dispatch('STOPPED'), 'idle')
})

test('recovers after a network change', () => {
  const machine = new ConnectionStateMachine()
  machine.dispatch('CONNECT')
  machine.dispatch('PREPARED')
  machine.dispatch('AUTHORIZED')
  machine.dispatch('CONNECTED')
  assert.equal(machine.dispatch('NETWORK_CHANGED'), 'reconnecting')
  assert.equal(machine.dispatch('CONNECTED'), 'connected')
})

test('records a failure and blocks illegal duplicate actions', () => {
  const machine = new ConnectionStateMachine()
  machine.dispatch('CONNECT')
  assert.equal(machine.dispatch('FAILED', 'core unavailable'), 'error')
  assert.equal(machine.errorReason(), 'core unavailable')
  assert.throws(() => machine.dispatch('CONNECT'), /非法连接状态变更/)
  assert.equal(machine.dispatch('RETRY'), 'preparing')
})

