import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

export const DOMAIN = Buffer.from('HNA-RELEASE-APPROVAL-V1\0', 'utf8');

function sorted(value) {
  if (Array.isArray(value)) return value.map(sorted);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, sorted(value[key])]));
  }
  return value;
}

export function canonical(value) {
  return Buffer.from(`${JSON.stringify(sorted(value))}\n`, 'utf8');
}

function timestamp(date) {
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function fileBinding(file) {
  const bytes = fs.readFileSync(file);
  return { sha256: crypto.createHash('sha256').update(bytes).digest('hex'), sizeBytes: bytes.length };
}

export function createReleaseApprovalFixture(root, market = 'overseas') {
  fs.mkdirSync(root, { recursive: true });
  const bundleName = 'com.harmonynet.assistant';
  const versionCode = 1000000;
  const versionName = '0.1.0';
  const gitCommit = '7d73a2fc8125d4dfd1d36b8ea5f9380397648ba9';
  const files = {};
  for (const name of [
    'app', 'privacyPolicyZh', 'privacyPolicyEn', 'userAgreementZh',
    'userAgreementEn', 'correspondingSource', 'sbom', 'securityReport',
  ]) {
    files[name] = path.join(root, `${name}.bin`);
    fs.writeFileSync(files[name], `reviewed-${name}-bytes\n`);
  }
  files.releaseManifest = path.join(root, 'release-manifest.json');
  const appBinding = fileBinding(files.app);
  fs.writeFileSync(files.releaseManifest, JSON.stringify({
    application: { bundleName, versionCode, versionName },
    source: { gitCommit, treeClean: true },
    appPack: { sha256: appBinding.sha256 },
  }));

  const evidenceKinds = market === 'cn' ? [
    'huawei-vpn-category-review', 'cn-app-filing', 'cn-app-copyright',
    'cn-telecom-vpn-legal-review',
  ] : [
    'huawei-vpn-category-review', 'huawei-overseas-phone-eligibility',
    'encryption-export-control-review',
  ];
  const now = new Date();
  const effectiveAt = timestamp(new Date(now.getTime() - 24 * 60 * 60 * 1000));
  const issuedAt = timestamp(new Date(now.getTime() - 60 * 60 * 1000));
  const expiresAt = timestamp(new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000));
  const evidence = evidenceKinds.map((kind, index) => {
    const file = path.join(root, `${kind}.evidence`);
    fs.writeFileSync(file, `authoritative-${kind}-evidence\n`);
    files[`evidence:${kind}`] = file;
    return {
      kind,
      issuer: index === 0 ? 'Huawei App Review Authority' : 'Independent Compliance Authority',
      reference: `HNA-REVIEW-2026-${String(index + 1).padStart(4, '0')}`,
      sha256: fileBinding(file).sha256,
      effectiveAt,
      expiresAt,
    };
  });

  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  const spki = publicKey.export({ type: 'spki', format: 'der' });
  const rawPublicKey = spki.subarray(spki.length - 32);
  const keyId = 'hna-release-approver-2026';
  const issuer = 'HarmonyNet Release Approval Board';
  const keyFingerprintSha256 = crypto.createHash('sha256').update(rawPublicKey).digest('hex');
  const approval = {
    schemaVersion: 1,
    approvalId: `HNA-RELEASE-2026-${market.toUpperCase()}-0001`,
    market,
    application: { bundleName, versionCode, versionName },
    source: { gitCommit },
    artifacts: Object.fromEntries(Object.entries(files)
      .filter(([name]) => !name.startsWith('evidence:'))
      .map(([name, file]) => [name, fileBinding(file)])),
    evidence,
    validity: { issuedAt, notBefore: effectiveAt, expiresAt },
    signer: { keyId, issuer, keyFingerprintSha256 },
  };
  const approvalBytes = canonical(approval);
  const approvalFile = path.join(root, 'release-approval.json');
  fs.writeFileSync(approvalFile, approvalBytes);
  const signature = crypto.sign(null, Buffer.concat([DOMAIN, approvalBytes]), privateKey);
  const signatureFile = path.join(root, 'release-approval.sig.json');
  fs.writeFileSync(signatureFile, canonical({
    schemaVersion: 1,
    algorithm: 'Ed25519',
    keyId,
    approvalSha256: crypto.createHash('sha256').update(approvalBytes).digest('hex'),
    signatureBase64: signature.toString('base64'),
  }));
  const trustedKeyFile = path.join(root, 'trusted-release-key.json');
  fs.writeFileSync(trustedKeyFile, canonical({
    schemaVersion: 1,
    keyId,
    issuer,
    algorithm: 'Ed25519',
    publicKeyBase64: rawPublicKey.toString('base64'),
    notBefore: timestamp(new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000)),
    expiresAt: timestamp(new Date(now.getTime() + 365 * 24 * 60 * 60 * 1000)),
    markets: ['cn', 'overseas'],
  }));

  return {
    approval,
    approvalFile,
    signatureFile,
    trustedKeyFile,
    files,
    evidenceKinds,
    expected: { market, bundleName, versionCode, versionName, gitCommit },
    privateKey,
  };
}

export function resignFixture(fixture) {
  const approvalBytes = canonical(fixture.approval);
  fs.writeFileSync(fixture.approvalFile, approvalBytes);
  fs.writeFileSync(fixture.signatureFile, canonical({
    schemaVersion: 1,
    algorithm: 'Ed25519',
    keyId: fixture.approval.signer.keyId,
    approvalSha256: crypto.createHash('sha256').update(approvalBytes).digest('hex'),
    signatureBase64: crypto.sign(null, Buffer.concat([DOMAIN, approvalBytes]), fixture.privateKey).toString('base64'),
  }));
}
