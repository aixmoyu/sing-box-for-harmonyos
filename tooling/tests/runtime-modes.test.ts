import test from 'node:test'
import assert from 'node:assert/strict'
import { dashboardModes } from '../../entry/src/main/ets/domain/RuntimeModes.ts'
import { prepareLocalConfig } from '../../entry/src/main/ets/domain/LocalConfig.ts'

test('dashboard removes case aliases, puts rule in the middle and retains the active core value', () => {
  assert.deepEqual(dashboardModes(['direct', 'global', 'rule', 'Rule', 'Global'], 'Rule'), ['direct', 'Rule', 'global'])
  assert.deepEqual(dashboardModes(['Global', 'Rule', 'Direct'], 'Global'), ['Direct', 'Rule', 'Global'])
  assert.deepEqual(dashboardModes(['custom', 'rule', 'custom'], 'custom'), ['rule', 'custom'])
})

test('privacy keeps imported nested and default mode casing without adding aliases', () => {
  const input = JSON.stringify({ outbounds: [{ type: 'socks', tag: 'proxy', server: '127.0.0.1', server_port: 1080 }],
    experimental: { clash_api: { default_mode: 'Rule' } },
    route: { final: 'proxy', rules: [{ type: 'logical', mode: 'or', rules: [{ clash_mode: 'Global' }], outbound: 'proxy' }] } })
  const output = JSON.parse(prepareLocalConfig(input, { ipv6Enabled: true, protectWebRtc: true }))
  const stun = output.route.rules.filter((r: any) => r.protocol === 'stun')
  assert.deepEqual(stun.map((r: any) => r.clash_mode), ['Global', 'Rule'])
  assert.ok(stun.every((r: any) => r.outbound === 'proxy'))
  assert.equal(output.route.rules.at(-1).rules[0].clash_mode, 'Global')
})
