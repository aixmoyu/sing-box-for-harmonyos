import assert from 'node:assert/strict'
import test from 'node:test'
import {
  classifyNodeLatency,
  compareNodeLatency
} from '../../entry/src/main/ets/domain/NodeLatencyQuality.ts'

test('classifies real latency thresholds without calling them bandwidth', () => {
  assert.equal(classifyNodeLatency(undefined), 'untested')
  assert.equal(classifyNodeLatency(-1), 'failed')
  assert.equal(classifyNodeLatency(100), 'fast')
  assert.equal(classifyNodeLatency(101), 'normal')
  assert.equal(classifyNodeLatency(250), 'normal')
  assert.equal(classifyNodeLatency(251), 'slow')
  assert.equal(classifyNodeLatency(600), 'slow')
  assert.equal(classifyNodeLatency(601), 'very_slow')
})

test('sorts successful latency first, then untested, then failures', () => {
  const measured: number[] = [400, -1, 80, 220]
  measured.sort((left: number, right: number) => compareNodeLatency(left, right))
  assert.deepEqual(measured, [80, 220, 400, -1])
  assert.ok(compareNodeLatency(undefined, -1) < 0)
  assert.ok(compareNodeLatency(-1, undefined) > 0)
  assert.equal(compareNodeLatency(undefined, undefined), 0)
  assert.equal(compareNodeLatency(-1, -1), 0)
})
