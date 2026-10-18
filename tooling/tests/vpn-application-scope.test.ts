import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const extensionSource = readFileSync(new URL(
  '../../entry/src/main/ets/vpnextension/NetworkVpnExtAbility.ets', import.meta.url), 'utf8')
const runtimeStoreSource = readFileSync(new URL(
  '../../entry/src/main/ets/services/VpnRuntimeConfigStore.ts', import.meta.url), 'utf8')
const coordinatorSource = readFileSync(new URL(
  '../../entry/src/main/ets/services/ConnectionCoordinator.ts', import.meta.url), 'utf8')
const catalogSource = readFileSync(new URL(
  '../../entry/src/main/ets/services/ApplicationCatalogService.ts', import.meta.url), 'utf8')
const indexSource = readFileSync(new URL(
  '../../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8')
const moduleSource = readFileSync(new URL(
  '../../entry/src/main/module.json5', import.meta.url), 'utf8')

test('VPN Extension applies only the validated allowlist to trustedApplications', () => {
  assert.match(extensionSource, /applicationScope\.mode === 'allowlist'/)
  assert.match(extensionSource, /config\.trustedApplications = applicationScope\.trustedApplications\.slice\(\)/)
  assert.doesNotMatch(extensionSource, /config\.blockedApplications\s*=/)
  const loadConfigAt = extensionSource.indexOf('const configJson: string = await configStore.load()')
  const loadScopeAt = extensionSource.indexOf('await configStore.loadApplicationScope()', loadConfigAt)
  const createAt = extensionSource.indexOf('connection.create(this.buildVpnConfig(ipv6Enabled, applicationScope))')
  assert.ok(loadConfigAt >= 0 && loadScopeAt > loadConfigAt && createAt > loadScopeAt)
})

test('application scope is encrypted and committed before a start ticket becomes visible', () => {
  assert.match(runtimeStoreSource, /vpn-application-scope\.secure\.json/)
  assert.match(runtimeStoreSource, /new SecureFileStore\(/)
  assert.match(runtimeStoreSource, /'vpn-application-scope'/)
  assert.match(runtimeStoreSource, /normalizeVpnApplicationScope/)
  assert.match(runtimeStoreSource, /await this\.applicationScopeStore\.save\(JSON\.stringify\(normalizedScope\)\)/)
  assert.match(runtimeStoreSource, /await this\.applicationScopeStore\.clear\(\)/)
  const ticketAt = coordinatorSource.indexOf('await this.runtimeBridge.publishStartTicket')
  const scopeWriteAt = coordinatorSource.indexOf('await this.configStore.save(configJson, applicationScope)', ticketAt)
  assert.ok(ticketAt >= 0 && scopeWriteAt > ticketAt)
})

test('normal app catalog uses launchable ability discovery and keeps manual bundle fallback', () => {
  assert.match(catalogSource, /bundle\.queryAbilityByWant\(HOME_WANT/)
  assert.match(catalogSource, /GET_ABILITY_INFO_WITH_APPLICATION/)
  assert.doesNotMatch(catalogSource, /getInstalledBundleList|ENTERPRISE_GET_INSTALLED_BUNDLE_LIST/)
  assert.match(moduleSource, /ohos\.permission\.GET_BUNDLE_INFO/)
  assert.match(indexSource, /applicationBundleDraft/)
  assert.match(indexSource, /validateApplicationBundleName\(bundleName\)/)
  assert.match(indexSource, /仅所选应用/)
  assert.match(indexSource, /Only selected apps/)
})

test('connected allowlist changes use acknowledged runtime reconfiguration', () => {
  assert.match(indexSource, /private async setApplicationMode\(mode: VpnApplicationMode\)/)
  assert.match(indexSource, /private async setApplicationSelected\(bundleName: string, selected: boolean\)/)
  assert.match(indexSource, /this\.applicationMode === 'allowlist' \?\s+gatePlan : 'persist-only'/)
  assert.match(indexSource, /vpnApplicationScope\(previousSettings\)/)
  assert.match(indexSource, /vpnApplicationScope\(nextSettings\)/)
  assert.match(indexSource, /coordinator\.connect\(nextConfigJson,\s+vpnApplicationScope\(nextSettings\)\)/)
})
