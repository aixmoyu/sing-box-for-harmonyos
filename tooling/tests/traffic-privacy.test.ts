import test from 'node:test'
import assert from 'node:assert/strict'
import { prepareLocalConfig } from '../../entry/src/main/ets/domain/LocalConfig.ts'
import { applyTrafficPrivacy } from '../../entry/src/main/ets/domain/TrafficPrivacy.ts'
import { defaultSavedUiSettings, parseSavedUiSettings } from '../../entry/src/main/ets/domain/SavedUiSettings.ts'

const source = JSON.stringify({ inbounds: [{ type: 'tun', tag: 'my-tun' }],
 dns: { servers: [{ type: 'https', tag: 'dns', server: '1.1.1.1' }] },
 outbounds: [{ type: 'selector', tag: 'proxy', outbounds: ['node'] }, { type: 'direct', tag: 'node' }],
 route: { final: 'proxy', rules: [{ ip_is_private: true, action: 'route', outbound: 'node' }] } })

test('both IP families are always captured and proxied traffic is left to the node', () => {
 const output = JSON.parse(prepareLocalConfig(source, { ipv6Enabled: false, protectWebRtc: true }))
 assert.deepEqual(output.inbounds[0].address, ['172.19.0.1/30','fdfe:dcba:9876::1/126'])
 assert.equal(output.route.rules.filter((rule: any) => rule.ip_version === 6).length, 0)
 assert.equal(output.dns.strategy, undefined)
 assert.equal(output.route.rules[0].action, 'sniff')
})

test('STUN is sniffed then routed through selected proxy in rule/global modes, never rewritten to direct', () => {
 const output = JSON.parse(prepareLocalConfig(source, { ipv6Enabled: true, protectWebRtc: true }))
 const rules = output.route.rules
 assert.equal(rules[0].action, 'sniff')
 assert.ok(rules[0].sniffer.includes('stun'))
 const index = rules.findIndex((r: any) => r.protocol === 'stun')
 assert.equal(rules[index].outbound, 'proxy')
 assert.deepEqual(rules.filter((r: any) => r.protocol === 'stun').map((r: any) => r.clash_mode), ['global','rule'])
 assert.ok(index < rules.findIndex((r: any) => r.ip_is_private === true))
 assert.equal(output.route.final, 'proxy')
 assert.ok(rules.some((r: any) => r.clash_mode === 'direct' && r.outbound === 'node'), 'explicit direct mode remains usable')
})

test('DNS hijack is limited to captured inbound with configured DNS; minimal direct profiles remain valid', () => {
 const output = JSON.parse(prepareLocalConfig(source, { ipv6Enabled: true, protectWebRtc: true }))
 const dns = output.route.rules.find((r: any) => r.action === 'hijack-dns' && r.inbound)
 assert.equal(dns.port, 53)
 assert.equal(dns.inbound[0], 'my-tun')
 assert.deepEqual(output.dns, JSON.parse(source).dns)
 const minimal = JSON.parse(prepareLocalConfig('{"outbounds":[{"type":"direct","tag":"direct"}]}', { ipv6Enabled: true, protectWebRtc: true }))
 assert.equal(minimal.dns, undefined)
 assert.equal(minimal.route.rules.length, 0)
})

test('privacy adaptation is repeatable and disabling protection removes its managed STUN rule', () => {
 const adapted = prepareLocalConfig(source, { ipv6Enabled: false, protectWebRtc: true })
 assert.deepEqual(JSON.parse(applyTrafficPrivacy(adapted, { ipv6Enabled: false, protectWebRtc: true })), JSON.parse(adapted))
 const relaxed = JSON.parse(applyTrafficPrivacy(adapted, { ipv6Enabled: true, protectWebRtc: false }))
 assert.equal(relaxed.route.rules.filter((r: any) => r.protocol === 'stun').length, 0)
 assert.equal(relaxed.route.rules.filter((r: any) => r.ip_version === 6).length, 0)
 assert.equal(JSON.parse(source).route.rules.length, 1, 'source profile stays unchanged')
})

test('old UI preferences migrate privacy defaults without losing hidden cards and filters', () => {
 const ui = parseSavedUiSettings('{"version":1,"visibleCards":[],"expandedGroups":[],"showSystemApplications":false,"logLevel":"warn"}')
 assert.equal(ui.protectWebRtc, true); assert.equal(ui.ipv6Enabled, false)
 assert.equal(ui.version, 2)
 assert.deepEqual(ui.visibleCards, []); assert.equal(ui.logLevel, 'warn')
})

test('IPv6 is never rejected or stripped on the client, both settings behave the same', () => {
 const off = JSON.parse(prepareLocalConfig(source, { ipv6Enabled: false, protectWebRtc: true }))
 assert.equal(off.dns.strategy, undefined)
 assert.equal(off.route.rules.filter((rule: any) => rule.ip_version === 6).length, 0)
 const on = JSON.parse(prepareLocalConfig(source, { ipv6Enabled: true, protectWebRtc: true }))
 assert.equal(on.dns.strategy, undefined)
 assert.deepEqual(on.route.rules, off.route.rules)
})

test('new default is IPv6 off, but an explicit saved choice still wins', () => {
 assert.equal(defaultSavedUiSettings().ipv6Enabled, false)
 const baseline = { version: 2, visibleCards: [], expandedGroups: [], showSystemApplications: true, logLevel: 'all' }
 assert.equal(parseSavedUiSettings(JSON.stringify(baseline)).ipv6Enabled, false)
 const explicit = parseSavedUiSettings(JSON.stringify({ ...baseline, ipv6Enabled: true, protectWebRtc: false }))
 assert.equal(explicit.ipv6Enabled, true)
 assert.equal(explicit.protectWebRtc, false)
})
