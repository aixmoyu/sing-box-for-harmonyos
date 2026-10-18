import test from 'node:test'
import assert from 'node:assert/strict'
import { emptySfaCatalog, saveSfaProfile, deleteSfaProfile, parseSfaCatalog, validateSfaContent } from '../../entry/src/main/ets/domain/SfaProfiles.ts'
import { prepareLocalConfig } from '../../entry/src/main/ets/domain/LocalConfig.ts'

const raw = '{\n  "outbounds": [{"type":"direct", "tag":"直连"}], "route": {"final":"直连"}\n}'
const profile = { id: 'a', name: '原始配置', kind: 'local', url: '', content: raw, updatedAt: 1 }

test('SFA profiles retain the original raw JSON verbatim and do not convert routes or outbounds', () => {
  const original = emptySfaCatalog()
  const saved = saveSfaProfile(original, profile)
  assert.equal(original.profiles.length, 0)
  assert.equal(saved.profiles[0].content, raw)
  assert.equal(parseSfaCatalog(JSON.stringify(saved)).profiles[0].content, raw)
})

test('updating a profile preserves its ID, position and selected profile', () => {
  let catalog = saveSfaProfile(emptySfaCatalog(), profile)
  catalog = saveSfaProfile(catalog, { ...profile, id: 'b', name: 'second' })
  const updated = saveSfaProfile(catalog, { ...profile, updatedAt: 4 })
  assert.deepEqual(updated.profiles.map(p => p.id), ['a', 'b'])
  assert.equal(updated.selectedId, 'a')
})

test('deleting the selected profile chooses a remaining real profile or clears selection', () => {
  let catalog = saveSfaProfile(emptySfaCatalog(), profile)
  catalog = saveSfaProfile(catalog, { ...profile, id: 'b' })
  catalog = deleteSfaProfile(catalog, 'a')
  assert.equal(catalog.selectedId, 'b')
  assert.equal(deleteSfaProfile(catalog, 'b').selectedId, '')
})

test('duplicate IDs, orphaned selection, non-HTTPS remote profiles and corrupt JSON are rejected', () => {
  assert.throws(() => parseSfaCatalog(JSON.stringify({ version: 1, selectedId: 'a', profiles: [profile, profile] })))
  assert.throws(() => parseSfaCatalog(JSON.stringify({ version: 1, selectedId: 'missing', profiles: [profile] })))
  assert.throws(() => saveSfaProfile(emptySfaCatalog(), { ...profile, kind: 'remote', url: 'http://unsafe.test/profile' }))
  assert.throws(() => validateSfaContent('{ broken'))
})

test('minimal sing-box profiles do not require fabricated DNS or routing rules', () => {
  const minimal = '{"outbounds":[{"type":"direct","tag":"direct"}]}'
  const runtime = JSON.parse(prepareLocalConfig(minimal))
  assert.equal(runtime.outbounds[0].type, 'direct')
  assert.equal(runtime.dns, undefined)
  assert.equal(runtime.route.auto_detect_interface, false)
  assert.equal(runtime.inbounds[0].type, 'tun')
})

test('existing case-sensitive mode rules remain authoritative and adaptation is idempotent', () => {
  const input = { outbounds: [{ type: 'selector', tag: 'proxy', outbounds: ['direct'] }, { type: 'direct', tag: 'direct' }],
    route: { final: 'proxy', rules: [{ clash_mode: 'Direct', outbound: 'direct' }, { clash_mode: 'Global', outbound: 'proxy' }] } }
  const output = prepareLocalConfig(JSON.stringify(input))
  assert.deepEqual(JSON.parse(output).route.rules, input.route.rules)
  assert.deepEqual(JSON.parse(prepareLocalConfig(output)), JSON.parse(output))
})

test('generated direct outbound avoids an imported tag collision', () => {
  const output = JSON.parse(prepareLocalConfig(JSON.stringify({ outbounds: [{ type: 'socks', tag: 'harmony-direct', server: '127.0.0.1', server_port: 1080 }] })))
  assert.equal(output.outbounds[1].tag, 'harmony-direct-1')
  assert.equal(output.route.rules.find((rule: { clash_mode?: string; outbound?: string }) => rule.clash_mode === 'global' && rule.outbound).outbound, 'harmony-direct')
})

test('TUN adaptation preserves selector members, DNS, routing and cache settings', () => {
  const input = { dns: { servers: [{ type: 'local', tag: 'dns' }] }, route: { final: 'selection', rules: [{ domain: ['example.com'], outbound: 'direct' }] },
    outbounds: [{ type: 'selector', tag: 'selection', outbounds: ['direct'] }, { type: 'direct', tag: 'direct' }],
    experimental: { cache_file: { enabled: true } } }
  const output = JSON.parse(prepareLocalConfig(JSON.stringify(input)))
  assert.deepEqual(output.dns, input.dns)
  assert.deepEqual(output.outbounds, input.outbounds)
  assert.deepEqual(output.route.rules.slice(4), input.route.rules)
  assert.equal(output.route.rules.find((r: { clash_mode?: string; outbound?: string }) => r.clash_mode === 'direct' && r.outbound)?.outbound, 'direct')
  assert.equal(output.route.rules.find((r: { clash_mode?: string; outbound?: string }) => r.clash_mode === 'global' && r.outbound)?.outbound, 'selection')
  assert.deepEqual(output.experimental, input.experimental)
})
