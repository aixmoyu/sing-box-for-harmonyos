import test from 'node:test'
import assert from 'node:assert/strict'
import { newerAppVersion, selectAppUpdate } from '../../entry/src/main/ets/domain/AppUpdate.ts'
import { coreIsPrerelease } from '../../entry/src/main/ets/domain/BuildInfo.ts'
function release(tag:string,beta=false):any { return {tag_name:tag,draft:false,prerelease:beta,html_url:'https://github.com/being123321/sing-box-for-harmonyos/releases/tag/'+tag,assets:[{name:'sing-box-HarmonyOS-'+tag+(beta?'-beta':'')+'-core-1.14.4-unsigned.hap'}]} }
test('version jump is numeric and ignores malformed versions',()=>{
 assert.equal(newerAppVersion('v0.80','0.2.40'),true)
 assert.equal(newerAppVersion('v0.81-beta','0.80-beta'),true)
 assert.equal(newerAppVersion('v0.80-beta','0.80-beta'),false)
 assert.equal(newerAppVersion('v0.8','0.80'),false)
 assert.equal(newerAppVersion('garbage','0.80'),false)
})
test('channel follows upstream core, stable and beta releases never cross',()=>{
 assert.equal(coreIsPrerelease('1.14.4'),false)
 assert.equal(coreIsPrerelease('1.15.0-alpha.13'),true)
 const rs=[release('v0.99-beta',true),release('v0.81'),release('v0.82')]
 assert.equal(selectAppUpdate(rs,'0.80','1.14.4')?.tag_name,'v0.82')
 assert.equal(selectAppUpdate(rs,'0.80','1.15.0-alpha.13')?.tag_name,'v0.99-beta')
})
test('reject drafts, foreign links, missing packages and wrong package channel',()=>{
 const bad=[{...release('v0.81'),draft:true},{...release('v0.82'),html_url:'https://evil.example/file'}, {...release('v0.83'),assets:[]},{...release('v0.84'),assets:release('v0.84',true).assets}]
 assert.equal(selectAppUpdate(bad,'0.80','1.14.4'),null)
})
