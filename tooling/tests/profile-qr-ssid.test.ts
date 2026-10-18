import test from 'node:test'
import assert from 'node:assert/strict'
import { parseProfileQr } from '../../entry/src/main/ets/domain/ProfileQr.ts'
import { normalizeSsidPolicy, ssidMode } from '../../entry/src/main/ets/domain/SsidPolicy.ts'

test('SFA remote QR preserves URL credentials/query escaping and fragment name', () => {
 const url = 'https://example.com/config.json?a=1&b=a+b'
 const qr = `sing-box://import-remote-profile?url=${encodeURIComponent(url)}#${encodeURIComponent('家里 + 手机')}`
 assert.deepEqual(parseProfileQr(qr), { name: '家里 + 手机', url, kind: 'remote', content: '' })
})
test('QR imports are data only and malformed/unrelated links do not reach download', () => {
 for (const value of ['https://example.com', 'vless://test', 'sing-box://import-remote-profile?url=javascript%3Aalert(1)', 'sing-box://import-remote-profile?url=%ZZ']) assert.throws(() => parseProfileQr(value))
 assert.equal(parseProfileQr('sing-box://import-remote-profile?url=https%3A%2F%2Fexample.com%2Fp').name,'example.com')
 assert.equal(parseProfileQr('{"outbounds":[]}').kind,'local')
})
test('SSID exact matching, fallback and disabled behavior', () => {
 const p=normalizeSsidPolicy({ enabled:true,direct:[' Home '],proxy:['Office'],fallback:'rule' })
 assert.equal(ssidMode(p,'Home'),'direct'); assert.equal(ssidMode(p,'Office'),'global')
 assert.equal(ssidMode(p,'home'),'rule'); assert.equal(ssidMode(p,''),'rule')
 assert.equal(ssidMode({...p,enabled:false},'Home'),'keep')
})
test('conflicting SSID policies are rejected before persistence', () => {
 assert.throws(() => normalizeSsidPolicy({enabled:true,direct:['Home'],proxy:[' Home '],fallback:'keep'}))
 assert.throws(() => normalizeSsidPolicy({enabled:true,direct:[],proxy:[],fallback:'bad'}))
})
