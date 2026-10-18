import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

interface NamedResource { name: string; value: string }
interface StringResources { string: NamedResource[] }
interface ColorResources { color: NamedResource[] }

function names<T extends { name: string }>(items: T[]): string[] {
  return items.map((item) => item.name).sort()
}

test('English and Chinese string resource sets stay key-complete', () => {
  const appBase = JSON.parse(readFileSync(new URL('../../AppScope/resources/base/element/string.json', import.meta.url), 'utf8')) as StringResources
  const appEnglish = JSON.parse(readFileSync(new URL('../../AppScope/resources/en_US/element/string.json', import.meta.url), 'utf8')) as StringResources
  const entryBase = JSON.parse(readFileSync(new URL('../../entry/src/main/resources/base/element/string.json', import.meta.url), 'utf8')) as StringResources
  const entryEnglish = JSON.parse(readFileSync(new URL('../../entry/src/main/resources/en_US/element/string.json', import.meta.url), 'utf8')) as StringResources
  assert.deepEqual(names(appEnglish.string), names(appBase.string))
  assert.deepEqual(names(entryEnglish.string), names(entryBase.string))
  assert.ok(appEnglish.string.every((item) => item.value.trim().length > 0))
  assert.ok(entryEnglish.string.every((item) => item.value.trim().length > 0))
})

test('dark and light color resources expose the same semantic keys', () => {
  const light = JSON.parse(readFileSync(new URL('../../entry/src/main/resources/base/element/color.json', import.meta.url), 'utf8')) as ColorResources
  const dark = JSON.parse(readFileSync(new URL('../../entry/src/main/resources/dark/element/color.json', import.meta.url), 'utf8')) as ColorResources
  assert.deepEqual(names(dark.color), names(light.color))
  assert.ok(light.color.every((item) => /^#[0-9A-F]{6}$/i.test(item.value)))
  assert.ok(dark.color.every((item) => /^#[0-9A-F]{6}$/i.test(item.value)))
})
