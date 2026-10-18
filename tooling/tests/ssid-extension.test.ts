import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { stripTypeScriptTypes } from 'node:module'
import vm from 'node:vm'
import { normalizeSsidPolicy, shouldSuspendSsid } from '../../entry/src/main/ets/domain/SsidPolicy.ts'

// Execute the production Extension methods against simulated OS/core boundaries.
// This checks sequencing and cancellation, not HarmonyOS process retention.
function fixture() {
  let ssid = 'Home'
  const calls: string[] = []
  const policy = { enabled: true, direct: [], proxy: [], fallback: 'keep', excluded: ['Home'] }
  const source = readFileSync(new URL('../../entry/src/main/ets/vpnextension/NetworkVpnExtAbility.ets', import.meta.url), 'utf8')
    .replace(/import[\s\S]*?from '[^']+'\r?\n/g, '')
    .replace('export default class NetworkVpnExtAbility', 'class NetworkVpnExtAbility')
  const context = vm.createContext({
    CoreGateway: class {},
    VpnExtensionAbility: class { context = { filesDir: '/private', cacheDir: '/cache' } },
    normalizeSsidPolicy, shouldSuspendSsid,
    fileIo: { readTextSync: () => JSON.stringify(policy) },
    wifiManager: { isWifiActive: () => !!ssid, ConnState: { CONNECTED: 1 }, getLinkedInfo: async () => ({ connState: 1, ssid }) },
    Date, JSON, setInterval, clearInterval,
    hilog: { error() {}, info() {} }
  })
  const Ext = vm.runInContext(stripTypeScriptTypes(source) + '\nNetworkVpnExtAbility', context)
  const ext = new Ext()
  ext.core = { stop: async () => calls.push('stop-core'), start: async () => calls.push('start-core'), control: async () => calls.push('restore-mode') }
  ext.vpnConnection = { destroy: async () => calls.push('destroy-tun'), protectProcessNet: async () => calls.push('protect'), create: async () => { calls.push('create-tun'); return 42 } }
  ext.coreStarted = true; ext.coreInitialized = true; ext.tunFd = 41
  ext.runtimeState = 'running'; ext.resumeConfig = '{}'; ext.readIpv6Enabled = () => false
  return { ext, calls, roam: (value: string) => { ssid = value; ext.lastSsidCheck = 0 } }
}

test('excluded SSID stops the core before releasing TUN; roaming protects and restores service', async () => {
  const { ext, calls, roam } = fixture()
  await ext.applySsidPolicy('{"mode":"rule"}')
  assert.deepEqual(calls, ['stop-core', 'destroy-tun'])
  assert.equal(ext.suspended, true)
  assert.equal(ext.tunFd, -1)
  assert.equal(JSON.parse(ext.runtimeSnapshotJson).suspended, true)
  roam('Home'); await ext.applySsidPolicy('{}')
  assert.equal(calls.length, 2, 'staying on an excluded SSID must not repeatedly restart')
  roam('Office'); await ext.applySsidPolicy('{}')
  assert.deepEqual(calls.slice(2), ['protect', 'create-tun', 'start-core', 'restore-mode'])
  assert.equal(ext.suspended, false)
  assert.equal(ext.coreStarted, true)
})

test('SSID read failure preserves suspension; manual stop prevents automatic resume', async () => {
  const { ext, calls, roam } = fixture()
  await ext.applySsidPolicy('{}')
  roam('<unknown ssid>'); await ext.applySsidPolicy('{}')
  assert.equal(ext.suspended, true)
  ext.stopRequested = true
  roam('Office'); await ext.applySsidPolicy('{}')
  assert.deepEqual(calls, ['stop-core', 'destroy-tun'])
})

test('a manual stop arriving during resume prevents creating a new TUN', async () => {
  const { ext, calls, roam } = fixture()
  await ext.applySsidPolicy('{}')
  ext.vpnConnection.protectProcessNet = async () => { calls.push('protect'); ext.stopRequested = true }
  roam('Office')
  await assert.rejects(ext.applySsidPolicy('{}'), /cancelled/)
  assert.deepEqual(calls, ['stop-core', 'destroy-tun', 'protect'])
})
