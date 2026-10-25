import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'
import { stripTypeScriptTypes } from 'node:module'
import { createCipheriv,createDecipheriv,randomBytes } from 'node:crypto'
const canonical='com.harmonynet.assistant.secure-files.v1', beta='com.harmonynet.assistant.beta.secure-files.v1'
function fixture(){
 const keys=new Map<string,Buffer>(), sessions=new Map<number,any>();let next=0,generated=0;const aliases:string[]=[]
 const tag=new Proxy({},{get:(_t,k)=>String(k)})
 const prop=(o:any,n:string)=>o.properties.find((p:any)=>p.tag===n)?.value
 const huks:any={HuksTag:tag,HuksKeyAlg:{HUKS_ALG_AES:20},HuksKeySize:{HUKS_AES_KEY_SIZE_256:256},HuksKeyPurpose:{HUKS_KEY_PURPOSE_ENCRYPT:1,HUKS_KEY_PURPOSE_DECRYPT:2},HuksKeyPadding:{HUKS_PADDING_NONE:0},HuksCipherMode:{HUKS_MODE_GCM:32},
  hasKeyItem:async(alias:string)=>keys.has(alias),generateKeyItem:async(alias:string)=>{keys.set(alias,randomBytes(32));generated++},
  initSession:async(alias:string,o:any)=>{const encrypt=prop(o,'HUKS_TAG_PURPOSE')===1;const key=keys.get(alias)!;const nonce=prop(o,'HUKS_TAG_NONCE');const c:any=encrypt?createCipheriv('aes-256-gcm',key,nonce):createDecipheriv('aes-256-gcm',key,nonce);c.setAAD(prop(o,'HUKS_TAG_ASSOCIATED_DATA'));if(!encrypt)c.setAuthTag(prop(o,'HUKS_TAG_AE_TAG'));sessions.set(++next,{c,encrypt});aliases.push(alias);return {handle:next}},
  updateSession:async(id:number,o:any)=>({outData:Uint8Array.from(sessions.get(id).c.update(o.inData))}),
  finishSession:async(id:number,o:any)=>{const s=sessions.get(id);const bytes=Buffer.concat([s.c.update(o.inData),s.c.final(),...(s.encrypt?[s.c.getAuthTag()]:[])]);sessions.delete(id);return {outData:Uint8Array.from(bytes)}},abortSession:async(id:number)=>{sessions.delete(id)}}
 const util={Base64Helper:class{encodeToStringSync(b:any){return Buffer.from(b).toString('base64')}decodeSync(s:string){return Uint8Array.from(Buffer.from(s,'base64'))}},TextEncoder:class{static create(){return new this()}encodeInto(s:string){return new TextEncoder().encode(s)}},TextDecoder:{create:()=>({decodeToString:(b:any)=>new TextDecoder('utf-8',{fatal:true}).decode(b)})}}
 const cs=fs.readFileSync(new URL('../../entry/src/main/ets/services/SecureCipher.ts',import.meta.url),'utf8').replace(/import[^\n]+\n/g,'').replace(/export /g,'')
 const Cipher=vm.runInNewContext(stripTypeScriptTypes(cs)+'\nSecureCipher',{util,huks,cryptoFramework:{createRandom:()=>({generateRandom:async(n:number)=>({data:Uint8Array.from(randomBytes(n))})})},Uint8Array,Error})
 let envelope='';const io:any={readText:async()=>envelope}
 const ss=fs.readFileSync(new URL('../../entry/src/main/ets/services/SecureFileStore.ts',import.meta.url),'utf8').replace(/import[^\n]+\n/g,'').replace(/export /g,'')
 const Store=vm.runInNewContext(stripTypeScriptTypes(ss)+'\nSecureFileStore',{SecureCipher:Cipher,fileIo:io,Error,util})
 return {Cipher,Store,keys,aliases,generated:()=>generated,setEnvelope:(s:string)=>{envelope=s},cipher:(alias:string,prefix:string)=>new Cipher(alias,prefix+'|secure-file|v1|sfa-profiles-v1'),store:()=>new Store('/secure','/legacy','sfa-profiles-v1',4096,(s:string)=>JSON.parse(s))}
}
test('original Beta0.2.36 alias+AAD is read with unchanged hardware-key identity',async()=>{
 const f=fixture(), c=f.cipher(canonical,'com.harmonynet.assistant'),plain='{"profiles":["synthetic"]}'
 f.setEnvelope(await c.encrypt(plain));const before=f.generated();assert.equal(await f.store().loadEncryptedFile('/secure'),plain);assert.equal(f.generated(),before)
})
test('Beta0.2.38/39 renamed pair remains authenticated and no key is created while reading',async()=>{
 const f=fixture(),c=f.cipher(beta,'com.harmonynet.assistant.beta'),plain='{"profiles":["beta"]}'
 f.setEnvelope(await c.encrypt(plain));const before=f.generated();assert.equal(await f.store().loadEncryptedFile('/secure'),plain);assert.equal(f.generated(),before);assert.equal(f.keys.has(canonical),false)
})
test('both historical keys can coexist; a corrupted envelope is never accepted',async()=>{
 const f=fixture();await f.cipher(canonical,'com.harmonynet.assistant').encrypt('{}');const e=JSON.parse(await f.cipher(beta,'com.harmonynet.assistant.beta').encrypt('{}'))
 const bytes=Buffer.from(e.authTagBase64,'base64');bytes[0]^=1;e.authTagBase64=bytes.toString('base64');f.setEnvelope(JSON.stringify(e));const before=f.generated();await assert.rejects(f.store().loadEncryptedFile('/secure'));assert.equal(f.generated(),before)
})
test('business validation failures cannot trigger alternate-key or plaintext recovery',async()=>{
 const f=fixture();f.setEnvelope(await f.cipher(canonical,'com.harmonynet.assistant').encrypt('not-json'));const count=f.aliases.length;await assert.rejects(f.store().loadEncryptedFile('/secure'));assert.deepEqual(f.aliases.slice(count),[canonical])
})
test('reading with no historical key does not generate replacement material',async()=>{
 const f=fixture();await assert.rejects(f.cipher(canonical,'com.harmonynet.assistant').decrypt('{}'));assert.equal(f.generated(),0)
})
test('canonical cipher round trips chunk boundaries against independent AES-GCM',async()=>{
 const f=fixture(),c=f.cipher(canonical,'com.harmonynet.assistant');for(const n of [0,15,32768,32769,65537]){const plain='x'.repeat(n);assert.equal(await c.decrypt(await c.encrypt(plain)),plain)}
})
