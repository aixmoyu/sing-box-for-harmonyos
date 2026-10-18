import assert from 'node:assert/strict'
import { existsSync, readFileSync, readdirSync } from 'node:fs'
import test from 'node:test'
import { join, resolve } from 'node:path'

const projectRoot = resolve(import.meta.dirname, '../..')
function sourceFiles(directory: string): string[] {
  const paths: string[] = []
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path: string = join(directory, entry.name)
    if (entry.isDirectory()) paths.push(...sourceFiles(path))
    if (entry.isFile() && (entry.name.endsWith('.ets') || entry.name.endsWith('.ts'))) paths.push(path)
  }
  return paths
}

test('single package compiles and targets API 26 while declaring API 22 compatibility', () => {
  const profileFiles: string[] = ['build-profile.example.json5']
  if (existsSync(join(projectRoot, 'build-profile.json5'))) profileFiles.push('build-profile.json5')
  for (const relativePath of profileFiles) {
    const source = readFileSync(join(projectRoot, relativePath), 'utf8')
    assert.match(source, /["']?compileSdkVersion["']?\s*:\s*["']26\.0\.0["']/)
    assert.match(source, /["']?targetSdkVersion["']?\s*:\s*["']26\.0\.0["']/)
    assert.match(source, /["']?compatibleSdkVersion["']?\s*:\s*["']6\.0\.2\(22\)["']/)
  }
  const toolchainCheck = readFileSync(join(projectRoot, 'scripts/check_toolchain.sh'), 'utf8')
  assert.match(toolchainCheck, /compatibleSdkVersion[^\n]+6\\\.0\\\.2\(22\)/)
})

test('API 23 and API 26-only symbols cannot return to the API 22 production path', () => {
  const source = sourceFiles(join(projectRoot, 'entry/src/main/ets'))
    .map((path: string) => readFileSync(path, 'utf8'))
    .join('\n')
  const forbidden: RegExp[] = [
    /import\s+\{\s*uiMaterial\s*\}\s+from\s+'@kit\.ArkUI'/,
    /ImmersiveMaterial/,
    /\.systemMaterial\s*\(/,
    /HUKS_TAG_KEY_SECURITY_LEVEL/,
    /HuksKeySecurityLevel/,
    /HUKS_TAG_AAD\b/,
    /reuseConnections\s*:/,
    /maxRedirects\s*:/
  ]
  for (const pattern of forbidden) assert.doesNotMatch(source, pattern)
})

const devecoHome = process.env.HNA_DEVECO_HOME ?? '/Applications/DevEco-Studio.app'
const sdkRoot = join(devecoHome, 'Contents/sdk/default/openharmony/ets')
const httpDeclaration = join(sdkRoot, 'api/@ohos.net.http.d.ts')
const huksDeclaration = join(sdkRoot, 'api/@ohos.security.huks.d.ts')
const commonDeclaration = join(sdkRoot, 'component/common.d.ts')
const materialDeclaration = join(sdkRoot, 'api/@ohos.arkui.uiMaterial.d.ts')
const localSdkAvailable = [httpDeclaration, huksDeclaration, commonDeclaration, materialDeclaration]
  .every((path: string) => existsSync(path))

function declarationBlock(source: string, symbol: string): string {
  const symbolAt: number = source.indexOf(symbol)
  assert.ok(symbolAt >= 0, `missing SDK declaration for ${symbol}`)
  const commentAt: number = source.lastIndexOf('/**', symbolAt)
  return source.slice(commentAt, symbolAt + symbol.length)
}

test('local API 26 declarations confirm the API 22 replacement boundary', {
  skip: !localSdkAvailable
}, () => {
  const httpSource = readFileSync(httpDeclaration, 'utf8')
  const huksSource = readFileSync(huksDeclaration, 'utf8')
  const commonSource = readFileSync(commonDeclaration, 'utf8')
  const materialSource = readFileSync(materialDeclaration, 'utf8')

  assert.match(declarationBlock(httpSource, 'export enum InterceptorType'), /@since 22/)
  assert.match(declarationBlock(httpSource, 'maxRedirects?: number'), /@since 23/)
  assert.match(declarationBlock(httpSource, 'reuseConnections?: boolean'), /@since 26\.0\.0/)
  assert.match(declarationBlock(huksSource, 'HUKS_TAG_KEY_SECURITY_LEVEL ='), /@since 26\.0\.0/)
  assert.match(declarationBlock(huksSource, 'HUKS_TAG_AE_TAG_LEN ='), /@since 22/)
  assert.match(declarationBlock(commonSource, 'COMPONENT_ULTRA_THIN ='), /@since 11/)
  assert.match(declarationBlock(commonSource, '\n    backgroundBlurStyle(value: BlurStyle'), /@since 9/)
  assert.match(declarationBlock(materialSource, 'class ImmersiveMaterial'), /@since 26\.0\.0/)
})
