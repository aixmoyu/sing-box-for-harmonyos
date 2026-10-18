import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import test from 'node:test';

const projectRoot = resolve(import.meta.dirname, '../..');
const verifier = join(projectRoot, 'scripts/verify_build_toolchain.py');
const lockPath = join(projectRoot, 'third_party/build-toolchain-lock.json');
const devecoContents = '/Applications/DevEco-Studio.app/Contents';

function bootstrapRoot(): string {
  return execFileSync('go', ['env', 'GOROOT'], { encoding: 'utf8' }).trim();
}

test('reviewed bootstrap Go and DevEco inputs match their exact lock', () => {
  const result = execFileSync(
    'python3',
    [verifier, 'all', '--goroot', bootstrapRoot(), '--contents', devecoContents],
    { cwd: projectRoot, encoding: 'utf8' }
  );
  assert.match(result, /BOOTSTRAP GO TOOLCHAIN VERIFIED/);
  assert.match(result, /DEVECO BUILD TOOLCHAIN VERIFIED/);
});

test('build toolchain lock records an official bootstrap archive identity', () => {
  const lock = JSON.parse(readFileSync(lockPath, 'utf8'));
  assert.equal(lock.schema_version, 1);
  assert.equal(lock.host.system, 'Darwin');
  assert.equal(lock.host.machine, 'arm64');
  assert.match(lock.bootstrap_go.official_archive_url, /^https:\/\/go\.dev\/dl\/go\d+\.\d+\.\d+\.darwin-arm64\.tar\.gz$/);
  assert.match(lock.bootstrap_go.official_archive_sha256, /^[0-9a-f]{64}$/);
  assert.equal(lock.deveco.sdk_api_version, 26);
  assert.match(lock.deveco.sdk_version, /^26\./);
  assert.equal(typeof lock.deveco.sdk_release_type, 'string');
  assert.match(
    lock.deveco.files['sdk/default/openharmony/toolchains/lib/app_unpacking_tool.jar'],
    /^[0-9a-f]{64}$/,
  );
  assert.match(lock.deveco.trees['tools/hvigor'], /^[0-9a-f]{64}$/);
  assert.match(lock.deveco.trees['tools/ohpm'], /^[0-9a-f]{64}$/);
});

test('build toolchain verifier rejects a drifted executable hash', () => {
  const directory = mkdtempSync(join(tmpdir(), 'hna-build-toolchain-lock-test-'));
  const lock = JSON.parse(readFileSync(lockPath, 'utf8'));
  lock.deveco.files['tools/node/bin/node'] = '0'.repeat(64);
  const candidate = join(directory, 'build-toolchain-lock.json');
  writeFileSync(candidate, `${JSON.stringify(lock, null, 2)}\n`);

  const result = spawnSync(
    'python3',
    [verifier, '--lock', candidate, 'deveco', '--contents', devecoContents],
    { cwd: projectRoot, encoding: 'utf8' }
  );
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /deveco file drift: tools\/node\/bin\/node/);
});

test('build toolchain verifier rejects drift in executed Hvigor implementation', () => {
  const directory = mkdtempSync(join(tmpdir(), 'hna-build-toolchain-tree-test-'));
  const lock = JSON.parse(readFileSync(lockPath, 'utf8'));
  lock.deveco.trees['tools/hvigor'] = '0'.repeat(64);
  const candidate = join(directory, 'build-toolchain-lock.json');
  writeFileSync(candidate, `${JSON.stringify(lock, null, 2)}\n`);

  const result = spawnSync(
    'python3',
    [verifier, '--lock', candidate, 'deveco', '--contents', devecoContents],
    { cwd: projectRoot, encoding: 'utf8' }
  );
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /deveco directory drift: tools\/hvigor/);
});

test('build toolchain verifier rejects drift in the official App Pack unpacker', () => {
  const directory = mkdtempSync(join(tmpdir(), 'hna-build-toolchain-unpacker-test-'));
  const lock = JSON.parse(readFileSync(lockPath, 'utf8'));
  lock.deveco.files['sdk/default/openharmony/toolchains/lib/app_unpacking_tool.jar'] =
    '0'.repeat(64);
  const candidate = join(directory, 'build-toolchain-lock.json');
  writeFileSync(candidate, `${JSON.stringify(lock, null, 2)}\n`);

  const result = spawnSync(
    'python3',
    [verifier, '--lock', candidate, 'deveco', '--contents', devecoContents],
    { cwd: projectRoot, encoding: 'utf8' }
  );
  assert.notEqual(result.status, 0);
  assert.match(result.stderr,
    /deveco file drift: sdk\/default\/openharmony\/toolchains\/lib\/app_unpacking_tool\.jar/);
});

test('every native and formal build entry point verifies the reviewed toolchain', () => {
  const buildOhosGo = readFileSync(join(projectRoot, 'scripts/build_ohos_go.sh'), 'utf8');
  const buildCore = readFileSync(join(projectRoot, 'scripts/build_core.sh'), 'utf8');
  const smoke = readFileSync(join(projectRoot, 'scripts/core_smoke_test.sh'), 'utf8');
  const debugHap = readFileSync(join(projectRoot, 'scripts/build_hap.sh'), 'utf8');
  const release = readFileSync(join(projectRoot, 'scripts/build_release_app.sh'), 'utf8');

  assert.match(buildOhosGo, /verify_build_toolchain\.py" bootstrap/);
  assert.match(buildCore, /verify_build_toolchain\.py" deveco/);
  assert.match(smoke, /verify_build_toolchain\.py" deveco/);
  assert.match(debugHap, /verify_build_toolchain\.py" all/);
  assert.match(debugHap, /HNA_DEVECO_HOME/);
  assert.match(debugHap, /scripts\/build_ohos_go\.sh/);
  assert.match(debugHap, /scripts\/verify_core_vendor\.sh/);
  assert.match(debugHap, /scripts\/core_smoke_test\.sh/);
  assert.match(debugHap, /scripts\/build_core\.sh/);
  assert.match(debugHap, /packaged debug core differs from this build's stripped native core/);
  assert.match(debugHap, /staged debug core differs from the freshly rebuilt native core/);
  assert.match(release, /verify_build_toolchain\.py" all/);
});
