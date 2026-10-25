import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { stripTypeScriptTypes } from 'node:module'
import vm from 'node:vm'

test('physical signature ignores VPN and prefers validated Wi-Fi as native binding does', async () => {
  const source = readFileSync(new URL('../../entry/src/main/ets/services/PhysicalNetwork.ts', import.meta.url), 'utf8')
    .replace(/import[^\n]+\n/g, '').replaceAll('export async function', 'async function')
  let wifiAvailable = true
  const caps = (wifi: boolean, vpn: boolean = false) => ({ bearerTypes: [vpn ? 4 : wifi ? 1 : 0], networkCap: vpn ? [12,16] : [12,15,16] })
  const context = vm.createContext({ connection: {
    NetBearType: { BEARER_WIFI:1, BEARER_CELLULAR:0, BEARER_VPN:4 },
    NetCap: { NET_CAPABILITY_INTERNET:12, NET_CAPABILITY_NOT_VPN:15, NET_CAPABILITY_VALIDATED:16 },
    getAllNets: async () => [{netId:1},{netId:2}, ...(wifiAvailable ? [{netId:3}] : [])],
    getNetCapabilities: async ({netId}: {netId:number}) => caps(netId === 3, netId === 1),
    getConnectionProperties: async ({netId}: {netId:number}) => ({interfaceName: netId === 3 ? 'wlan0' : 'rmnet0', linkAddresses:[{address:{address:'192.0.2.1'},prefixLength:24}], dnses:[{address:'1.1.1.1'}]})
  } })
  const signature = vm.runInContext(stripTypeScriptTypes(source) + '\nphysicalNetworkSignature', context)
  assert.equal(JSON.parse(await signature()).id, 3)
  assert.equal(JSON.parse(await signature()).kind, 'wifi')
  const stable = await signature()
  assert.equal(await signature(), stable)
  wifiAvailable = false
  assert.equal(JSON.parse(await signature()).id, 2)
  assert.equal(JSON.parse(await signature()).kind, 'cellular')
})

test('probe DNS comes from validated physical underlay, excludes VPN and handles no DNS',async()=>{
 const source=readFileSync(new URL('../../entry/src/main/ets/services/PhysicalNetwork.ts',import.meta.url),'utf8').replace(/import[^\n]+\n/g,'').replaceAll('export async function','async function')
 let dns=[{address:'2001:db8::53'},{address:'192.0.2.53'}],available=true
 const ctx=vm.createContext({Error,connection:{NetBearType:{BEARER_WIFI:1,BEARER_CELLULAR:0,BEARER_VPN:4},NetCap:{NET_CAPABILITY_INTERNET:12,NET_CAPABILITY_NOT_VPN:15,NET_CAPABILITY_VALIDATED:16},getAllNets:async()=>available?[{netId:1},{netId:2}]:[],getNetCapabilities:async({netId}:any)=>({bearerTypes:[netId===1?4:1],networkCap:netId===1?[12,16]:[12,15,16]}),getConnectionProperties:async({netId}:any)=>{assert.equal(netId,2);return {interfaceName:'wlan0',linkAddresses:[],dnses:dns}}}})
 const get=vm.runInContext(stripTypeScriptTypes(source)+'\nphysicalProbeDns',ctx)
 assert.equal(await get(),'192.0.2.53');dns=[{address:'2001:db8::53'}];assert.equal(await get(),'2001:db8::53')
 dns=[];await assert.rejects(get(),/DNS/);available=false;await assert.rejects(get(),/网络/)
})
