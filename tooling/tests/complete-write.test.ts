import test from 'node:test'
import assert from 'node:assert/strict'
import { writeFully } from '../../entry/src/main/ets/domain/CompleteWrite.ts'

test('short native writes complete the exact UTF-8 envelope before resolving', async () => {
  const input = new TextEncoder().encode(JSON.stringify({ cipher: '密文+'.repeat(10000) }))
  const output: number[] = []
  await writeFully(input, async buffer => {
    const bytes = new Uint8Array(buffer)
    const count = Math.min(bytes.length, 997)
    output.push(...bytes.slice(0, count))
    return count
  })
  assert.deepEqual(new Uint8Array(output), input)
})

test('zero progress, invalid counts and native failures reject before promotion', async () => {
  for (const count of [0, -1, 5, NaN, 1.5]) {
    await assert.rejects(writeFully(new Uint8Array([1, 2]), async () => count), /写入不完整/)
  }
  const failure = new Error('disk full')
  await assert.rejects(writeFully(new Uint8Array([1]), async () => { throw failure }), error => error === failure)
})
