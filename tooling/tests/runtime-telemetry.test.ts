import test from 'node:test'
import assert from 'node:assert/strict'
import { trafficRates, delayColor } from '../../entry/src/main/ets/domain/RuntimeTelemetry.ts'

test('rates use native sample elapsed time, not UI poll time', () => {
  assert.deepEqual(trafficRates({session:'a',at:1000,upload:100,download:200},
    {session:'a',at:3000,upload:1100,download:4200}), {upload:500,download:2000})
})
test('repeated and out-of-order IPC snapshots do not zero the live graph', () => {
  const previous = {session:'a',at:3000,upload:1100,download:4200}
  assert.equal(trafficRates(previous, previous), null)
  assert.equal(trafficRates(previous, {...previous,at:2000}), null)
})
test('new sessions and counter resets do not produce negative or huge speeds', () => {
  const previous = {session:'a',at:3000,upload:1100,download:4200}
  assert.deepEqual(trafficRates(previous,{session:'b',at:4000,upload:5,download:2}), {upload:0,download:0})
  assert.deepEqual(trafficRates(previous,{...previous,at:4000,upload:0}), {upload:0,download:0})
})
test('group latency colors distinguish untested, fast, slow and timeout-range results', () => {
  assert.equal(delayColor(0),'#DADCE2')
  assert.equal(delayColor(600),'#3A8270')
  assert.equal(delayColor(1000),'#B08236')
  assert.equal(delayColor(2500),'#BA4C4C')
})
