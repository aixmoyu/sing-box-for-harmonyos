import test from 'node:test'
import assert from 'node:assert/strict'
import { applyTrafficPrivacy } from '../../entry/src/main/ets/domain/TrafficPrivacy.ts'
import { prepareLocalConfig } from '../../entry/src/main/ets/domain/LocalConfig.ts'
import { parseSavedUiSettings } from '../../entry/src/main/ets/domain/SavedUiSettings.ts'
const raw=JSON.stringify({inbounds:[{type:'tun',tag:'custom-tun'}],outbounds:[{type:'selector',tag:'proxy',outbounds:['direct']},{type:'direct',tag:'direct'}],route:{final:'proxy',rules:[{network:'udp',outbound:'direct'},{domain_suffix:['example.com'],outbound:'direct'}]}})
test('strict custom-profile STUN rejection precedes broad direct rules and preserves original JSON',()=>{
 const before=JSON.parse(raw), config=JSON.parse(prepareLocalConfig(raw,{ipv6Enabled:true,protectWebRtc:true,strictWebRtc:true}))
 const rejects=config.route.rules.filter((r:any)=>r.protocol==='stun')
 assert.ok(rejects.length>=2);assert.ok(rejects.every((r:any)=>r.action==='reject'&&r.outbound===undefined))
 assert.ok(config.route.rules.findIndex((r:any)=>r.protocol==='stun')<config.route.rules.findIndex((r:any)=>r.network==='udp'&&r.outbound==='direct'))
 assert.ok(!rejects.some((r:any)=>r.clash_mode==='direct'));assert.deepEqual(JSON.parse(raw),before)
})
test('strict mode works without proxy and switching back does not retain managed reject rules',()=>{
 const source=JSON.stringify({inbounds:[{type:'tun',tag:'tun'}],outbounds:[{type:'direct',tag:'direct'}]})
 const strict=applyTrafficPrivacy(source,{ipv6Enabled:true,protectWebRtc:true,strictWebRtc:true})
 assert.ok(JSON.parse(strict).route.rules.some((r:any)=>r.protocol==='stun'&&r.action==='reject'))
 const disabled=JSON.parse(applyTrafficPrivacy(strict,{ipv6Enabled:true,protectWebRtc:false,strictWebRtc:false}))
 assert.ok(!disabled.route.rules.some((r:any)=>r.protocol==='stun'))
 const proxy=JSON.parse(applyTrafficPrivacy(applyTrafficPrivacy(raw,{ipv6Enabled:true,protectWebRtc:true,strictWebRtc:true}),{ipv6Enabled:true,protectWebRtc:true,strictWebRtc:false}))
 assert.ok(proxy.route.rules.filter((r:any)=>r.protocol==='stun').every((r:any)=>r.action==='route'))
})
test('strict mode is idempotent and covers each TUN with configured mode casing',()=>{
 const source=JSON.stringify({...JSON.parse(raw),inbounds:[{type:'tun',tag:'one'},{type:'tun',tag:'two'}],experimental:{clash_api:{default_mode:'Rule'}}})
 const privacy={ipv6Enabled:true,protectWebRtc:true,strictWebRtc:true}
 const once=applyTrafficPrivacy(source,privacy);assert.deepEqual(JSON.parse(applyTrafficPrivacy(once,privacy)),JSON.parse(once))
 for(const r of JSON.parse(once).route.rules.filter((r:any)=>r.protocol==='stun'))assert.deepEqual(r.inbound,['one','two'])
 assert.ok(JSON.parse(once).route.rules.some((r:any)=>r.clash_mode==='Rule'&&r.action==='reject'))
})
test('new strict choice persists without silently changing existing proxy preferences',()=>{
 const old={version:2,visibleCards:[],expandedGroups:[],showSystemApplications:false,logLevel:'warn',protectWebRtc:true}
 assert.equal(parseSavedUiSettings(JSON.stringify(old)).strictWebRtc,false)
 const saved=parseSavedUiSettings(JSON.stringify({...old,strictWebRtc:true}));assert.equal(saved.strictWebRtc,true);assert.equal(saved.protectWebRtc,true)
 assert.throws(()=>parseSavedUiSettings(JSON.stringify({...old,strictWebRtc:'yes'})))
})

test('disable STUN remains effective independently of proxy STUN toggle',()=>{
 const config=JSON.parse(applyTrafficPrivacy(raw,{ipv6Enabled:true,protectWebRtc:false,strictWebRtc:true}))
 assert.ok(config.route.rules.some((r:any)=>r.protocol==='stun'&&r.action==='reject'))
 assert.ok(!config.route.rules.some((r:any)=>r.protocol==='stun'&&r.action==='route'))
})
