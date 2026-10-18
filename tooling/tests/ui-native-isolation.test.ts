import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

test('the entire UI runtime import graph is isolated from c-shared Go/N-API loading', () => {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../entry/src/main/ets')
  const visited = new Set<string>()
  function walk(file: string): void {
    if (visited.has(file)) return
    visited.add(file)
    const source = fs.readFileSync(file, 'utf8')
    assert.doesNotMatch(source, /from\s+['"]libentry\.so['"]|loadNativeModule\s*\(|import\s*\(\s*['"]libentry\.so/, file)
    const imports = source.matchAll(/^import[ \t]+([\s\S]*?)\s+from[ \t]+['"]([^'"]+)['"]/gm)
    for (const item of imports) {
      if (item[1].trim().startsWith('type ')) continue
      if (!item[2].startsWith('.')) continue
      const target = path.resolve(path.dirname(file), item[2])
      const resolved = ['.ets', '.ts', ''].map(ext => target + ext).find(p => fs.existsSync(p) && fs.statSync(p).isFile())
      assert.ok(resolved, `Unresolved import ${item[2]} from ${file}`)
      walk(resolved)
    }
  }
  walk(path.join(root, 'pages/SfaIndex.ets'))
  assert.ok(visited.size > 10, 'test must inspect the transitive graph, including the connection coordinator')
})
