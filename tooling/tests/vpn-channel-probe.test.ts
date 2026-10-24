import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { stripTypeScriptTypes } from 'node:module'
import vm from 'node:vm'

function fixture() {
 let nets: number[] = [17]
 let fail = false
 let ownAddress = true
 const source = readFileSync(new URL('../../entry/src/main/ets/services/VpnChannelProbe.ts',import.meta.url),'utf8')
  .replace(/import[^\n]+\r?\n/g,'').replace(/export /g,'')
 const ctx = vm.createContext({connection:{NetBearType:{BEARER_VPN:4},getAllNets:async()=>nets.map(netId=>({netId})),
  getNetCapabilities:async()=>{if(fail)throw new Error('inventory failed');return{bearerTypes:[4]}},
  getConnectionProperties:async()=>({linkAddresses:[{address:{address:ownAddress?'172.19.0.1':'10.8.0.1'}}]})}})
 const probe = vm.runInContext(stripTypeScriptTypes(source)+'\nprobeVpnChannel',ctx)
 return{probe,setNets:(value:number[])=>{nets=value},setFail:()=>{fail=true},foreign:()=>{ownAddress=false}}
}

test('VPN channel probe matches the owned net ID and TUN address, never a different known ID',async()=>{
 const{probe}=fixture()
 assert.equal((await probe(17)).state,'owned')
 assert.equal((await probe(18)).state,'foreign')
 assert.equal((await probe(-2)).state,'foreign','recovery gap cannot rediscover another tunnel')
})

test('incomplete inventory and simultaneous VPNs are unknown rather than proof of loss',async()=>{
 const{probe,setNets,setFail}=fixture();setNets([17,18])
 assert.equal((await probe(17)).state,'unknown')
 setFail();assert.equal((await probe(17)).state,'unknown')
})

test('complete empty inventory proves absence; foreign address cannot be adopted',async()=>{
 const{probe,setNets,foreign}=fixture();setNets([])
 assert.equal((await probe(17)).state,'absent')
 setNets([17]);foreign();assert.equal((await probe(-1)).state,'foreign')
})
