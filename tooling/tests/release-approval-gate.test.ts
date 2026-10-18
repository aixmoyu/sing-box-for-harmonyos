import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import {
  canonical,
  createReleaseApprovalFixture,
  resignFixture,
} from './fixtures/release_approval_fixture.mjs';

const projectRoot = path.resolve(import.meta.dirname, '../..');
const verifier = path.join(projectRoot, 'scripts/verify_release_approval.py');
const schemaFile = path.join(projectRoot, 'schemas/release-approval.schema.json');

function argumentsFor(fixture) {
  const args = [
    verifier,
    '--approval', fixture.approvalFile,
    '--signature', fixture.signatureFile,
    '--trusted-key', fixture.trustedKeyFile,
    '--market', fixture.expected.market,
    '--bundle', fixture.expected.bundleName,
    '--version-code', String(fixture.expected.versionCode),
    '--version-name', fixture.expected.versionName,
    '--git-commit', fixture.expected.gitCommit,
    '--app', fixture.files.app,
    '--release-manifest', fixture.files.releaseManifest,
    '--privacy-policy-zh', fixture.files.privacyPolicyZh,
    '--privacy-policy-en', fixture.files.privacyPolicyEn,
    '--user-agreement-zh', fixture.files.userAgreementZh,
    '--user-agreement-en', fixture.files.userAgreementEn,
    '--corresponding-source', fixture.files.correspondingSource,
    '--sbom', fixture.files.sbom,
    '--security-report', fixture.files.securityReport,
  ];
  for (const kind of fixture.evidenceKinds) {
    args.push('--evidence', `${kind}=${fixture.files[`evidence:${kind}`]}`);
  }
  return args;
}

function run(fixture, replacements = {}) {
  const args = argumentsFor(fixture);
  for (const [flag, value] of Object.entries(replacements)) {
    const index = args.indexOf(flag);
    assert.notEqual(index, -1, `unknown argument replacement: ${flag}`);
    args[index + 1] = String(value);
  }
  return spawnSync('python3', args, { encoding: 'utf8' });
}

function withFixture(t, market = 'overseas') {
  const root = fs.mkdtempSync('/tmp/hna-release-approval.');
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  return createReleaseApprovalFixture(root, market);
}

test('approval schema is strict and documents all signed release bindings', () => {
  const schema = JSON.parse(fs.readFileSync(schemaFile, 'utf8'));
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.properties.market.enum, ['cn', 'overseas']);
  assert.deepEqual(schema.properties.artifacts.required.sort(), [
    'app', 'correspondingSource', 'privacyPolicyEn', 'privacyPolicyZh',
    'releaseManifest', 'sbom', 'securityReport', 'userAgreementEn',
    'userAgreementZh',
  ].sort());
  assert.deepEqual(schema.properties.evidence.items.required.sort(), [
    'effectiveAt', 'expiresAt', 'issuer', 'kind', 'reference', 'sha256',
  ].sort());
});

test('valid detached approvals verify for both exact market evidence sets', (t) => {
  for (const market of ['cn', 'overseas']) {
    const fixture = withFixture(t, market);
    const result = run(fixture);
    assert.equal(result.status, 0, result.stderr);
    const output = JSON.parse(result.stdout);
    assert.equal(output.verified, true);
    assert.equal(output.market, market);
    assert.deepEqual(output.evidenceKinds, [...fixture.evidenceKinds].sort());
  }
});

test('tampering, wrong package binding, market replay, and an untrusted key fail closed', (t) => {
  const fixture = withFixture(t);

  for (const artifact of [
    'app', 'releaseManifest', 'privacyPolicyZh', 'privacyPolicyEn',
    'userAgreementZh', 'userAgreementEn', 'correspondingSource', 'sbom',
    'securityReport',
  ]) {
    const original = fs.readFileSync(fixture.files[artifact]);
    fs.appendFileSync(fixture.files[artifact], 'tampered');
    assert.notEqual(run(fixture).status, 0, `tampered ${artifact} must fail`);
    fs.writeFileSync(fixture.files[artifact], original);
  }

  assert.notEqual(run(fixture, { '--git-commit': 'a'.repeat(40) }).status, 0);
  assert.notEqual(run(fixture, { '--bundle': 'com.other.application' }).status, 0);
  assert.notEqual(run(fixture, { '--version-code': 1000001 }).status, 0);
  assert.notEqual(run(fixture, { '--version-name': '0.1.1' }).status, 0);
  assert.notEqual(run(fixture, { '--market': 'cn' }).status, 0, 'overseas approval must not replay in CN');

  const other = withFixture(t);
  assert.notEqual(run(fixture, { '--trusted-key': other.trustedKeyFile }).status, 0);

  fixture.approval.application.versionName = '0.1.1';
  fs.writeFileSync(fixture.approvalFile, canonical(fixture.approval));
  assert.notEqual(run(fixture).status, 0, 'approval edits without a new signature must fail');
});

test('expired evidence and placeholders remain invalid even with a valid signature', (t) => {
  const fixture = withFixture(t);
  fixture.approval.evidence[0].expiresAt = '2020-01-01T00:00:00Z';
  resignFixture(fixture);
  assert.notEqual(run(fixture).status, 0);

  const placeholder = withFixture(t);
  placeholder.approval.evidence[0].reference = 'xxxxxxxx';
  resignFixture(placeholder);
  assert.notEqual(run(placeholder).status, 0);

  const blank = withFixture(t);
  blank.approval.evidence[0].issuer = '   ';
  resignFixture(blank);
  assert.notEqual(run(blank).status, 0);

  const expiredApproval = withFixture(t);
  expiredApproval.approval.validity.expiresAt = '2020-01-01T00:00:00Z';
  resignFixture(expiredApproval);
  assert.notEqual(run(expiredApproval).status, 0);

  const futureIssued = withFixture(t);
  const future = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString().replace(/\.\d{3}Z$/, 'Z');
  futureIssued.approval.validity.issuedAt = future;
  futureIssued.approval.validity.expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
    .toISOString().replace(/\.\d{3}Z$/, 'Z');
  resignFixture(futureIssued);
  const futureResult = run(futureIssued);
  assert.notEqual(futureResult.status, 0);
  assert.match(futureResult.stderr, /issuedAt is unacceptably far in the future/);

  const expiredKey = withFixture(t);
  const key = JSON.parse(fs.readFileSync(expiredKey.trustedKeyFile, 'utf8'));
  key.expiresAt = '2020-01-01T00:00:00Z';
  fs.writeFileSync(expiredKey.trustedKeyFile, canonical(key));
  assert.notEqual(run(expiredKey).status, 0);
});

test('missing, duplicated, or wrong evidence bytes fail closed', (t) => {
  const fixture = withFixture(t);
  const args = argumentsFor(fixture);
  const firstEvidence = args.indexOf('--evidence');
  args.splice(firstEvidence, 2);
  assert.notEqual(spawnSync('python3', args, { encoding: 'utf8' }).status, 0);

  fs.appendFileSync(fixture.files[`evidence:${fixture.evidenceKinds[0]}`], 'tampered');
  assert.notEqual(run(fixture).status, 0);
});

test('signature envelope cannot be relabeled or replaced', (t) => {
  const fixture = withFixture(t);
  const envelope = JSON.parse(fs.readFileSync(fixture.signatureFile, 'utf8'));
  envelope.keyId = 'untrusted-release-key';
  fs.writeFileSync(fixture.signatureFile, canonical(envelope));
  assert.notEqual(run(fixture).status, 0);

  const replacement = withFixture(t);
  fs.copyFileSync(replacement.signatureFile, fixture.signatureFile);
  assert.notEqual(run(fixture).status, 0);
});

test('repository fixtures contain no persisted private key or formal approval', () => {
  const fixtureSource = fs.readFileSync(
    path.join(projectRoot, 'tooling/tests/fixtures/release_approval_fixture.mjs'),
    'utf8',
  );
  assert.match(fixtureSource, /generateKeyPairSync\('ed25519'\)/);
  assert.doesNotMatch(fixtureSource, /BEGIN (?:OPENSSH |ED25519 )?PRIVATE KEY/);
  assert.equal(fs.existsSync(path.join(projectRoot, 'release-approval.json')), false);
  assert.equal(fs.existsSync(path.join(projectRoot, 'release-approval.sig.json')), false);
  assert.doesNotMatch(fs.readFileSync(verifier, 'utf8'), /from cryptography|import cryptography/);
  assert.match(fs.readFileSync(verifier, 'utf8'), /openssl.*pkeyutl/s);
});
