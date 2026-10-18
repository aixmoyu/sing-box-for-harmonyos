import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const indexPath = new URL('../../entry/src/main/ets/pages/Index.ets', import.meta.url)
const source = readFileSync(indexPath, 'utf8')
const runtimeMessagesPath = new URL('../../entry/src/main/ets/ui/RuntimeMessages.ts', import.meta.url)
const runtimeMessagesSource = readFileSync(runtimeMessagesPath, 'utf8')
const openSourceTextsPath = new URL('../../entry/src/main/ets/ui/OpenSourceTexts.ts', import.meta.url)
const openSourceTextsSource = readFileSync(openSourceTextsPath, 'utf8')
const designSystemPath = new URL('../../entry/src/main/ets/ui/DesignSystem.ts', import.meta.url)
const designSystemSource = readFileSync(designSystemPath, 'utf8')
const releaseConfigPath = new URL('../../entry/src/main/ets/ui/ReleaseConfig.ts', import.meta.url)
const releaseConfigSource = readFileSync(releaseConfigPath, 'utf8')
const entryAbilityPath = new URL('../../entry/src/main/ets/entryability/EntryAbility.ets', import.meta.url)
const entryAbilitySource = readFileSync(entryAbilityPath, 'utf8')

function paletteColor(paletteName: string, field: string): string {
  const paletteAt = designSystemSource.indexOf(`export const ${paletteName}`)
  assert.ok(paletteAt >= 0, `missing palette: ${paletteName}`)
  const paletteEnd = designSystemSource.indexOf('\n}', paletteAt)
  const paletteBody = designSystemSource.slice(paletteAt, paletteEnd)
  const match = paletteBody.match(new RegExp(`${field}: '(#[0-9A-Fa-f]{6})'`))
  assert.ok(match, `missing ${paletteName}.${field}`)
  return match[1]
}

function relativeLuminance(hex: string): number {
  const channels = [hex.slice(1, 3), hex.slice(3, 5), hex.slice(5, 7)]
    .map((part) => Number.parseInt(part, 16) / 255)
    .map((value) => value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4))
  return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
}

function contrastRatio(foreground: string, background: string): number {
  const first = relativeLuminance(foreground)
  const second = relativeLuminance(background)
  return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05)
}

test('English mode never falls through to an untranslated runtime error', () => {
  assert.match(source, /localizeRuntimeMessage\(value, this\.effectiveLanguage/)
  assert.match(runtimeMessagesSource, /\[\\u3400-\\u9FFF\]/)
  assert.match(runtimeMessagesSource, /The operation could not be completed\. Open Diagnostics for details\./)
  assert.match(runtimeMessagesSource, /HNA-\[A-Z-\]/)
  assert.match(source, /localizedSubscriptionName\(this\.subscriptionName\)/)
  assert.match(source, /localizedNodeName\(this\.selectedNodeName\)/)
})

test('runtime language, compliance details and sensitive-data clearing are real', () => {
  assert.match(source, /return this\.effectiveLanguage === 'en' \? en : zh/)
  assert.match(source, /this\.effectiveLanguage === 'en' \? this\.dnsPresetDescriptionEn/)
  assert.match(source, /privacyDetails\(\)/)
  assert.match(source, /licenseDetails\(\)/)
  assert.match(source, /AES-256-GCM/)
  assert.match(source, /GPL-3\.0-or-later/)
  assert.match(source, /not affiliated with or endorsed/)
  assert.match(source, /public privacy-policy URL/)
  assert.match(source, /private async clearSensitiveData\(\)/)
  assert.match(source, /const status: CoreStatus = await coordinator\.getStatus\(\)/)
  assert.match(source, /status\.running \|\| status\.lastError\.length > 0/)
  assert.match(source, /await runtimeStore\.clear\(\)/)
  assert.match(source, /await subscriptionRepository\.clear\(\)/)
  assert.match(source, /await settingsRepository\.clear\(\)/)
  assert.match(source, /private confirmClearSensitiveData\(\)/)
  assert.match(source, /private confirmClearSensitiveDataFinal\(\)/)
  assert.match(source, /if \(!this\.appearanceReady\)/)
  assert.match(source, /appearanceSkeleton\(\)/)
  assert.match(source, /accessibilityDescription/)
})

test('privacy consent is durable, revocable and gates every network feature', () => {
  assert.match(designSystemSource, /UI_PRIVACY_CONSENT_KEY: string = 'privacy-consent-v1'/)
  assert.match(source, /this\.privacyConsent = consent === 'accepted' \|\| consent === 'declined' \? consent : 'unknown'/)
  assert.match(source, /this\.privacyConsent === 'unknown'/)
  assert.match(source, /privacyOnboarding\(\)/)
  assert.match(source, /private async savePrivacyConsent\(consent: string\): Promise<boolean>/)
  const saveAt = source.indexOf('private async savePrivacyConsent')
  const saveEnd = source.indexOf('\n  private ', saveAt + 10)
  const saveBody = source.slice(saveAt, saveEnd)
  assert.ok(saveBody.indexOf('flushSync()') < saveBody.indexOf('this.privacyConsent = nextConsent'))
  assert.match(saveBody, /return false/)
  assert.match(source, /private networkConsentGranted\(\): boolean/)
  assert.ok((source.match(/if \(!this\.networkConsentGranted\(\)\) return/g) ?? []).length >= 8)
  assert.match(source, /private async declinePrivacyConsent\(\)/)
  assert.match(source, /private async withdrawPrivacyConsent\(\)/)
  const withdrawAt = source.indexOf('private async withdrawPrivacyConsent')
  const withdrawEnd = source.indexOf('\n  private ', withdrawAt + 10)
  const withdrawBody = source.slice(withdrawAt, withdrawEnd)
  assert.match(withdrawBody, /const status: CoreStatus = await coordinator\.getStatus\(\)/)
  assert.match(withdrawBody, /status\.running \|\| status\.lastError\.length > 0/)
  assert.match(withdrawBody, /await this\.savePrivacyConsent\('declined'\)/)
})

test('local legal pages include complete GPL and third-party notices without fake publication links', () => {
  assert.match(source, /userAgreementDetails\(\)/)
  assert.match(source, /GPL_V3_FULL_TEXT/)
  assert.match(source, /THIRD_PARTY_NOTICE_TEXT/)
  assert.match(openSourceTextsSource, /GNU GENERAL PUBLIC LICENSE/)
  assert.match(openSourceTextsSource, /Version 3, 29 June 2007/)
  assert.match(openSourceTextsSource, /END OF TERMS AND CONDITIONS/)
  assert.match(openSourceTextsSource, /# Third-party notices/)
  assert.match(openSourceTextsSource, /Apache License/)
  assert.match(openSourceTextsSource, /Redistribution and use in source and binary forms/)
  assert.match(openSourceTextsSource, /Additional IP Rights Grant \(Patents\)/)
  assert.match(source, /APACHE_2_FULL_TEXT/)
  assert.match(source, /GO_LICENSE_TEXT/)
  assert.match(source, /GO_PATENTS_TEXT/)
  assert.match(source, /signed build exact-version entry is shown under Public release information/)
  assert.doesNotMatch(source, /No final public URL is configured in this development build/)
  assert.match(source, /'Support email'/)
  assert.match(source, /'Support site'/)
  assert.match(source, /'Not configured · Release blocked'/)
})

test('public release metadata is wired to real links and debug values fail closed', () => {
  for (const field of [
    'operatorName',
    'privacyUrl',
    'privacyUrlEn',
    'userAgreementUrl',
    'userAgreementUrlEn',
    'supportUrl',
    'supportEmail',
    'correspondingSourceUrl'
  ]) {
    assert.match(releaseConfigSource, new RegExp(`${field}: string`))
    assert.match(releaseConfigSource, new RegExp(`${field}: ''`))
    assert.match(source, new RegExp(`RELEASE_PUBLIC_INFO\\.${field}`))
  }
  assert.match(source, /private isReleaseHttps\(value: string\): boolean/)
  assert.match(source, /private isReleaseEmail\(value: string\): boolean/)
  assert.match(source, /private releasePublicInfoReady\(\): boolean/)
  assert.match(source, /this\.isEnglish\(\) \?\s*RELEASE_PUBLIC_INFO\.privacyUrlEn : RELEASE_PUBLIC_INFO\.privacyUrl/)
  assert.match(source, /this\.isEnglish\(\) \?\s*RELEASE_PUBLIC_INFO\.userAgreementUrlEn : RELEASE_PUBLIC_INFO\.userAgreementUrl/)
  assert.match(source, /private async openReleaseLink\(url: string\): Promise<void>/)
  assert.match(source, /if \(!this\.isReleaseHttps\(url\)\)/)
  assert.match(source, /await this\.applicationContext\(\)\.openLink\(normalizedUrl\)/)
  assert.match(source, /releaseLinkRow\(field: string, url: string\)/)
  const linkRowAt = source.indexOf('releaseLinkRow(field: string, url: string)')
  const linkRowEnd = source.indexOf('\n  @Builder', linkRowAt + 10)
  const linkRow = source.slice(linkRowAt, linkRowEnd)
  assert.match(linkRow, /if \(this\.isReleaseHttps\(url\)\)/)
  assert.match(linkRow, /\.height\(44\)/)
  assert.match(linkRow, /\.onClick\(\(\) => this\.openReleaseLink\(url\)\)/)
  assert.match(source, /'Not configured · Release blocked'/)
  assert.match(source, /'Invalid configuration · Release blocked'/)
  assert.match(source, /no fabricated links or inactive entries are shown/)
})

test('connected mode exposes real proxy tests while direct TCP probes remain idle-only', () => {
  assert.match(source, /coordinator\.urlTest\(node\.id\)/)
  assert.match(source, /coordinator\.urlTest\('proxy'\)/)
  assert.match(source, /Proxy URLTest \$\{this\.localizedRuntimeText\(this\.proxyLatencyText\)\}/)
  assert.match(source, /this\.connectionPhase === 'idle' && !this\.isProbing\(node\.id\)/)
  assert.match(source, /this\.proxyRuntimeAvailable\(\) && !this\.proxyTestBusy\(\)/)
})

test('batch node test switches from idle TCP to serialized connected sing-box URLTests', () => {
  assert.match(source, /private async runAllNodeProxyUrlTests\(\)/)
  const batchAt = source.indexOf('private async runAllNodeProxyUrlTests')
  const batchEnd = source.indexOf('\n  private ', batchAt + 10)
  const batchBody = source.slice(batchAt, batchEnd)
  assert.match(batchBody, /this\.runMode === 'direct'/)
  assert.match(batchBody, /const token: number = this\.runtimeProbeEpoch/)
  assert.match(batchBody, /const subscriptionId: string = record\.id/)
  assert.match(batchBody, /for \(let index: number = 0; index < nodes\.length; index\+\+\)/)
  assert.match(batchBody, /await coordinator\.urlTest\(node\.id\)/)
  assert.match(batchBody, /this\.setProxyNodeLatency\(node\.id, -1\)/)
  assert.match(batchBody, /this\.isCurrentRuntimeProbe\(token\)/)
  assert.match(batchBody, /this\.storeState\.activeSubscriptionId !== subscriptionId/)
  assert.match(source, /this\.runAllNodeProxyUrlTests\(\)/)
  assert.match(source, /this\.probeAllNodes\(\)/)
  assert.match(source, /批量代理测速/)
  assert.match(source, /直连不测速/)
})

test('manual connected node selection waits for native selector readback before persistence', () => {
  assert.match(source, /this\.nodeSelectionMode !== 'manual'/)
  const selectAt = source.indexOf('await coordinator.selectOutbound(nodeId)')
  const verifyAt = source.indexOf("status.selectedOutboundTag !== nodeId", selectAt)
  const applyAt = source.indexOf('this.applyCoreStatus(status)', selectAt)
  const persistAt = source.indexOf('await this.persistAndApply(selectSubscriptionNode', selectAt)
  assert.ok(selectAt >= 0 && verifyAt > selectAt && applyAt > verifyAt && persistAt > applyAt)
  assert.match(source, /本次运行节点已切换，但首选节点保存失败；下次连接可能恢复旧选择/)
})

test('runtime diagnostics reject stale completions from an older VPN session', () => {
  assert.match(source, /private runtimeProbeEpoch: number = 0/)
  assert.match(source, /private runtimeWasRunning: boolean = false/)
  assert.match(source, /if \(this\.runtimeWasRunning && !status\.running\) this\.invalidateRuntimeProbes\(\)/)
  const invalidateAt = source.indexOf('private invalidateRuntimeProbes')
  const invalidateEnd = source.indexOf('\n  private ', invalidateAt + 10)
  const invalidateBody = source.slice(invalidateAt, invalidateEnd)
  assert.match(invalidateBody, /this\.proxyLatencyText = '— ms'/)
  assert.match(invalidateBody, /this\.proxyNodeLatencies = \[\]/)
  assert.match(invalidateBody, /this\.isProxyTesting = false/)
  assert.match(invalidateBody, /this\.isTestingWebsites = false/)
  assert.match(invalidateBody, /this\.isTestingEgress = false/)
  for (const method of ['runSelectedProxyUrlTest', 'runNodeProxyUrlTest', 'runAllWebsiteTests', 'probeEgressInfo']) {
    const start = source.indexOf(`private async ${method}`)
    const end = source.indexOf('\n  private ', start + 10)
    const body = source.slice(start, end)
    assert.match(body, /const token: number = this\.runtimeProbeEpoch/)
    assert.match(body, /this\.isCurrentRuntimeProbe\(token\)/)
    assert.match(body, /token === this\.runtimeProbeEpoch/)
  }
  const nodeTestAt = source.indexOf('private async runNodeProxyUrlTest')
  const nodeTestEnd = source.indexOf('\n  private ', nodeTestAt + 10)
  assert.match(source.slice(nodeTestAt, nodeTestEnd), /this\.setProxyNodeLatency\(node\.id, -1\)/)
})

test('connected direct mode saves only the next proxy preference and disables proxy tests', () => {
  const chooseAt = source.indexOf('private async chooseNode')
  const chooseEnd = source.indexOf('\n  private nodeSelectionInteractive', chooseAt)
  const chooseBody = source.slice(chooseAt, chooseEnd)
  const directAt = chooseBody.indexOf("this.runMode === 'direct'")
  const nativeAt = chooseBody.indexOf('coordinator.selectOutbound(nodeId)')
  assert.ok(directAt >= 0 && nativeAt > directAt)
  assert.match(chooseBody, /当前为直连模式，不经过代理；已保存为下次代理连接的首选节点/)
  assert.match(source, /private proxyRuntimeAvailable\(\): boolean \{[\s\S]*?this\.runMode !== 'direct'/)
  assert.match(source, /直连模式不使用代理/)
  assert.match(source, /节点代理测速不适用/)
  assert.match(source, /if \(this\.runMode === 'direct'\) return this\.t\('下次代理首选', 'Next proxy preference'\)/)
  assert.match(source, /Text\(this\.t\('当前业务出站：直连', 'Active outbound: Direct'\)\)/)
})

test('safe stop remains available while a connected runtime action is pending', () => {
  const enabledAt = source.indexOf('private connectionActionEnabled')
  const enabledEnd = source.indexOf('\n  private ', enabledAt + 10)
  const enabledBody = source.slice(enabledAt, enabledEnd)
  assert.match(enabledBody, /this\.connectionPhase === 'connected'/)
  assert.match(enabledBody, /return this\.connectionCoordinator !== null/)

  const connectAt = source.indexOf('private async tryConnect')
  const connectEnd = source.indexOf('\n  private ', connectAt + 10)
  const connectBody = source.slice(connectAt, connectEnd)
  assert.match(connectBody, /const stoppingAllowed: boolean/)
  assert.match(connectBody, /this\.configurationBusy && !stoppingAllowed/)
  assert.match(connectBody, /\(this\.settingsLoading \|\| this\.isLoadingStore\) && !stoppingAllowed/)
  assert.ok(connectBody.indexOf("this.connectionPhase === 'connected'") < connectBody.indexOf('coordinator.getInfo()'))

  const labelAt = source.indexOf('private connectionButtonLabel')
  const labelEnd = source.indexOf('\n  private ', labelAt + 10)
  const labelBody = source.slice(labelAt, labelEnd)
  assert.ok(labelBody.indexOf("this.connectionPhase === 'connected'") < labelBody.indexOf('this.configurationBusy'))
})

test('idle TCP probe results cannot cross the VPN start boundary', () => {
  assert.match(source, /private idleProbeEpoch: number = 0/)
  const probeAt = source.indexOf('private async probeNode')
  const probeEnd = source.indexOf('\n  private ', probeAt + 10)
  const probeBody = source.slice(probeAt, probeEnd)
  assert.match(probeBody, /const token: number = this\.idleProbeEpoch/)
  assert.match(probeBody, /token !== this\.idleProbeEpoch \|\| this\.connectionPhase !== 'idle'/)

  const connectAt = source.indexOf('private async tryConnect')
  const connectEnd = source.indexOf('\n  private ', connectAt + 10)
  assert.match(source.slice(connectAt, connectEnd), /this\.invalidateIdleProbes\(\)/)
})

test('a live outbound change invalidates path-specific diagnostics', () => {
  assert.match(source, /private runtimeSelectedOutboundTag: string = ''/)
  const applyAt = source.indexOf('private applyCoreStatus')
  const applyEnd = source.indexOf('\n  private ', applyAt + 10)
  const applyBody = source.slice(applyAt, applyEnd)
  assert.match(applyBody, /this\.runtimeSelectedOutboundTag !== currentRuntimeTag/)
  assert.match(applyBody, /this\.invalidateRuntimePathDiagnostics\(\)/)
  assert.match(applyBody, /this\.runtimeSelectedOutboundTag = currentRuntimeTag/)
  const pathInvalidateAt = source.indexOf('private invalidateRuntimePathDiagnostics')
  const pathInvalidateEnd = source.indexOf('\n  private ', pathInvalidateAt + 10)
  const pathInvalidateBody = source.slice(pathInvalidateAt, pathInvalidateEnd)
  assert.match(pathInvalidateBody, /this\.websiteTestResults = emptyWebsiteTestResults\(\)/)
  assert.match(pathInvalidateBody, /this\.egressInfo = emptyEgressInfo\(\)/)
  assert.doesNotMatch(pathInvalidateBody, /this\.proxyNodeLatencies = \[\]/)

  const chooseAt = source.indexOf('private async chooseNode')
  const chooseEnd = source.indexOf('\n  private ', chooseAt + 10)
  const chooseBody = source.slice(chooseAt, chooseEnd)
  assert.doesNotMatch(chooseBody, /this\.proxyNodeLatencies = \[\]/)
})

test('home takeover card uses truthful switches for TUN IPv6 and unavailable system proxy', () => {
  assert.match(source, /homeNetworkTakeoverCard\(\)/)
  assert.match(source, /tunSwitch\(\)[\s\S]*?Toggle\(\{ type: ToggleType\.Switch, isOn: this\.connectionPhase === 'connected' \}\)/)
  assert.match(source, /\.onChange\(\(enabled: boolean\) => this\.setTunEnabled\(enabled\)\)/)
  assert.match(source, /unavailableSystemProxySwitch\(\)[\s\S]*?Toggle\(\{ type: ToggleType\.Switch, isOn: false \}\)[\s\S]*?\.enabled\(false\)/)
  assert.match(source, /ipv6Switch\(\)[\s\S]*?Toggle\(\{ type: ToggleType\.Switch, isOn: this\.ipv6Enabled \}\)/)
  assert.match(source, /\.onChange\(\(enabled: boolean\) => this\.setIpv6Enabled\(enabled\)\)/)
})

test('diagnostic section selector is outside its independently scrolling content', () => {
  const pageAt = source.indexOf('activityPage()')
  const selectorAt = source.indexOf("this.activitySectionButton('overview')", pageAt)
  const scrollAt = source.indexOf('Scroll() {', pageAt)
  assert.ok(pageAt >= 0 && selectorAt > pageAt && scrollAt > selectorAt)
})

test('subscription UI supports optional local names and display-name fallback', () => {
  assert.match(source, /placeholder: this\.t\('订阅名称（可选）', 'Subscription name \(optional\)'\)/)
  assert.match(source, /this\.newSubscriptionName\s*\n\s*\)/)
  assert.match(source, /renameSubscription\(this\.storeState, record\.id, this\.renameSubscriptionDraft\)/)
  assert.doesNotMatch(source, /record\.bundle\.metadata\.title/)
})

test('selecting an existing custom DNS applies it through runtime reconfiguration', () => {
  const selectAt = source.indexOf("if (presetId === 'custom')")
  const validateAt = source.indexOf('validateDnsEndpoint(this.customDns)', selectAt)
  const commitAt = source.indexOf("await this.commitRuntimeReconfiguration('切换 DNS'", validateAt)
  assert.ok(selectAt >= 0 && validateAt > selectAt && commitAt > validateAt)
})

test('connected subscription and IPv6 changes use acknowledged restart transactions', () => {
  const commitAt = source.indexOf('private async commitRuntimeReconfiguration')
  const commitEnd = source.indexOf('\n  private ', commitAt + 10)
  const body = source.slice(commitAt, commitEnd)
  const disconnectAt = body.indexOf('await coordinator.disconnect()')
  const persistAt = body.indexOf('await this.persistRuntimeSnapshot', disconnectAt)
  const connectAt = body.indexOf('await coordinator.connect(nextConfigJson,', persistAt)
  const runningAt = body.indexOf('if (!status.running)', connectAt)
  assert.ok(disconnectAt >= 0 && persistAt > disconnectAt && connectAt > persistAt && runningAt > connectAt)
  assert.match(body, /reconfigurationRecovery\(isConfirmedNoTunStartupError\(message\)\)/)
  assert.match(body, /this\.connectionPhase = 'unknown'/)

  const subscriptionAt = source.indexOf('private async activateSubscription')
  const subscriptionEnd = source.indexOf('\n  private ', subscriptionAt + 10)
  assert.match(source.slice(subscriptionAt, subscriptionEnd),
    /commitRuntimeReconfiguration\('切换订阅'/)

  const ipv6At = source.indexOf('private async setIpv6Enabled')
  const ipv6End = source.indexOf('\n  private ', ipv6At + 10)
  assert.match(source.slice(ipv6At, ipv6End),
    /commitRuntimeReconfiguration\('切换 IPv6'/)
})

test('explicit connected stop invalidates stale automatic reconnect', () => {
  assert.match(source, /private reconfigurationEpoch: number = 0/)
  const commitAt = source.indexOf('private async commitRuntimeReconfiguration')
  const commitEnd = source.indexOf('\n  private ', commitAt + 10)
  const body = source.slice(commitAt, commitEnd)
  assert.match(body, /const token: number = \+\+this\.reconfigurationEpoch/)
  assert.match(body, /token !== this\.reconfigurationEpoch/)

  const connectAt = source.indexOf('private async tryConnect')
  const connectEnd = source.indexOf('\n  private ', connectAt + 10)
  const connectBody = source.slice(connectAt, connectEnd)
  assert.match(connectBody, /this\.connectionPhase === 'connected'[\s\S]*?this\.reconfigurationEpoch\+\+/)
})

test('desired-state switch handlers reject stale or duplicate toggle events', () => {
  const tunAt = source.indexOf('private async setTunEnabled')
  const tunEnd = source.indexOf('\n  private ', tunAt + 10)
  const tunBody = source.slice(tunAt, tunEnd)
  assert.match(tunBody, /if \(this\.connectionPhase === 'connected'\) return/)
  assert.match(tunBody, /if \(this\.connectionPhase === 'idle'\) return/)
  assert.match(tunBody, /await this\.tryConnect\(\)/)

  const ipv6At = source.indexOf('private async setIpv6Enabled')
  const ipv6End = source.indexOf('\n  private ', ipv6At + 10)
  const ipv6Body = source.slice(ipv6At, ipv6End)
  assert.match(ipv6Body, /if \(enabled === this\.ipv6Enabled\) return/)
  assert.match(ipv6Body, /nextSettings\.ipv6Enabled = enabled/)
  assert.doesNotMatch(ipv6Body, /!this\.ipv6Enabled/)
})

test('current subscription and connected automatic nodes do not expose dead selection targets', () => {
  const actionAt = source.indexOf('private subscriptionActionEnabled')
  const actionEnd = source.indexOf('\n  private ', actionAt + 10)
  const actionBody = source.slice(actionAt, actionEnd)
  assert.match(actionBody, /record\.id !== this\.storeState\.activeSubscriptionId/)

  const interactiveAt = source.indexOf('private nodeSelectionInteractive')
  const interactiveEnd = source.indexOf('\n  private ', interactiveAt + 10)
  const interactiveBody = source.slice(interactiveAt, interactiveEnd)
  assert.match(interactiveBody, /this\.runMode === 'direct' \|\| this\.nodeSelectionMode === 'manual'/)
  assert.match(source, /运行中节点列表已锁定/)
})

test('privacy keeps explicit first-run choices and uses a confirmed settings switch later', () => {
  assert.match(source, /Button\(this\.t\('同意并继续', 'Agree & continue'\)\)/)
  assert.match(source, /Button\(this\.t\('不同意，仅离线浏览', 'Decline · Offline mode'\)\)/)
  assert.match(source, /networkConsentSwitch\(\)[\s\S]*?Toggle\(\{ type: ToggleType\.Switch, isOn: this\.privacyConsent === 'accepted' \}\)/)
  assert.match(source, /\.onChange\(\(enabled: boolean\) => this\.setNetworkConsentEnabled\(enabled\)\)/)
  assert.match(source, /if \(enabled\)[\s\S]*?savePrivacyConsent\('accepted'\)/)
  assert.match(source, /this\.confirmWithdrawPrivacyConsent\(\)/)
  assert.match(source, /await coordinator\.getStatus\(\)/)
})

test('four-tab shell keeps fixed primary and diagnostic navigation', () => {
  for (const page of ['homePage()', 'subscriptionPage()', 'activityPage()', 'settingsPage()']) {
    assert.match(source, new RegExp(page.replace(/[()]/g, '\\$&')))
  }
  const pageAt = source.indexOf('activityPage()')
  const selectorAt = source.indexOf("this.activitySectionButton('overview')", pageAt)
  const scrollAt = source.indexOf('Scroll() {', pageAt)
  assert.ok(selectorAt > pageAt && scrollAt > selectorAt)
  const buildAt = source.indexOf('build()')
  const homeAt = source.indexOf("this.tabItem($r('sys.symbol.house'), 'home')", buildAt)
  const profilesAt = source.indexOf("this.tabItem($r('sys.symbol.rectangle_stack'), 'subscription')", buildAt)
  const diagnosticsAt = source.indexOf("this.tabItem($r('sys.symbol.diagnostic_analytics'), 'activity')", buildAt)
  const settingsAt = source.indexOf("this.tabItem($r('sys.symbol.gearshape'), 'settings')", buildAt)
  assert.ok(homeAt > buildAt && profilesAt > homeAt && diagnosticsAt > profilesAt && settingsAt > diagnosticsAt)
})

test('primary navigation uses one regular HarmonyOS Symbol family and API 22 glass chrome', () => {
  assert.doesNotMatch(source, /import \{ uiMaterial \} from '@kit\.ArkUI'/)
  assert.doesNotMatch(source, /\.systemMaterial\(/)
  for (const symbol of ['house', 'rectangle_stack', 'diagnostic_analytics', 'gearshape']) {
    assert.match(source, new RegExp(`\\$r\\('sys\\.symbol\\.${symbol}'\\)`))
  }
  assert.match(source, /tabItem\(icon: Resource, tab: string\)[\s\S]*?SymbolGlyph\(icon\)[\s\S]*?\.fontWeight\(FontWeight\.Regular\)/)
  assert.doesNotMatch(source, /this\.tabItem\('[⌂▤⌁⚙]'/)
  assert.match(source, /\.margin\(\{ left: 16, right: 16, bottom: 8 \}\)[\s\S]*?\.backgroundColor\(this\.palette\(\)\.surfaceGlass\)[\s\S]*?\.backgroundBlurStyle\(BlurStyle\.COMPONENT_ULTRA_THIN\)[\s\S]*?\.borderRadius\(28\)[\s\S]*?\.shadow\(/)
})

test('API 22 controls and shared chrome retain modern blur, border and shadow primitives', () => {
  assert.match(source, /\.switchStyle\(\{ pointRadius: 13, pointColor: this\.palette\(\)\.controlThumb/)
  assert.match(source, /\.backgroundBlurStyle\(BlurStyle\.COMPONENT_THIN\)/)
  assert.match(source, /\.border\(\{ width: 1, color: this\.palette\(\)\.border \}\)/)
  assert.match(source, /API 22\+/)
  assert.match(source, /\.linearGradient\(\{ angle: 154/)
  assert.match(source, /\.borderRadius\(24\)/)
})

test('home node rendering is bounded, searchable and grows only in explicit 50-row batches', () => {
  assert.match(source, /const NODE_RENDER_BATCH_SIZE: number = 50/)
  assert.match(source, /private matchingNodes\(\): ProxyNode\[\]/)
  assert.match(source, /return this\.matchingNodes\(\)\.slice\(0, this\.nodeRenderLimit\)/)
  assert.match(source, /private updateNodeFilter\(value: string\): void/)
  assert.match(source, /this\.resetNodeWindow\(false\)/)
  assert.match(source, /private loadMoreNodes\(\): void/)
  assert.match(source, /this\.nodeRenderLimit \+ NODE_RENDER_BATCH_SIZE/)
  assert.match(source, /if \(activeSubscriptionChanged \|\| activeNodeSetChanged\) this\.resetNodeWindow\(true\)/)
  assert.match(source, /Showing \$\{this\.visibleNodes\(\)\.length\} of \$\{this\.matchingNodes\(\)\.length\}/)
  assert.match(source, /\.onChange\(\(value: string\) => this\.updateNodeFilter\(value\)\)/)
  assert.match(source, /\.onClick\(\(\) => this\.loadMoreNodes\(\)\)/)

  const homeAt = source.indexOf('homePage()')
  const profilesAt = source.indexOf('subscriptionPage()', homeAt)
  const homeBody = source.slice(homeAt, profilesAt)
  assert.match(homeBody, /ForEach\(this\.visibleNodes\(\)/)
  assert.doesNotMatch(homeBody, /(?:List|LazyForEach)\(/)

  const probeAt = source.indexOf('private async probeAllNodes')
  const probeEnd = source.indexOf('\n  private ', probeAt + 10)
  const probeBody = source.slice(probeAt, probeEnd)
  assert.match(probeBody, /record \? record\.bundle\.nodes : \[\]/)
  assert.doesNotMatch(probeBody, /this\.visibleNodes\(\)/)
})

test('compact layout handles half-width controls and long status values without horizontal-only assumptions', () => {
  assert.match(source, /const COMPACT_LAYOUT_MAX_WIDTH: number = 400/)
  assert.match(source, /@State viewportWidth: number = 360/)
  assert.match(source, /private isCompactLayout\(\): boolean/)
  assert.match(source, /\.onAreaChange\(\(_oldArea: Area, newArea: Area\)/)
  assert.match(source, /this\.viewportWidth = newArea\.width/)

  const cardAt = source.indexOf('subscriptionCard(record: SubscriptionRecord)')
  const cardEnd = source.indexOf('\n  @Builder', cardAt + 10)
  const card = source.slice(cardAt, cardEnd)
  assert.match(card, /if \(this\.isCompactLayout\(\)\) \{[\s\S]*?subscriptionActionButton\(record, 'use', 0\)[\s\S]*?subscriptionActionButton\(record, 'update', 8\)[\s\S]*?subscriptionActionButton\(record, 'rename', 0\)[\s\S]*?subscriptionActionButton\(record, 'delete', 8\)/)

  const statusAt = source.indexOf('settingsStatusRow(field: string, topMargin: number)')
  const statusEnd = source.indexOf('\n  @Builder', statusAt + 10)
  const statusRow = source.slice(statusAt, statusEnd)
  assert.match(statusRow, /if \(this\.isCompactLayout\(\)\) \{\s*Column\(\)/)
  assert.match(statusRow, /maxLines\(3\)/)
  assert.match(statusRow, /textOverflow\(\{ overflow: TextOverflow\.Ellipsis \}\)/)
  assert.ok((source.match(/minFontSize: APP_TYPOGRAPHY\.controlMin/g) ?? []).length >= 20)
  assert.ok((source.match(/\.maxFontScale\(APP_TYPOGRAPHY\.controlMaxScale\)/g) ?? []).length >= 20)
})

test('node selection uses one large sibling target while the test button stays independent', () => {
  const rowAt = source.indexOf('nodeRow(record: SubscriptionRecord, node: ProxyNode)')
  const rowEnd = source.indexOf('\n  @Builder', rowAt + 10)
  const row = source.slice(rowAt, rowEnd)
  assert.match(row, /Button\(\) \{[\s\S]*?\.height\(this\.isCompactLayout\(\) \? 62 : 66\)[\s\S]*?\.enabled\(this\.nodeSelectionInteractive\(\)\)[\s\S]*?\.onClick\(\(\) => this\.chooseNode\(record\.id, node\.id\)\)/)
  assert.match(row, /Button\(this\.nodeTestActionLabel\(node\.id\)\)[\s\S]*?\.width\(this\.isCompactLayout\(\) \? 72 : 86\)[\s\S]*?\.onClick\(\(\) => \{\s*if \(this\.connectionPhase === 'connected'\) this\.runNodeProxyUrlTest\(node\)/)
  assert.doesNotMatch(row, /ClickEvent|stopPropagation/)
  const arrowAt = row.indexOf("Text(record.selectedNodeId === node.id ? '✓' : '›')")
  assert.ok(arrowAt >= 0)
  const arrowEnd = row.indexOf('\n        }', arrowAt)
  assert.ok(arrowEnd > arrowAt)
  assert.doesNotMatch(row.slice(arrowAt, arrowEnd), /\.onClick\(/)
})

test('node-row testing uses compact state labels instead of a clipped proxy sentence', () => {
  const labelAt = source.indexOf('private nodeTestActionLabel(nodeId: string)')
  const labelEnd = source.indexOf('\n  private ', labelAt + 10)
  const label = source.slice(labelAt, labelEnd)
  assert.match(label, /this\.t\('测速中', 'Testing'\)/)
  assert.match(label, /this\.t\('测速', 'Test'\)/)
  assert.match(label, /this\.t\('失败', 'Failed'\)/)
  assert.match(label, /`\$\{proxyLatency\.milliseconds\}ms`/)
  assert.doesNotMatch(label, /代理测试中|Testing proxy|Proxy /)
})

test('node latency colors and sorting use current-path measurements with honest thresholds', () => {
  assert.match(source, /@State nodeSortMode: string = 'default'/)
  assert.match(source, /private nodeLatencyResult\(nodeId: string\)/)
  assert.match(source, /this\.connectionPhase === 'connected' \?\s*this\.proxyNodeLatencies : this\.nodeLatencies/)
  assert.match(source, /compareNodeLatency\(candidateLatency,/)
  assert.match(source, /this\.nodeSortButton\('default'\)/)
  assert.match(source, /this\.nodeSortButton\('latency'\)/)
  assert.match(source, /延迟等级：快 ≤100 · 一般 ≤250 · 慢 ≤600 · 很慢 >600ms/)
  assert.match(source, /this\.nodeLatencyForeground\(node\.id\)/)
  assert.match(source, /this\.nodeLatencyBackground\(node\.id\)/)
})

test('light theme small tertiary and accent text keep at least 4.5 to 1 contrast', () => {
  const tertiary = paletteColor('LIGHT_PALETTE', 'textTertiary')
  const accent = paletteColor('LIGHT_PALETTE', 'accent')
  assert.ok(contrastRatio(tertiary, paletteColor('LIGHT_PALETTE', 'surface')) >= 4.5)
  assert.ok(contrastRatio(tertiary, paletteColor('LIGHT_PALETTE', 'background')) >= 4.5)
  assert.ok(contrastRatio(accent, paletteColor('LIGHT_PALETTE', 'accentSoft')) >= 4.5)
})

test('light and dark themes keep readable text roles and semantic foregrounds', () => {
  for (const palette of ['LIGHT_PALETTE', 'DARK_PALETTE']) {
    for (const textRole of ['textPrimary', 'textSecondary', 'textTertiary', 'placeholder']) {
      assert.ok(contrastRatio(paletteColor(palette, textRole), paletteColor(palette, 'surface')) >= 4.5,
        `${palette}.${textRole} must remain readable on cards`)
    }
    assert.ok(contrastRatio(paletteColor(palette, 'accentForeground'), paletteColor(palette, 'accent')) >= 4.5,
      `${palette}.accentForeground must remain readable on accent controls`)
  }
  assert.ok(contrastRatio(paletteColor('LIGHT_PALETTE', 'blue'),
    paletteColor('LIGHT_PALETTE', 'blueSoft')) >= 4.5)
  assert.ok(contrastRatio(paletteColor('LIGHT_PALETTE', 'danger'),
    paletteColor('LIGHT_PALETTE', 'dangerSoft')) >= 4.5)
  assert.match(source, /this\.currentTab === tab \? this\.palette\(\)\.accent : this\.palette\(\)\.textSecondary/)
})

test('phone typography stays compact and protects dynamic labels from clipping', () => {
  assert.match(designSystemSource, /APP_TYPOGRAPHY: AppTypography/)
  assert.match(designSystemSource, /display: 24/)
  assert.match(designSystemSource, /pageTitle: 20/)
  assert.match(designSystemSource, /metric: 15/)
  assert.match(designSystemSource, /control: 10/)
  assert.match(designSystemSource, /controlCompact: 9/)
  assert.match(designSystemSource, /controlMin: 9/)
  assert.match(designSystemSource, /controlMaxScale: 1\.3/)
  assert.match(designSystemSource, /textDisabled: '#566B80'/)
  assert.match(designSystemSource, /controlThumb: '#FFFFFF'/)
  assert.match(source, /Text\(this\.connectionTitle\(\)\)[\s\S]*?APP_TYPOGRAPHY\.displayCompact[\s\S]*?maxLines\(1\)[\s\S]*?TextOverflow\.Ellipsis/)
  assert.match(source, /Text\(this\.localizedRuntimeText\(this\.downloadSpeed\)\)[\s\S]*?APP_TYPOGRAPHY\.metric[\s\S]*?maxLines\(1\)/)
  assert.match(source, /Text\(this\.localizedNodeName\(this\.selectedNodeName\)\)[\s\S]*?APP_TYPOGRAPHY\.sectionTitle[\s\S]*?TextOverflow\.Ellipsis/)
})

test('labeled buttons keep full touch targets while labels shrink before ellipsis', () => {
  const labeledButtons = [...source.matchAll(/^\s*Button\((?!\))/gm)]
  assert.ok(labeledButtons.length >= 30)
  for (const match of labeledButtons) {
    const start = match.index ?? 0
    const currentLineEnd = source.indexOf('\n', start)
    const nextButton = source.slice(currentLineEnd + 1).search(/^\s*Button\(/m)
    const end = nextButton < 0 ? source.length : currentLineEnd + 1 + nextButton
    const nextBuilder = source.indexOf('\n  @Builder', start + 1)
    const block = source.slice(start, nextBuilder >= 0 && nextBuilder < end ? nextBuilder : end)
    assert.match(block, /\.fontSize\([^\n]*APP_TYPOGRAPHY\.control/)
    assert.match(block, /minFontSize: APP_TYPOGRAPHY\.controlMin/)
    assert.match(block, /maxFontSize:/)
    assert.match(block, /heightAdaptivePolicy: TextHeightAdaptivePolicy\.MIN_FONT_SIZE_FIRST/)
    assert.match(block, /\.maxFontScale\(APP_TYPOGRAPHY\.controlMaxScale\)/)
  }
  assert.match(source, /Button\(this\.nodeTestActionLabel\(node\.id\)\)[\s\S]*?\.height\(44\)[\s\S]*?APP_TYPOGRAPHY\.controlCompact/)
  assert.match(source, /Button\(this\.t\('校验并保存自定义 DNS',[\s\S]*?APP_TYPOGRAPHY\.controlCompact/)
})

test('appearance controls use application language and color mode with persisted preferences', () => {
  assert.match(source, /preferences\.getPreferences\(context, UI_PREFERENCES_FILE\)/)
  assert.match(source, /setLanguage\(language\)/)
  assert.match(source, /if \(preference !== 'system'\) this\.applicationContext\(\)\.getApplicationContext\(\)\.setLanguage\(language\)/)
  assert.match(source, /setAppPreferredLanguage\(preference === 'system' \? 'default' : language\)/)
  assert.match(source, /setColorMode\(colorMode\)/)
  assert.match(source, /putSync\(UI_LANGUAGE_KEY, preference\)/)
  assert.match(source, /putSync\(UI_THEME_KEY, preference\)/)
  assert.match(source, /this\.languageChoiceButton\('en'\)/)
  assert.match(source, /this\.themeChoiceButton\('dark'\)/)
})

test('language-reactive builders resolve visible labels internally instead of capturing translated parameters', () => {
  for (const [signature, labelExpression] of [
    ['modeButton(mode: RunMode)', 'this.runModeUiLabel(mode)'],
    ['selectionModeButton(mode: NodeSelectionMode)', 'this.selectionModeUiLabel(mode)'],
    ['activitySectionButton(section: string)', 'this.activitySectionUiLabel(section)'],
    ['languageChoiceButton(preference: UiLanguagePreference)', 'this.languagePreferenceUiLabel(preference)'],
    ['themeChoiceButton(preference: UiThemePreference)', 'this.themePreferenceUiLabel(preference)'],
    ['tabItem(icon: Resource, tab: string)', 'this.primaryTabUiLabel(tab)'],
    ['releaseValueRow(field: string, value: string, valid: boolean)', 'this.releaseFieldUiLabel(field)'],
    ['releaseLinkRow(field: string, url: string)', 'this.releaseFieldUiLabel(field)'],
    ['localLegalTextCard(kind: string)', 'this.localLegalTitle(kind)'],
    ['subscriptionActionButton(record: SubscriptionRecord, action: string, leftMargin: number)',
      'this.subscriptionActionLabel(record, action)'],
    ['settingsStatusRow(field: string, topMargin: number)', 'this.settingsStatusLabel(field)']
  ]) {
    const start = source.indexOf(signature)
    assert.ok(start >= 0, `missing reactive builder: ${signature}`)
    const end = source.indexOf('\n  @Builder', start + signature.length)
    assert.ok(source.slice(start, end < 0 ? source.length : end).includes(labelExpression),
      `${signature} must resolve ${labelExpression} during rendering`)
  }
  assert.doesNotMatch(source,
    /this\.(?:modeButton|selectionModeButton|activitySectionButton|languageChoiceButton|themeChoiceButton|tabItem|releaseValueRow|releaseLinkRow|localLegalTextCard)\([^\n]*this\.t\(/)
  assert.match(source, /if \(preference === 'zh'\) return this\.t\('中文', 'Chinese'\)/)
  assert.match(source, /return this\.t\('英文', 'English'\)/)
  assert.match(source, /if \(tab === 'home'\) return this\.t\('首页', 'Home'\)/)
  assert.match(source, /if \(tab === 'subscription'\) return this\.t\('订阅', 'Profiles'\)/)
  assert.match(source, /if \(tab === 'activity'\) return this\.t\('诊断', 'Diagnostics'\)/)
  assert.match(source, /return this\.t\('设置', 'Settings'\)/)
})

test('system appearance is initialized from current configuration and follows later changes', () => {
  assert.match(entryAbilitySource, /this\.context\.config\.colorMode/)
  assert.match(entryAbilitySource, /this\.context\.config\.language/)
  assert.match(entryAbilitySource, /onConfigurationUpdate\(newConfig: Configuration\)/)
  assert.match(entryAbilitySource, /AppStorage\.setOrCreate\('colorMode'/)
  assert.match(entryAbilitySource, /AppStorage\.setOrCreate\('languageCode'/)
  assert.match(source, /@StorageProp\('colorMode'\) systemColorMode/)
  assert.match(source, /@StorageProp\('languageCode'\) @Watch\('onSystemLanguageCodeChanged'\) systemLanguageCode/)
  assert.match(source, /private onSystemLanguageCodeChanged\(\): void/)
  assert.match(source, /if \(this\.languagePreference !== 'system'\) return/)
  assert.match(source, /this\.effectiveLanguage = this\.systemLanguageCode\.toLowerCase\(\)\.startsWith\('en'\) \? 'en' : 'zh'/)
  assert.doesNotMatch(entryAbilitySource, /envProp\('colorMode', ColorMode\.DARK\)/)
  assert.doesNotMatch(entryAbilitySource, /envProp\('languageCode', 'zh'\)/)
})

test('redesigned controls preserve every real runtime action', () => {
  for (const handler of [
    'this.setTunEnabled(enabled)',
    'this.setIpv6Enabled(enabled)',
    'this.selectRunMode(mode)',
    'this.selectNodeSelectionMode(mode)',
    'this.chooseNode(record.id, node.id)',
    'this.runSelectedProxyUrlTest()',
    'this.runNodeProxyUrlTest(node)',
    'this.importSubscription()',
    'this.activateSubscription(record.id)',
    'this.refreshSubscription(record)',
    'this.runAllWebsiteTests()',
    'this.probeEgressInfo()',
    'this.selectDnsPreset(preset.id)',
    'this.saveCustomDns()'
  ]) {
    assert.ok(source.includes(handler), `missing runtime action: ${handler}`)
  }
  assert.match(source, /Toggle\(\{ type: ToggleType\.Switch, isOn: false \}\)[\s\S]*?\.enabled\(false\)/)
})

test('website diagnostics explain safe failure categories and ChatGPT two-stage reachability', () => {
  assert.match(source, /private websiteProbeErrorLabel\(result: WebsiteTestResult\): string/)
  for (const category of ['dns', 'tcp', 'timeout', 'tls', 'io']) {
    assert.match(source, new RegExp(`result\\.errorCategory === '${category}'`))
  }
  assert.match(source, /E\$\{result\.errorCode\}/)
  assert.match(source, /入口可达 · 主页可打开/)
  assert.match(source, /Endpoint reached · Home available/)
  assert.match(source, /入口可达 · 主页受限/)
  assert.match(source, /Endpoint reached · Home limited/)
  assert.match(source, /Google 和 YouTube 仅 HTTP 204/)
  assert.match(source, /Google and YouTube pass only on HTTP 204/)
})

test('redesigned interactive controls meet the 44vp touch-target baseline', () => {
  const interactiveHeights = [...source.matchAll(/(?:Button|TextInput)\([^\n]*\)[\s\S]{0,300}?\.height\((\d+)\)/g)]
    .map((match) => Number(match[1]))
  assert.ok(interactiveHeights.length > 20)
  assert.equal(interactiveHeights.filter((height) => height < 44).length, 0)
})

test('settings local routing editor is persisted and applied through the runtime transaction', () => {
  assert.match(source, /@State localRules: RoutingRule\[\] = \[\]/)
  assert.match(source, /validateLocalRoutingRule\(ruleKind/)
  assert.match(source, /normalizeLocalRoutingRules\(this\.localRules\.concat\(\[rule\]\)\)/)
  assert.match(source, /nextSettings\.localRules = nextRules/)
  assert.match(source, /commitRuntimeReconfiguration\('新增本地规则'/)
  assert.match(source, /commitRuntimeReconfiguration\('删除本地规则'/)
  assert.match(source, /const plan: RuntimeReconfigurationPlan = this\.runMode === 'rule' \? gatePlan : 'persist-only'/)
  assert.match(source, /本地规则已保存；切换到规则模式后应用/)
  assert.match(source, /本地规则已删除；当前路由无需重连/)
  assert.match(source, /localRules: settings\.localRules/)
  assert.match(source, /localRules: this\.localRules/)
  assert.match(source, /this\.t\('本地规则', 'LOCAL RULES'\)/)
  assert.match(source, /this\.localRuleKindButton\('domain'\)/)
  assert.match(source, /this\.localRuleKindButton\('domain_suffix'\)/)
  assert.match(source, /this\.localRuleKindButton\('ip_cidr'\)/)
  assert.match(source, /this\.localRuleTargetButton\('proxy'\)/)
  assert.match(source, /this\.localRuleTargetButton\('direct'\)/)
  assert.match(source, /this\.localRuleTargetButton\('reject'\)/)
  assert.match(source, /订阅规则仍由订阅提供并在诊断页只读展示/)
  assert.match(source, /订阅含不支持规则时，规则模式仍会阻止启动/)
})

test('settings expose a real per-application VPN allowlist with manual fallback', () => {
  assert.match(source, /@State applicationMode: VpnApplicationMode = 'all'/)
  assert.match(source, /@State trustedApplications: string\[\] = \[\]/)
  assert.match(source, /this\.applicationModeButton\('all'\)/)
  assert.match(source, /this\.applicationModeButton\('allowlist'\)/)
  assert.match(source, /Toggle\(\{[\s\S]*?isOn: this\.trustedApplications\.includes\(application\.bundleName\)/)
  assert.match(source, /private async setApplicationSelected\(bundleName: string, selected: boolean\)/)
  assert.match(source, /normalizeTrustedApplications\(selected \?/)
  assert.match(source, /applicationBundleDraft/)
  assert.match(source, /应用接管白名单/)
  assert.match(source, /APP TUNNEL ALLOWLIST/)
  assert.match(source, /其他应用直接使用系统网络/)
  assert.match(source, /every other app uses the system network directly/)
})

test('local-rule validation and connected reconfiguration remain meaningful in English', () => {
  assert.match(runtimeMessagesSource, /case '本地规则已保存并应用': return 'Local rule saved and applied\.'/)
  assert.match(runtimeMessagesSource, /case '本地规则已删除': return 'Local rule removed\.'/)
  assert.match(runtimeMessagesSource, /case '系统仍未确认旧 VPN 网络已消失，升级会话仍保持锁定'/)
  assert.match(runtimeMessagesSource, /case 'CIDR IP 地址格式不正确': return 'The CIDR IP address is invalid\.'/)
  assert.match(runtimeMessagesSource, /value\.includes\('：正在安全停止当前 VPN\/TUN…'\)/)
})
