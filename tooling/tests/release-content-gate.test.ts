import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const projectRoot = path.resolve(import.meta.dirname, '../..');
const verifier = path.join(projectRoot, 'scripts/release_content_gate.py');
const probeFixture = path.join(projectRoot, 'tooling/tests/fixtures/release_content_probe_fixture.py');
const buildScript = fs.readFileSync(path.join(projectRoot, 'scripts/build_release_app.sh'), 'utf8');
const preflight = fs.readFileSync(path.join(projectRoot, 'scripts/release_preflight.sh'), 'utf8');
const verifierSource = fs.readFileSync(verifier, 'utf8');

function run(command: string, args: string[], cwd?: string) {
  return spawnSync(command, args, { cwd, encoding: 'utf8' });
}

function write(root: string, relative: string, body = `fixture ${relative}\n`) {
  const target = path.join(root, relative);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, body);
}

function makeSourceFixture(): { root: string; commit: string } {
  const root = fs.mkdtempSync('/tmp/hna-source-gate.');
  const required = [
    'LICENSE',
    'THIRD_PARTY_NOTICES.md',
    'AppScope/app.json5',
    'build-profile.example.json5',
    'hvigorfile.ts',
    'oh-package.json5',
    'entry/build-profile.json5',
    'entry/hvigorfile.ts',
    'entry/src/main/module.json5',
    'entry/src/main/ets/App.ets',
    'core/go/go.mod',
    'core/go/go.sum',
    'core/go/main.go',
    'scripts/build_core.sh',
    'scripts/build_ohos_go.sh',
    'scripts/core_smoke_test.sh',
    'scripts/core_vendor.py',
    'scripts/prepare_core_upgrade.sh',
    'scripts/release_content_gate.py',
    'scripts/verify_build_toolchain.py',
    'scripts/verify_core_vendor.sh',
    'third_party/core-lock.json',
    'third_party/build-toolchain-lock.json',
    'third_party/CORE_UPGRADE.md',
    'third_party/patches/ohos-go.patch',
    'third_party/sing-box/LICENSE',
    'third_party/sing-box/go.mod',
    'third_party/gvisor/LICENSE',
    'third_party/gvisor/go.mod',
    'third_party/ohos-golang-go-1.24/LICENSE',
    'third_party/ohos-golang-go-1.24/src/make.bash',
  ];
  for (const relative of required) write(root, relative);
  assert.equal(run('git', ['init', '-q'], root).status, 0);
  assert.equal(run('git', ['config', 'user.name', 'Release Test'], root).status, 0);
  assert.equal(run('git', ['config', 'user.email', 'release-test@invalid.test'], root).status, 0);
  assert.equal(run('git', ['add', '.'], root).status, 0);
  const committed = spawnSync('git', ['commit', '-qm', 'fixture'], {
    cwd: root,
    encoding: 'utf8',
    env: {
      ...process.env,
      GIT_AUTHOR_DATE: '2026-01-01T00:00:00Z',
      GIT_COMMITTER_DATE: '2026-01-01T00:00:00Z',
    },
  });
  assert.equal(committed.status, 0, committed.stderr);
  const commit = run('git', ['rev-parse', 'HEAD'], root).stdout.trim();
  assert.match(commit, /^[0-9a-f]{40}$/);
  return { root, commit };
}

test('approved policy bytes reject templates and accept a substantive final UTF-8 body', () => {
  const root = fs.mkdtempSync('/tmp/hna-policy-gate.');
  try {
    const approved = path.join(root, 'approved.txt');
    fs.writeFileSync(approved, 'Final privacy policy. '.repeat(32));
    const accepted = run('python3', [verifier, 'policy-file', '--approved-file', approved]);
    assert.equal(accepted.status, 0, accepted.stderr);
    const metadata = JSON.parse(accepted.stdout);
    assert.equal(metadata.sizeBytes, fs.statSync(approved).size);
    assert.equal(
      metadata.sha256,
      crypto.createHash('sha256').update(fs.readFileSync(approved)).digest('hex'),
    );

    const template = path.join(root, 'template.txt');
    fs.writeFileSync(template, `${'Final privacy policy. '.repeat(20)}\n[TODO: operator]\n`);
    const rejected = run('python3', [verifier, 'policy-file', '--approved-file', template]);
    assert.notEqual(rejected.status, 0);
    assert.match(rejected.stderr, /RELEASE_CONTENT_BLOCKED:/);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('corresponding source archive is deterministic and commit-bound', () => {
  const fixture = makeSourceFixture();
  try {
    const first = path.join(fixture.root, 'first.tar.gz');
    const second = path.join(fixture.root, 'second.tar.gz');
    const args = [
      verifier,
      'create-source',
      '--repo', fixture.root,
      '--commit', fixture.commit,
      '--version', '1.2.3',
    ];
    const createdFirst = run('python3', [...args, '--output', first]);
    assert.equal(createdFirst.status, 0, createdFirst.stderr);
    write(fixture.root, 'core/go/main.go', 'uncommitted mutation\n');
    const createdSecond = run('python3', [...args, '--output', second]);
    assert.equal(createdSecond.status, 0, createdSecond.stderr);
    assert.deepEqual(fs.readFileSync(first), fs.readFileSync(second));
    const metadata = JSON.parse(createdFirst.stdout);
    assert.equal(metadata.gitCommit, fixture.commit);
    assert.equal(metadata.sha256, crypto.createHash('sha256').update(fs.readFileSync(first)).digest('hex'));
    assert.equal(metadata.format, 'tar+gzip');
    assert.equal(metadata.prefix, `HarmonyOS-Network-Assistant-1.2.3-${fixture.commit}/`);

    const listed = run('tar', ['-tzf', first]);
    assert.equal(listed.status, 0, listed.stderr);
    assert.match(listed.stdout, /third_party\/sing-box\/go\.mod/);
    assert.match(listed.stdout, /third_party\/gvisor\/go\.mod/);
    assert.match(listed.stdout, /third_party\/patches\/ohos-go\.patch/);
    assert.match(listed.stdout, /third_party\/build-toolchain-lock\.json/);
    assert.match(listed.stdout, /scripts\/build_core\.sh/);
    assert.match(listed.stdout, /LICENSE/);
  } finally {
    fs.rmSync(fixture.root, { recursive: true, force: true });
  }
});

test('public content fetch is fail-closed for private or placeholder hosts', () => {
  const root = fs.mkdtempSync('/tmp/hna-url-gate.');
  try {
    const expected = path.join(root, 'expected.txt');
    fs.writeFileSync(expected, 'Expected policy. '.repeat(32));
    for (const url of ['https://127.0.0.1/policy', 'https://example.com/policy']) {
      const result = run('python3', [
        verifier,
        'verify-url',
        '--kind', 'policy',
        '--url', url,
        '--expected-file', expected,
      ]);
      assert.notEqual(result.status, 0, url);
      assert.match(result.stderr, /RELEASE_CONTENT_BLOCKED:/);
    }
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
  assert.match(verifierSource, /Accept-Encoding/);
  assert.match(verifierSource, /identity/);
  assert.match(verifierSource, /address\.is_global/);
  assert.match(verifierSource, /MAX_REDIRECTS = 5/);
  assert.match(verifierSource, /POLICY_MAX_BYTES/);
  assert.match(verifierSource, /SOURCE_MAX_BYTES/);
  assert.match(verifierSource, /public HTTPS content has an unapproved MIME type/);
  assert.doesNotMatch(verifierSource, /CERT_NONE|check_hostname\s*=\s*False/);
});

test('support URL probe accepts bounded text 2xx without requiring reviewed local bytes', () => {
  const accepted = run('python3', [probeFixture, verifier, 'success']);
  assert.equal(accepted.status, 0, accepted.stderr);
  const metadata = JSON.parse(accepted.stdout);
  assert.equal(metadata.status, 201);
  assert.equal(metadata.contentType, 'text/html');
  assert.equal(metadata.sizeBytes, 28);

  for (const scenario of ['bad-mime', 'oversized-header', 'compressed', 'empty', 'redirect-private']) {
    const rejected = run('python3', [probeFixture, verifier, scenario]);
    assert.notEqual(rejected.status, 0, scenario);
    assert.match(rejected.stderr, /RELEASE_CONTENT_BLOCKED:/, scenario);
  }

  for (const url of ['https://127.0.0.1/support', 'http://support.harmonynet.app/help']) {
    const rejected = run('python3', [verifier, 'probe-url', '--url', url]);
    assert.notEqual(rejected.status, 0, url);
    assert.match(rejected.stderr, /RELEASE_CONTENT_BLOCKED:/, url);
  }

  assert.match(verifierSource, /http\.client\.HTTPSConnection\([\s\S]*?ssl\.create_default_context\(\)/);
  assert.match(verifierSource, /connection\._create_connection = pinned_create_connection/);
  assert.match(verifierSource, /response\.status < 200 or response\.status >= 300/);
  assert.match(verifierSource, /SUPPORT_PAGE_MAX_BYTES = 2 \* 1024 \* 1024/);
  assert.match(verifierSource, /SUPPORT_PAGE_TOTAL_TIMEOUT_SECONDS = 30/);
});

test('formal build and preflight bind policies and complete source inside signed provenance', () => {
  for (const variable of [
    'HNA_PRIVACY_POLICY_ZH',
    'HNA_PRIVACY_POLICY_EN',
    'HNA_USER_AGREEMENT_ZH',
    'HNA_USER_AGREEMENT_EN',
    'HNA_PRIVACY_URL_EN',
    'HNA_USER_AGREEMENT_URL_EN',
  ]) {
    assert.match(buildScript, new RegExp(variable));
    assert.match(preflight, new RegExp(variable));
  }
  assert.match(buildScript, /policyDocuments: policyBindings\.documents/);
  assert.match(buildScript, /source: \{ gitCommit, treeClean: true, correspondingArchive \}/);
  assert.match(buildScript, /public GPL source URL serves the deterministic complete source archive/);
  assert.match(buildScript, /"\$source_archive_sha" "\$source_artifact_name"/);
  assert.match(preflight, /release policy-body binding mismatch/);
  assert.match(preflight, /signed release policy-body binding mismatch/);
  assert.match(preflight, /release corresponding-source binding mismatch/);
  assert.match(preflight, /deterministically reproduces from the current Git commit/);
  assert.match(preflight, /published GPL source URL serves the exact deterministic sibling archive/);
  assert.match(preflight, /release_content_gate\.py probe-url/);
  assert.match(preflight, /DNS-pinned public redirect chain/);
  assert.doesNotMatch(preflight, /curl\s/);
});
