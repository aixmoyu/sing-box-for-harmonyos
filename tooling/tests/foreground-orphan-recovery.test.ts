import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { stripTypeScriptTypes } from 'node:module'
import vm from 'node:vm'
import { isStaleCurrentRuntimeSession, isRuntimeStatusFresh } from '../../entry/src/main/ets/services/VpnRuntimeProtocol.ts'

function fixture(){
 let absent=true;let command:any=null;let stopped=0
 const status:any={protocolGeneration:'v3',revision:5,sessionId:'old',state:'running',stage:'running',updatedAt:Date.now()-40000,version:'1.14.4',error:'',uploadBytes:1,downloadBytes:2,activeConnections:0,selectedOutboundTag:'proxy'}
 const source=readFileSync(new URL('../../entry/src/main/ets/services/ConnectionCoordinator.ts',import.meta.url),'utf8').replace(/import[\s\S]*?from '[^']+'\r?\n/g,'').replace(/export /g,'')
 const ctx=vm.createContext({Date,isStaleCurrentRuntimeSession,isRuntimeStatusFresh,waitForSystemVpnBearerAbsent:async()=>absent})
 const C=vm.runInContext(stripTypeScriptTypes(source)+'\nConnectionCoordinator',ctx)
 const coordinator=Object.create(C.prototype)
 coordinator.disconnectTask=null;coordinator.activeSessionId='old';coordinator.recoverActiveSession=async()=>{}
 coordinator.runtimeBridge={loadStatus:async()=>status,loadCommand:async()=>command}
 coordinator.configStore={loadProfileId:async()=>'profile'}
 coordinator.disconnect=async()=>{stopped++}
 return{coordinator,status,setPresent:()=>{absent=false},setStop:()=>{command={type:'stop'}},stops:()=>stopped}
}

test('foreground recovery requires stale matching session and proved missing VPN',async()=>{
 const{coordinator,stops}=fixture()
 assert.equal(await coordinator.recoverOrphanedSession('profile'),true)
 assert.equal(stops(),1)
})

test('live VPN, short heartbeat delays, manual stop and changed profile prevent orphan restart',async()=>{
 const live=fixture();live.setPresent();assert.equal(await live.coordinator.recoverOrphanedSession('profile'),false)
 const delay=fixture();delay.status.updatedAt=Date.now()-12000;assert.equal(await delay.coordinator.recoverOrphanedSession('profile'),false)
 const stop=fixture();stop.setStop();assert.equal(await stop.coordinator.recoverOrphanedSession('profile'),false)
 const profile=fixture();assert.equal(await profile.coordinator.recoverOrphanedSession('different'),false)
 assert.equal(live.stops()+delay.stops()+stop.stops()+profile.stops(),0)
})
