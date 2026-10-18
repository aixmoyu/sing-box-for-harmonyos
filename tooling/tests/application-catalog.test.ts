import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { stripTypeScriptTypes } from 'node:module'
import vm from 'node:vm'
import { HARMONY_NET_BUNDLE_NAME, validateApplicationBundleName } from '../../entry/src/main/ets/domain/NetworkSettings.ts'

function catalogFixture(granted: boolean) {
  let reads = 0
  const source = readFileSync(new URL('../../entry/src/main/ets/services/ApplicationCatalogService.ts', import.meta.url), 'utf8')
    .replace(/import[^\n]+\r?\n/g, '').replace('export class ApplicationCatalogService', 'class ApplicationCatalogService')
  const context = vm.createContext({
    HARMONY_NET_BUNDLE_NAME, validateApplicationBundleName,
    bundleManager: { BundleFlag: { GET_BUNDLE_INFO_WITH_APPLICATION: 1 }, getBundleInfoForSelf: async () => ({ appInfo: { accessTokenId: 1 } }) },
    abilityAccessCtrl: { GrantStatus: { PERMISSION_GRANTED: 0 }, createAtManager: () => ({ checkAccessTokenSync: () => granted ? 0 : -1 }) },
    bundle: { BundleFlag: { GET_BUNDLE_DEFAULT: 0 }, getAllApplicationInfo: async () => {
      reads++
      return ['com.example.b', HARMONY_NET_BUNDLE_NAME, 'invalid', 'com.example.a','com.example.a'].map(name => ({ name, label: '$string:label', labelId: '123', iconId: '456', moduleInfos: [{moduleName:'entry'}], systemApp: name.endsWith('.b') }))
    } }
  })
  const Service = vm.runInContext(stripTypeScriptTypes(source) + '\nApplicationCatalogService', context)
  return { service: new Service(), reads: () => reads }
}

test('missing signing ACL returns an explicit permission state and never claims a scan', async () => {
  const f = catalogFixture(false)
  const result = await f.service.readInstalledApplications({})
  assert.equal(result.state, 'permission-required')
  assert.equal(result.applications.length, 0)
  assert.equal(f.reads(), 0)
})

test('authorized inventory loads installed apps with labels/icons, excluding self and duplicates', async () => {
  const f = catalogFixture(true)
  const result = await f.service.readInstalledApplications({ resourceManager: { getStringSync: ({bundleName}: {bundleName:string}) => bundleName.endsWith('.a') ? 'A应用' : 'B应用' } })
  assert.equal(f.reads(), 1)
  assert.equal(result.state, 'loaded')
  assert.deepEqual(Array.from(result.applications, (app: {bundleName:string}) => app.bundleName), ['com.example.a','com.example.b'])
  assert.equal(result.applications[0].label, 'A应用')
  assert.equal(result.applications[0].icon.id, 456)
  assert.equal(result.applications[1].systemApp, true)
})
