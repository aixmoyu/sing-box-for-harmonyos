import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { stripTypeScriptTypes } from 'node:module'
import vm from 'node:vm'
import { nextRecoveryAttempt } from '../../entry/src/main/ets/domain/VpnRecoveryPolicy.ts'
import { applyChoices, emptyChoices } from '../../entry/src/main/ets/domain/RuntimeChoices.ts'
import { telemetryInterval } from '../../entry/src/main/ets/domain/RuntimeActivity.ts'

function fixture() {
 let channel = 'owned'
 let nativeRunning = true
 let excluded: boolean | null = false
 const calls: string[] = []
 let started = ''
 const source = readFileSync(new URL('../../entry/src/main/ets/vpnextension/NetworkVpnExtAbility.ets', import.meta.url),'utf8')
  .replace(/import[\s\S]*?from '[^']+'\r?\n/g,'').replace('export default class NetworkVpnExtAbility','class NetworkVpnExtAbility')
 const context = vm.createContext({ CoreGateway: class {}, VpnExtensionAbility: class { context = { filesDir: '/private', cacheDir: '/cache' } },
  VPN_RUNTIME_PROTOCOL_CURRENT: 'v3', Date, JSON, setTimeout, clearTimeout, setInterval, clearInterval, nextRecoveryAttempt, applyChoices, telemetryInterval,
  probeVpnChannel: async () => ({ state: channel, netId: channel === 'owned' ? 17 : -1 }), physicalNetworkSignature: async () => 'stable',
  vpnExtension: { createVpnConnection: () => { calls.push('new-vpn'); return { protectProcessNet: async () => calls.push('protect'),
   create: async () => { calls.push('create'); channel='owned'; return 42 }, destroy: async () => calls.push('destroy') } } },
  hilog: { warn() {}, error() {}, info() {} }
 })
 const Ext = vm.runInContext(stripTypeScriptTypes(source)+'\nNetworkVpnExtAbility',context)
 const ext = new Ext()
 const status = () => ({ running: nativeRunning, version: '1.14.4', uploadBytes: 10, downloadBytes: 20, activeConnections: 0, selectedOutboundTag: 'proxy', snapshotJson: '{"mode":"global"}' })
 ext.core = { getStatus: async () => status(), getStatusLite: async () => status(),
  stop: async () => { calls.push('stop'); nativeRunning=false }, initialize: async () => ({available:true,version:'1.14.4'}), validateConfig: async () => ({valid:true}),
  start: async (_fd: number, config: string) => { calls.push('start'); started=config; nativeRunning=true }, control: async () => calls.push('control') }
 ext.runtimeState='running'; ext.sessionId='session'; ext.coreStarted=true; ext.coreInitialized=true; ext.tunFd=41
 ext.vpnConnection={destroy: async () => calls.push('destroy')}
 ext.runtimeBridge={publishStatus: async () => {}}
 ext.resumeConfig='{"outbounds":[{"type":"selector","tag":"proxy","outbounds":["slow","fast"],"default":"slow"}]}'
 ext.profileId='profile'; ext.choicesStore={load:async () => ({profileId:'profile',mode:'global',groups:[{group:'proxy',outbound:'fast'}]})}
 ext.requestedSsidSuspension=async () => excluded
 ext.readIpv6Enabled=() => true; ext.uiActive=() => false; ext.lastVpnProbeAt=0
 return {ext,calls,started:() => started,setChannel:(s: string)=>{channel=s},setCore:(value: boolean)=>{nativeRunning=value},exclude:(value: boolean|null)=>{excluded=value}}
}

test('confirmed missing VPN rebuilds TUN and core using saved manual node and mode', async () => {
 const {ext,calls,setChannel,started}=fixture();setChannel('absent')
 await ext.checkCoreHealth(); assert.equal(calls.length,0)
 ext.missingVpnSince=Date.now()-4000;ext.lastVpnProbeAt=0
 await ext.checkCoreHealth()
 assert.deepEqual(calls,['stop','destroy','new-vpn','protect','create','start','control'])
 assert.equal(JSON.parse(started()).outbounds[0].default,'fast')
 assert.equal(ext.recoveryReason,'');assert.equal(ext.suspended,false)
})

test('working VPN/core with a slow or unreachable node does not trigger restart', async () => {
 const {ext,calls}=fixture(); await ext.checkCoreHealth()
 assert.deepEqual(calls,[]);assert.equal(ext.ownedVpnId,17)
})

test('unknown system inventory never proves VPN loss', async () => {
 const {ext,calls,setChannel}=fixture();setChannel('unknown');ext.missingVpnSince=Date.now()-10000
 await ext.checkCoreHealth();assert.deepEqual(calls,[]);assert.equal(ext.missingVpnSince,0)
})

test('another VPN is not taken over by automatic recovery', async () => {
 const {ext,calls,setChannel}=fixture();setChannel('foreign')
 await ext.checkCoreHealth();assert.deepEqual(calls,['stop']);assert.equal(ext.stage,'foreign-vpn');assert.equal(ext.runtimeState,'error')
})

test('actual stopped core can be restarted while preserving the saved selector', async () => {
 const {ext,calls,setCore,started}=fixture();setCore(false)
 await ext.checkCoreHealth();assert.ok(calls.includes('start'));assert.equal(JSON.parse(started()).outbounds[0].default,'fast')
})

test('manual stop during recovery wins before creating a new TUN', async () => {
 const {ext,calls,setChannel}=fixture();setChannel('absent');ext.stopRequested=true
 await ext.recoverRuntime('vpn');assert.deepEqual(calls,[])
})

test('SSID exclusion prevents repair from creating any proxy resources', async () => {
 const {ext,calls,exclude}=fixture();exclude(true)
 await ext.recoverRuntime('vpn');assert.deepEqual(calls,['stop','destroy']);assert.equal(ext.suspended,true)
})

test('automatic recovery has bounded retries and backoff instead of a restart loop', async () => {
 const {ext,calls}=fixture();ext.recoveryBudget={windowAt:Date.now(),attempts:3,retryAt:0}
 await ext.recoverRuntime('core');assert.equal(ext.stage,'recovery-limit');assert.ok(!calls.includes('new-vpn'))
 const first=nextRecoveryAttempt({windowAt:0,attempts:0,retryAt:0},1000)!
 assert.equal(first.retryAt,6000)
 assert.equal(nextRecoveryAttempt(first,2000),null)
 const second=nextRecoveryAttempt(first,6000)!
 assert.equal(second.retryAt,21000)
})
