import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const projectRoot = path.resolve(import.meta.dirname, '../..');
const generator = path.join(projectRoot, 'scripts/generate_release_sbom.py');
const verifier = path.join(projectRoot, 'scripts/verify_release_security.py');
const TEST_NOW = '2026-08-12T12:00:00Z';

function run(command: string, args: string[], cwd?: string) {
  return spawnSync(command, args, { cwd, encoding: 'utf8' });
}

function canonical(value: unknown): string {
  return `${JSON.stringify(value, Object.keys(value as object).sort())}\n`;
}

// JSON.stringify's replacer array is not recursive. This helper exactly matches
// the Python gate's recursive sort_keys canonicalization.
function stable(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).sort(([a], [b]) => a.localeCompare(b)).map(([key, item]) => [key, stable(item)]));
  }
  return value;
}

function canonicalBytes(value: unknown): Buffer {
  return Buffer.from(`${JSON.stringify(stable(value))}\n`);
}

function write(root: string, relative: string, content: string | Buffer) {
  const target = path.join(root, relative);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, content);
}

function fixtureCoreLock() {
  return {
    schema_version: 2,
    sing_box: {
      version: 'v1.0.0', commit: '1'.repeat(40), license: 'GPL-3.0-or-later',
      vendor_tree_sha256: '1'.repeat(64), patch_sha256: '2'.repeat(64),
    },
    gvisor: {
      module: 'github.com/sagernet/gvisor', version: 'v0.0.1', commit: '2'.repeat(40),
      license: 'Apache-2.0', vendor_tree_sha256: '3'.repeat(64), patch_sha256: '4'.repeat(64),
    },
    ohos_go: {
      version: 'go1.24.13', source_tree_sha256: '5'.repeat(64),
      openharmony_port_commit: '3'.repeat(40), upstream_go_commit: '4'.repeat(40),
      replay_patch_sha256: '6'.repeat(64),
    },
  };
}

function makeGeneratorFixture() {
  const root = fs.mkdtempSync('/tmp/hna-sbom-fixture.');
  const inputs = path.join(root, 'inputs');
  write(root, 'core/go/go.mod', `module example.test/core\n\ngo 1.24.7\n\nrequire (\n example.test/direct v1.2.3\n github.com/sagernet/sing-box v1.0.0\n example.test/transitive v2.0.0 // indirect\n github.com/sagernet/gvisor v0.0.1 // indirect\n)\n\nreplace github.com/sagernet/sing-box => ../../third_party/sing-box\nreplace github.com/sagernet/gvisor => ../../third_party/gvisor\n`);
  const moduleDigest = Buffer.alloc(32, 1).toString('base64');
  const modDigest = Buffer.alloc(32, 2).toString('base64');
  write(root, 'core/go/go.sum', `example.test/direct v1.2.3 h1:${moduleDigest}\nexample.test/direct v1.2.3/go.mod h1:${modDigest}\n`);
  write(root, 'third_party/core-lock.json', `${JSON.stringify(fixtureCoreLock(), null, 2)}\n`);
  write(root, 'oh-package.json5', JSON.stringify({ devDependencies: { '@ohos/test': '1.0.0' } }));
  write(root, 'entry/oh-package.json5', JSON.stringify({ dependencies: { 'libentry.so': 'file:local' } }));
  write(root, 'AppScope/app.json5', JSON.stringify({ app: {
    bundleName: 'com.harmonynet.assistant', versionName: '0.1.0', versionCode: 1000000,
  } }));
  write(root, 'oh-package-lock.json5', JSON.stringify({ packages: {
    '@ohos/test@1.0.0': { name: '@ohos/test', version: '1.0.0', integrity: 'sha512-test', resolved: 'https://ohpm.invalid/test.har', registryType: 'ohpm' },
  } }));
  write(root, 'entry/oh-package-lock.json5', JSON.stringify({ packages: {
    'libentry.so@local': { name: 'libentry.so', version: '1.0.0', resolved: 'src/main/cpp/types/libentry', registryType: 'local' },
  } }));
  write(inputs, 'go-mod-edit.json', JSON.stringify({
    Module: { Path: 'example.test/core' }, Go: '1.24.7',
    Require: [
      { Path: 'example.test/direct', Version: 'v1.2.3' },
      { Path: 'github.com/sagernet/sing-box', Version: 'v1.0.0' },
      { Path: 'example.test/transitive', Version: 'v2.0.0', Indirect: true },
      { Path: 'github.com/sagernet/gvisor', Version: 'v0.0.1', Indirect: true },
    ],
    Replace: [
      { Old: { Path: 'github.com/sagernet/sing-box' }, New: { Path: '../../third_party/sing-box' } },
      { Old: { Path: 'github.com/sagernet/gvisor' }, New: { Path: '../../third_party/gvisor' } },
    ],
  }));
  write(inputs, 'go-mod-graph.txt', [
    'example.test/core example.test/direct@v1.2.3',
    'example.test/core github.com/sagernet/sing-box@v1.0.0',
    'example.test/core github.com/sagernet/gvisor@v0.0.1',
    'example.test/direct@v1.2.3 example.test/transitive@v2.0.0',
  ].join('\n') + '\n');
  write(inputs, 'core-build-info.txt', [
    'core-binary.bin: go1.24.13',
    '\tpath\texample.test/core',
    '\tmod\texample.test/core\t(devel)',
    `\tdep\texample.test/direct\tv1.2.3\th1:${moduleDigest}`,
    '\tdep\tgithub.com/sagernet/sing-box\tv1.0.0',
    '\t=>\t../../third_party/sing-box\t(devel)',
    '\tdep\tgithub.com/sagernet/gvisor\tv0.0.1',
    '\t=>\t../../third_party/gvisor\t(devel)',
    '\tbuild\t-tags=with_gvisor,with_quic',
    '\tbuild\tGOARCH=arm64',
    '\tbuild\tGOOS=openharmony',
  ].join('\n') + '\n');
  write(inputs, 'core-binary.bin', Buffer.from('offline fixture native core'));
  return { root, inputs };
}

test('SBOM generation is deterministic and distinguishes direct, transitive, build, and runtime scopes', () => {
  const fixture = makeGeneratorFixture();
  try {
    const first = path.join(fixture.root, 'first.cdx.json');
    const second = path.join(fixture.root, 'second.cdx.json');
    const common = [generator, '--repo', fixture.root, '--go-tool', '/usr/bin/true', '--fixture-input-dir', fixture.inputs, '--allow-fixture-input'];
    const generated = run('python3', [...common, '--output', first]);
    assert.equal(generated.status, 0, generated.stderr);
    const repeated = run('python3', [...common, '--output', second]);
    assert.equal(repeated.status, 0, repeated.stderr);
    assert.deepEqual(fs.readFileSync(first), fs.readFileSync(second));
    const sbom = JSON.parse(fs.readFileSync(first, 'utf8'));
    assert.equal(sbom.bomFormat, 'CycloneDX');
    assert.equal(sbom.specVersion, '1.6');
    const component = (needle: string) => sbom.components.find((item: any) => item['bom-ref'].includes(needle));
    const scope = (item: any) => item.properties.find((property: any) => property.name === 'hna:dependencyScopes').value;
    assert.equal(scope(component('example.test/direct')), 'build,direct,runtime');
    assert.equal(scope(component('example.test/transitive')), 'build,transitive');
    assert.equal(scope(component('openharmony-go')), 'build');
    assert.equal(scope(component('libentry.so')), 'runtime');
    assert.equal(scope(component('%40ohos/test')), 'build');
    assert.equal(sbom.metadata.properties.find((item: any) => item.name === 'hna:fixtureInput').value, 'true');
    assert.match(fs.readFileSync(first, 'utf8'), /coreBuildInfo/);
    assert.equal(sbom.metadata.component.version, '0.1.0');
    assert.match(fs.readFileSync(first, 'utf8'), /nativeCoreBuildInfoSha256/);
    assert.doesNotMatch(fs.readFileSync(first, 'utf8'), /coreBinary/);
  } finally {
    fs.rmSync(fixture.root, { recursive: true, force: true });
  }
});

test('SBOM generation fails when compiled BuildInfo names a module absent from the declared graph', () => {
  const fixture = makeGeneratorFixture();
  try {
    fs.appendFileSync(path.join(fixture.inputs, 'core-build-info.txt'), '\tdep\texample.test/undeclared\tv9.9.9\th1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n');
    const result = run('python3', [generator, '--repo', fixture.root, '--go-tool', '/usr/bin/true', '--fixture-input-dir', fixture.inputs,
      '--allow-fixture-input', '--output', path.join(fixture.root, 'bad.json')]);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /compiled module is absent/);
  } finally {
    fs.rmSync(fixture.root, { recursive: true, force: true });
  }
});

function makeSecurityFixture() {
  const root = fs.mkdtempSync('/tmp/hna-security-fixture.');
  const privateKey = path.join(root, 'test-private.pem');
  const publicKey = path.join(root, 'test-public.pem');
  assert.equal(run('openssl', ['genpkey', '-algorithm', 'Ed25519', '-out', privateKey]).status, 0);
  assert.equal(run('openssl', ['pkey', '-in', privateKey, '-pubout', '-out', publicKey]).status, 0);
  const publicKeyObject = crypto.createPublicKey(fs.readFileSync(publicKey));
  const publicKeyDer = publicKeyObject.export({ type: 'spki', format: 'der' });
  const rawPublicKey = publicKeyDer.subarray(publicKeyDer.length - 32);
  const digest = (value: string) => crypto.createHash('sha256').update(`offline-fixture-${value}`).digest('hex');
  const rootRef = 'pkg:generic/harmonyos/test@1.0.0';
  const moduleRef = 'pkg:golang/example.test/direct@v1.2.3';
  const metadataProperties = ['AppScope/app.json5', 'core/go/go.mod', 'core/go/go.sum', 'third_party/core-lock.json', 'oh-package-lock.json5',
    'entry/oh-package-lock.json5', 'coreBuildInfo'].map((name, index) => ({ name: `hna:inputSha256:${name}`, value: digest(String(index + 1)) }));
  metadataProperties.push({ name: 'hna:fixtureInput', value: 'false' });
  const sbom: any = {
    bomFormat: 'CycloneDX', specVersion: '1.6', serialNumber: 'urn:uuid:11111111-2222-5333-8444-555555555555', version: 1,
    metadata: { component: { type: 'application', 'bom-ref': rootRef, name: 'Test', version: '1.0.0', properties: [{ name: 'hna:dependencyScopes', value: 'runtime' }] }, properties: metadataProperties },
    components: [{ type: 'library', 'bom-ref': moduleRef, name: 'direct', version: 'v1.2.3', properties: [{ name: 'hna:dependencyScopes', value: 'build,direct,runtime' }] }],
    dependencies: [{ ref: rootRef, dependsOn: [moduleRef] }, { ref: moduleRef, dependsOn: [] }],
  };
  const sbomPath = path.join(root, 'release.cdx.json');
  fs.writeFileSync(sbomPath, canonicalBytes(sbom));
  const policy: any = {
    schemaVersion: 1, maxReportAgeDays: 7, maxDatabaseAgeDays: 7, maxFutureSkewMinutes: 5, maxWaiverDays: 90,
    blockSeverities: ['critical', 'high'], allowCriticalWaivers: false,
    allowedLicenseExpressions: ['GPL-3.0-or-later', 'MIT'], deniedLicenseExpressions: ['AGPL-3.0-only'],
    trustedKeys: [{ id: 'offline-test-key', roles: ['release-security'], publicKeyBase64: rawPublicKey.toString('base64'),
      sha256: crypto.createHash('sha256').update(rawPublicKey).digest('hex'),
      notBefore: '2026-08-01T00:00:00Z', notAfter: '2026-09-01T00:00:00Z' }],
  };
  const policyPath = path.join(root, 'policy.json');
  fs.writeFileSync(policyPath, JSON.stringify(policy));
  const refs = [rootRef, moduleRef];
  const report: any = {
    schemaVersion: 1, kind: 'hna.release-security-scan', generatedAt: '2026-08-12T11:30:00Z',
    sbomSha256: crypto.createHash('sha256').update(fs.readFileSync(sbomPath)).digest('hex'), sbomSerialNumber: sbom.serialNumber,
    componentCount: refs.length, scanner: { name: 'Offline Fixture Scanner', version: '1.2.3' },
    vulnerabilityDatabase: { name: 'Offline Fixture Advisory DB', version: 'snapshot-20260812', updatedAt: '2026-08-12T10:00:00Z', sha256: digest('a') },
    coverage: { mode: 'all-components', vulnerabilityComponentRefs: refs, licenseComponentRefs: refs },
    licenseAnalysis: [{ componentRef: rootRef, expression: 'GPL-3.0-or-later' }, { componentRef: moduleRef, expression: 'MIT' }],
    findings: [], waivers: [],
  };
  const sign = (value: any) => {
    delete value.signature;
    delete value.payloadSha256;
    const payload = canonicalBytes(value);
    value.payloadSha256 = crypto.createHash('sha256').update(payload).digest('hex');
    const payloadPath = path.join(root, 'payload.json');
    const signaturePath = path.join(root, 'signature.bin');
    fs.writeFileSync(payloadPath, payload);
    const signed = run('openssl', ['pkeyutl', '-sign', '-inkey', privateKey, '-rawin', '-in', payloadPath, '-out', signaturePath]);
    assert.equal(signed.status, 0, signed.stderr);
    value.signature = { algorithm: 'Ed25519', keyId: 'offline-test-key', value: fs.readFileSync(signaturePath).toString('base64') };
    const reportPath = path.join(root, 'report.json');
    fs.writeFileSync(reportPath, JSON.stringify(value));
    return reportPath;
  };
  return { root, sbomPath, policyPath, report, sign };
}

function verifyFixture(fixture: ReturnType<typeof makeSecurityFixture>) {
  return run('python3', [verifier, '--sbom', fixture.sbomPath, '--security-report', fixture.sign(fixture.report), '--policy', fixture.policyPath,
    '--now', TEST_NOW, '--allow-test-time']);
}

test('trusted signed scan evidence covering the exact SBOM passes without claiming that the gate scanned it', () => {
  const fixture = makeSecurityFixture();
  try {
    const result = verifyFixture(fixture);
    assert.equal(result.status, 0, result.stderr);
    const output = JSON.parse(result.stdout);
    assert.equal(output.status, 'verified');
    assert.match(output.meaning, /did not perform a scan/);
  } finally { fs.rmSync(fixture.root, { recursive: true, force: true }); }
});

test('a report changed after signing is rejected as tampered evidence', () => {
  const fixture = makeSecurityFixture();
  try {
    const reportPath = fixture.sign(fixture.report);
    const tampered = JSON.parse(fs.readFileSync(reportPath, 'utf8'));
    tampered.scanner.version = '9.9.9-tampered';
    fs.writeFileSync(reportPath, JSON.stringify(tampered));
    const result = run('python3', [verifier, '--sbom', fixture.sbomPath, '--security-report', reportPath,
      '--policy', fixture.policyPath, '--now', TEST_NOW, '--allow-test-time']);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /payload digest mismatch|signature verification failed/);
  } finally { fs.rmSync(fixture.root, { recursive: true, force: true }); }
});

test('tampering, incomplete coverage, forbidden licenses, and unresolved high findings fail closed', () => {
  for (const mutate of [
    (f: ReturnType<typeof makeSecurityFixture>) => { f.report.componentCount = 99; },
    (f: ReturnType<typeof makeSecurityFixture>) => { f.report.coverage.vulnerabilityComponentRefs.pop(); },
    (f: ReturnType<typeof makeSecurityFixture>) => { f.report.licenseAnalysis[1].expression = 'AGPL-3.0-only'; },
    (f: ReturnType<typeof makeSecurityFixture>) => { f.report.findings.push({ id: 'CVE-TEST-HIGH', componentRef: f.report.coverage.vulnerabilityComponentRefs[1], severity: 'high', status: 'open' }); },
  ]) {
    const fixture = makeSecurityFixture();
    try {
      mutate(fixture);
      const result = verifyFixture(fixture);
      assert.notEqual(result.status, 0, result.stdout);
      assert.match(result.stderr, /RELEASE_SECURITY_BLOCKED:/);
    } finally { fs.rmSync(fixture.root, { recursive: true, force: true }); }
  }
});

test('expired waivers and critical waivers fail closed while a current signed high waiver is accepted', () => {
  const cases = [
    { severity: 'high', expiresAt: '2026-08-11T00:00:00Z', passes: false },
    { severity: 'critical', expiresAt: '2026-08-20T00:00:00Z', passes: false },
    { severity: 'high', expiresAt: '2026-08-20T00:00:00Z', passes: true },
  ];
  for (const item of cases) {
    const fixture = makeSecurityFixture();
    try {
      const componentRef = fixture.report.coverage.vulnerabilityComponentRefs[1];
      fixture.report.findings.push({ id: 'CVE-TEST-WAIVED', componentRef, severity: item.severity, status: 'waived' });
      fixture.report.waivers.push({ id: 'WAIVER-2026-001', findingId: 'CVE-TEST-WAIVED', reviewer: 'Security Reviewer',
        reason: 'Compensating network control is independently monitored.', approvedAt: '2026-08-12T09:00:00Z', expiresAt: item.expiresAt });
      const result = verifyFixture(fixture);
      assert.equal(result.status === 0, item.passes, result.stderr);
    } finally { fs.rmSync(fixture.root, { recursive: true, force: true }); }
  }
});

test('stale report or vulnerability database evidence fails closed', () => {
  for (const field of ['generatedAt', 'database'] as const) {
    const fixture = makeSecurityFixture();
    try {
      if (field === 'generatedAt') fixture.report.generatedAt = '2026-08-01T00:00:00Z';
      else fixture.report.vulnerabilityDatabase.updatedAt = '2026-08-01T00:00:00Z';
      const result = verifyFixture(fixture);
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /stale/);
    } finally { fs.rmSync(fixture.root, { recursive: true, force: true }); }
  }
});

test('fixture-derived SBOM cannot be promoted as release evidence', () => {
  const generatorFixture = makeGeneratorFixture();
  try {
    const sbom = path.join(generatorFixture.root, 'fixture.cdx.json');
    assert.equal(run('python3', [generator, '--repo', generatorFixture.root, '--go-tool', '/usr/bin/true', '--fixture-input-dir', generatorFixture.inputs,
      '--allow-fixture-input', '--output', sbom]).status, 0);
    const security = makeSecurityFixture();
    try {
      security.sbomPath = sbom;
      security.report.sbomSha256 = crypto.createHash('sha256').update(fs.readFileSync(sbom)).digest('hex');
      security.report.sbomSerialNumber = JSON.parse(fs.readFileSync(sbom, 'utf8')).serialNumber;
      const result = verifyFixture(security);
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /fixture-derived SBOMs/);
    } finally { fs.rmSync(security.root, { recursive: true, force: true }); }
  } finally { fs.rmSync(generatorFixture.root, { recursive: true, force: true }); }
});

test('repository policy contains no fabricated scanner approval or private signing key', () => {
  const policy = JSON.parse(fs.readFileSync(path.join(projectRoot, 'security/release-security-policy.json'), 'utf8'));
  assert.deepEqual(policy.trustedKeys, []);
  for (const relative of [
    'security/release-security-policy.json',
    'security/release-security-policy.schema.json',
    'security/release-security-report.schema.json',
  ]) {
    const content = fs.readFileSync(path.join(projectRoot, relative), 'utf8');
    assert.doesNotMatch(content, /BEGIN (?:ED25519 |RSA |EC |OPENSSH )?PRIVATE KEY/);
  }
});

test('repository default policy cannot approve a formal scan report', () => {
  const fixture = makeSecurityFixture();
  try {
    const reportPath = fixture.sign(fixture.report);
    const defaultPolicy = path.join(projectRoot, 'security/release-security-policy.json');
    const result = run('python3', [verifier, '--sbom', fixture.sbomPath,
      '--security-report', reportPath, '--policy', defaultPolicy,
      '--now', TEST_NOW, '--allow-test-time']);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /not uniquely trusted/);
  } finally { fs.rmSync(fixture.root, { recursive: true, force: true }); }
});

test('security trust policy is self-contained and rejects filesystem key references', () => {
  const fixture = makeSecurityFixture();
  try {
    const policy = JSON.parse(fs.readFileSync(fixture.policyPath, 'utf8'));
    const trusted = policy.trustedKeys[0];
    trusted.publicKeyPemFile = '/tmp/untrusted-scanner.pem';
    fs.writeFileSync(fixture.policyPath, JSON.stringify(policy));
    const result = verifyFixture(fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /schema mismatch/);
  } finally { fs.rmSync(fixture.root, { recursive: true, force: true }); }
});

test('security verifier uses the declared OpenSSL runtime, not an undeclared Python crypto package', () => {
  const source = fs.readFileSync(verifier, 'utf8');
  assert.doesNotMatch(source, /from cryptography|import cryptography/);
  assert.match(source, /openssl.*pkeyutl/s);
});
