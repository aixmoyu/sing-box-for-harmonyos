import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const projectRoot = path.resolve(import.meta.dirname, '../..');
const releaseScript = fs.readFileSync(
  path.join(projectRoot, 'scripts/build_release_app.sh'),
  'utf8',
);
const preflightScript = fs.readFileSync(
  path.join(projectRoot, 'scripts/release_preflight.sh'),
  'utf8',
);
const contentGateScript = fs.readFileSync(
  path.join(projectRoot, 'scripts/release_content_gate.py'),
  'utf8',
);
const moduleManifest = fs.readFileSync(
  path.join(projectRoot, 'entry/src/main/module.json5'),
  'utf8',
);
const indexSource = fs.readFileSync(
  path.join(projectRoot, 'entry/src/main/ets/pages/Index.ets'),
  'utf8',
);

test('formal release uses assembleApp and an explicit release build mode', () => {
  assert.match(
    releaseScript,
    /assembleApp -m project -p product=default -p buildMode=release/,
  );
  assert.match(releaseScript, /profile type is: release/);
  assert.match(releaseScript, /profile type is: debug/);
  assert.match(releaseScript, /hap-sign-tool\.jar/);
  assert.match(releaseScript, /scripts\/build_core\.sh/);
  assert.match(releaseScript, /scripts\/build_ohos_go\.sh/);
  assert.match(releaseScript, /scripts\/core_smoke_test\.sh/);
  assert.match(releaseScript, /packaged native core differs from this release build's stripped output/);
  assert.match(releaseScript, /freshlyBuiltUnstrippedSha256/);
  assert.match(releaseScript, /packagedStrippedSha256/);
  assert.match(releaseScript, /coreLockSha256/);
  assert.match(releaseScript, /buildToolchainLockSha256/);
  assert.match(releaseScript, /build_toolchain_lock_sha/);
  assert.match(releaseScript, /official Release SDK; prerelease SDK metadata is not publishable/);
  assert.match(releaseScript, /HNA_RELEASE_CERT_SHA256/);
  assert.match(releaseScript, /HNA_OPERATOR_NAME/);
  assert.match(releaseScript, /HNA_PRIVACY_URL/);
  assert.match(releaseScript, /HNA_PRIVACY_URL_EN/);
  assert.match(releaseScript, /HNA_USER_AGREEMENT_URL/);
  assert.match(releaseScript, /HNA_USER_AGREEMENT_URL_EN/);
  assert.match(releaseScript, /HNA_SUPPORT_URL/);
  assert.match(releaseScript, /HNA_SUPPORT_EMAIL/);
  assert.match(releaseScript, /HNA_CORRESPONDING_SOURCE_URL/);
  assert.match(releaseScript, /hna_release_provenance\.json/);
  assert.match(releaseScript, /approvedLeafCertificateSha256/);
  assert.match(releaseScript, /publicInfo/);
  assert.match(releaseScript, /ReleaseConfig\.ts/);
  assert.match(releaseScript, /generate_release_sbom\.py/);
  assert.match(releaseScript, /verify_release_security\.py/);
  assert.match(releaseScript, /securityEvidence/);
  assert.match(releaseScript, /\.security-policy\.json/);
  assert.match(releaseScript, /\.security-verification\.json/);
  assert.match(releaseScript, /PENDING obtain an external signed release approval/);
  assert.match(preflightScript, /signed build toolchain provenance mismatch/);
  assert.match(preflightScript, /official HarmonyOS unpacking tool is required for formal release validation/);
  assert.doesNotMatch(preflightScript, /used strict ZIP-validated fallback/);
  assert.match(preflightScript, /build-toolchain-lock\.json/);
  assert.ok(
    releaseScript.indexOf('scripts/build_ohos_go.sh') <
      releaseScript.indexOf('scripts/verify_core_vendor.sh\" >/dev/null'),
    'a clean checkout must rebuild the ignored OHOS Go binary before full local verification',
  );
});

test('formal release fails closed on missing signing and package structure', () => {
  assert.match(releaseScript, /build-profile\.json5 is missing/);
  assert.match(releaseScript, /not valid JSON5/);
  assert.match(releaseScript, /exact reviewed semantic shape/);
  assert.match(releaseScript, /redacted_build_profile_sha/);
  assert.match(releaseScript, /verify_release_package\.py" build-profile/);
  assert.match(releaseScript, /verify-profile -inFile/);
  assert.match(releaseScript, /content\.get\("type"\) != "release"/);
  assert.match(releaseScript, /bundle-info/);
  assert.match(releaseScript, /provision profile is not a current release profile for this bundle/);
  assert.match(releaseScript, /does not contain root pack\.info/);
  assert.match(releaseScript, /must contain exactly one HAP module/);
  assert.match(releaseScript, /Git worktree is dirty/);
  assert.match(releaseScript, /git archive --format=tar "\$git_commit"/);
  assert.doesNotMatch(releaseScript, /rsync -a/);
  assert.match(releaseScript, /explicit local-input allowlist/);
  assert.match(releaseScript, /native build inputs come from the immutable Git commit archive/);
  assert.match(releaseScript, /source worktree or HEAD changed while the isolated native core was building/);
  assert.match(releaseScript, /tracked-source-sha256\.json/);
  assert.match(releaseScript, /GIT_INDEX_FILE="\$isolated_index"/);
  assert.match(releaseScript, /isolated release source differs from the explicit generated-file allowlist/);
  assert.doesNotMatch(
    releaseScript,
    /the isolated build changed tracked source or lock files/,
  );
  assert.match(releaseScript, /cp "\$build_profile" "\$build_root\/build-profile\.json5"/);
  assert.match(releaseScript, /for toolchain_output in bin pkg/);
  assert.match(releaseScript, /cp -a "\$core_build_root\/core\/go\/out"/);
  assert.match(releaseScript, /must contain this full Git commit or a version tag/);
  assert.match(releaseScript, /hna_sing_box_gpl_v3\.txt/);
  assert.match(releaseScript, /distributionLicenses/);
  assert.match(releaseScript, /every HAP must contain one complete signed license resource set/);
  const emailPatternLine = releaseScript
    .split('\n')
    .find((line) => line.includes('re.fullmatch') && line.includes('[A-Za-z0-9.!#$%'));
  assert.ok(emailPatternLine?.includes('(?:\\.['), 'a normal public email domain must be accepted');
  assert.ok(!emailPatternLine?.includes('(?:\\\\.['), 'the email regex must not require a literal backslash');
  const emailPattern = emailPatternLine?.match(/re\.fullmatch\(r"([^"]+)"/)?.[1];
  assert.ok(emailPattern, 'release email regex must be extractable for a behavioral check');
  const checkEmail = (value: string): number => spawnSync(
    'python3',
    ['-c', 'import re,sys; raise SystemExit(0 if re.fullmatch(sys.argv[1], sys.argv[2]) else 1)', emailPattern, value],
  ).status ?? -1;
  assert.equal(checkEmail('support@company.cn'), 0);
  assert.notEqual(checkEmail('support@company'), 0);
});

test('legal submission documents remain machine-detectable templates', () => {
  const legalDir = path.join(projectRoot, 'docs/legal');
  const templates = [
    'privacy-policy.zh-CN.template.md',
    'privacy-policy.en.template.md',
    'user-agreement.zh-CN.template.md',
    'user-agreement.en.template.md',
    'app-review-notes.zh-CN.template.md',
    'app-review-notes.en.template.md',
    'store-metadata.zh-CN.template.md',
    'store-metadata.en.template.md',
  ];
  for (const template of templates) {
    const content = fs.readFileSync(path.join(legalDir, template), 'utf8');
    assert.match(content, /HNA_LEGAL_TEMPLATE_DO_NOT_SUBMIT/);
    assert.match(content, /\[TODO:/);
  }
});

test('release preflight rejects legal templates and placeholder declarations', () => {
  assert.match(preflightScript, /HNA_LEGAL_TEMPLATE_DO_NOT_SUBMIT/);
  assert.match(preflightScript, /HNA_OPERATOR_NAME/);
  assert.match(preflightScript, /HNA_USER_AGREEMENT_URL/);
  assert.match(preflightScript, /\\\[TODO/);
  assert.match(preflightScript, /todo\|tbd\|placeholder\|self-test/i);
  assert.match(preflightScript, /example\.com/);
  assert.match(preflightScript, /ui-resources\.test\.ts/);
  assert.match(preflightScript, /index-ui-contract\.test\.ts/);
  assert.match(preflightScript, /END OF TERMS AND CONDITIONS/);
  assert.match(preflightScript, /distribution NOTICE\/open-source notices are explicitly preliminary/);
  assert.match(preflightScript, /notice_file="THIRD_PARTY_NOTICES\.md"/);
  assert.doesNotMatch(preflightScript, /for candidate in NOTICE THIRD_PARTY_NOTICES\.md/);
  assert.match(preflightScript, /release-manifest\.json is missing beside the App Pack/);
  assert.match(preflightScript, /SHA256SUMS is missing beside the App Pack/);
  assert.match(preflightScript, /release source commit mismatch/);
  assert.match(preflightScript, /release core provenance mismatch/);
  assert.match(preflightScript, /packaged HAP\/core provenance mismatch/);
  assert.match(preflightScript, /evidence file is empty/);
  assert.match(contentGateScript, /ipaddress\.ip_address/);
  assert.match(preflightScript, /release_content_gate\.py probe-url/);
  assert.match(preflightScript, /bounded HTML\/text HTTPS 2xx response through a DNS-pinned public redirect chain/);
  assert.doesNotMatch(preflightScript, /curl\s/);
  assert.match(preflightScript, /--skip-tests is diagnostic-only/);
  assert.match(preflightScript, /--allow-dirty is diagnostic-only/);
  assert.match(preflightScript, /strict ZIP, payload, pack\.info/);
  assert.match(preflightScript, /verify_release_package\.py app/);
  assert.match(preflightScript, /official HarmonyOS unpacking tool accepted/);
  assert.match(preflightScript, /official HarmonyOS unpacking tool is required for formal release validation/);
  assert.doesNotMatch(preflightScript, /strict ZIP-validated fallback/);
  assert.match(preflightScript, /buildProfileRedactedSha256/);
  assert.match(preflightScript, /signed release provenance metadata mismatch/);
  assert.match(preflightScript, /release public metadata mismatch/);
  assert.match(preflightScript, /signed release public metadata mismatch/);
  assert.match(preflightScript, /must contain this full Git commit or a version tag/);
  assert.match(preflightScript, /signed native-core provenance mismatch/);
  assert.match(preflightScript, /hna_sing_box_gpl_v3\.txt/);
  assert.match(preflightScript, /HAP signed license resource set is incomplete or duplicated/);
  assert.match(preflightScript, /HAP signed license resource differs from source tree/);
  assert.match(preflightScript, /release distribution license manifest mismatch/);
  assert.match(preflightScript, /signed release distribution license metadata mismatch/);
  assert.match(preflightScript, /not signed by the approved release certificate/);
  assert.match(preflightScript, /core_smoke_test\.sh/);
  assert.match(preflightScript, /setAppPreferredLanguage\\\(preference === 'system'/);
  assert.match(preflightScript, /verify_release_security\.py/);
  assert.match(preflightScript, /require_file HNA_RELEASE_SECURITY_POLICY/);
  assert.match(preflightScript, /explicit release security policy exactly matches the sibling policy bytes/);
  assert.match(preflightScript, /generate_release_sbom\.py/);
  assert.match(preflightScript, /signed release security evidence binding mismatch/);
  assert.match(preflightScript, /verify_release_approval\.py/);
  assert.match(preflightScript, /HNA_RELEASE_APPROVAL_SIGNATURE/);
  assert.match(preflightScript, /HNA_RELEASE_APPROVAL_TRUSTED_KEY/);
  assert.match(preflightScript, /HNA_HUAWEI_VPN_REVIEW_EVIDENCE/);
  assert.match(preflightScript, /HNA_HUAWEI_OVERSEAS_PHONE_EVIDENCE/);
  assert.match(preflightScript, /missing, invalid, stale, replayed, or mismatched signed release approval/);
  assert.match(preflightScript, /huawei-vpn-category-review=/);
  assert.match(preflightScript, /cn-telecom-vpn-legal-review=/);
  assert.match(preflightScript, /huawei-overseas-phone-eligibility=/);
  assert.ok(
    preflightScript.indexOf('signed release security evidence binding mismatch') <
      preflightScript.indexOf('python3 scripts/verify_release_approval.py'),
    'approval must run only after package, manifest, and security bytes have been verified',
  );
  assert.doesNotMatch(releaseScript, /verify_release_approval\.py/);
});

test('strict release package verifier accepts only the reviewed single-HAP shape', () => {
  const fixtureScript = path.join(
    projectRoot,
    'tooling/tests/fixtures/release_package_fixture.py',
  );
  const verifier = path.join(projectRoot, 'scripts/verify_release_package.py');
  const appJson = path.join(projectRoot, 'AppScope/app.json5');
  const moduleJson = path.join(projectRoot, 'entry/src/main/module.json5');
  const temporaryRoot = fs.mkdtempSync('/tmp/hna-release-fixture.');
  try {
    const runVariant = (variant: string): ReturnType<typeof spawnSync> => {
      const directory = path.join(temporaryRoot, variant);
      const fixture = spawnSync('python3', [fixtureScript, directory, variant], {
        encoding: 'utf8',
      });
      assert.equal(fixture.status, 0, fixture.stderr);
      return spawnSync('python3', [
        verifier,
        'app',
        '--app', path.join(directory, 'Fixture.app'),
        '--release-manifest', path.join(directory, 'release-manifest.json'),
        '--app-json', appJson,
        '--module-json', moduleJson,
      ], { encoding: 'utf8' });
    };

    const valid = runVariant('valid');
    assert.equal(valid.status, 0, valid.stderr);
    const result = JSON.parse(valid.stdout);
    assert.deepEqual(result.permissions, [
      'ohos.permission.GET_BUNDLE_INFO',
      'ohos.permission.GET_NETWORK_INFO',
      'ohos.permission.INTERNET',
    ]);

    for (const variant of [
      'hsp',
      'extra',
      'two-hap',
      'traversal',
      'absolute',
      'windows-absolute',
      'backslash',
      'duplicate-app-entry',
      'symlink',
      'directory',
      'special',
      'oversize',
      'duplicate-hap-entry',
      'hap-traversal',
      'hap-symlink',
      'debug',
      'bad-permissions',
      'bad-pack',
      'bad-min-api',
      'malformed-min-api-encoding',
      'beta-pack-sdk',
      'beta-hap-sdk',
      'exported-vpn',
      'bad-main-element',
      'bad-pack-main-ability',
      'extra-compiled-ability',
      'extra-pack-ability',
      'private-entry-ability',
      'bad-home-skill',
      'bad-security-binding',
    ]) {
      const rejected = runVariant(variant);
      assert.notEqual(rejected.status, 0, `${variant} must be rejected`);
      assert.match(rejected.stderr, /RELEASE_PACKAGE_INVALID:/);
    }
  } finally {
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
  }
});

test('build profile verifier records only a redacted semantic digest', () => {
  const verifier = path.join(projectRoot, 'scripts/verify_release_package.py');
  const temporaryRoot = fs.mkdtempSync('/tmp/hna-profile-fixture.');
  try {
    for (const name of ['release.cer', 'release.p7b', 'release.p12']) {
      fs.writeFileSync(path.join(temporaryRoot, name), `public-or-keystore-${name}`);
    }
    const secretPassword = 'never-emit-this-password';
    const parsedProfile = {
      app: {
        products: [{
          name: 'default',
          signingConfig: 'release',
          compileSdkVersion: '26.0.0',
          targetSdkVersion: '26.0.0',
          compatibleSdkVersion: '6.0.2(22)',
          runtimeOS: 'HarmonyOS',
        }],
        buildModeSet: [{ name: 'debug' }, { name: 'release' }],
        signingConfigs: [{
          name: 'release',
          type: 'HarmonyOS',
          material: {
            certpath: 'release.cer',
            keyAlias: 'private-alias',
            keyPassword: secretPassword,
            profile: 'release.p7b',
            signAlg: 'SHA256withECDSA',
            storeFile: 'release.p12',
            storePassword: secretPassword,
          },
        }],
      },
      modules: [{
        name: 'entry',
        srcPath: './entry',
        targets: [{ name: 'default', applyToProducts: ['default'] }],
      }],
    };
    const parsedPath = path.join(temporaryRoot, 'parsed-profile.json');
    fs.writeFileSync(parsedPath, JSON.stringify(parsedProfile));
    const verified = spawnSync('python3', [
      verifier,
      'build-profile',
      '--parsed-build-profile', parsedPath,
      '--build-profile-dir', temporaryRoot,
    ], { encoding: 'utf8' });
    assert.equal(verified.status, 0, verified.stderr);
    assert.match(verified.stdout, /"redactedBuildProfileSha256":"[0-9a-f]{64}"/);
    assert.doesNotMatch(verified.stdout, new RegExp(secretPassword));
    assert.doesNotMatch(verified.stdout, /private-alias|release\.p12/);

    parsedProfile.app.products[0].targetSdkVersion = '25.0.0';
    fs.writeFileSync(parsedPath, JSON.stringify(parsedProfile));
    const rejected = spawnSync('python3', [
      verifier,
      'build-profile',
      '--parsed-build-profile', parsedPath,
      '--build-profile-dir', temporaryRoot,
    ], { encoding: 'utf8' });
    assert.notEqual(rejected.status, 0);
  } finally {
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
  }
});

test('release preflight pins the exact reviewed permissions and their privacy purposes', () => {
  const permissions = [...new Set(moduleManifest.match(/ohos\.permission\.[A-Z0-9_]+/g) ?? [])].sort();
  assert.deepEqual(permissions, [
    'ohos.permission.GET_BUNDLE_INFO',
    'ohos.permission.GET_NETWORK_INFO',
    'ohos.permission.INTERNET',
  ]);
  assert.match(preflightScript, /expected_permission_names=/);
  assert.match(preflightScript, /permission surface is exactly INTERNET, GET_NETWORK_INFO and GET_BUNDLE_INFO/);
  assert.match(indexSource, /权限用途：INTERNET/);
  assert.match(indexSource, /Permission purposes: INTERNET/);
  assert.match(indexSource, /GET_NETWORK_INFO/);
  assert.match(indexSource, /GET_BUNDLE_INFO/);
  assert.match(indexSource, /BEARER_VPN/);
});

test('root and in-app third-party notices are identical and enforced by preflight', () => {
  const verifier = path.join(projectRoot, 'scripts/verify_open_source_notice.py');
  const rootNotice = path.join(projectRoot, 'THIRD_PARTY_NOTICES.md');
  const openSourceTexts = path.join(projectRoot, 'entry/src/main/ets/ui/OpenSourceTexts.ts');
  const coreLock = path.join(projectRoot, 'third_party/core-lock.json');
  const matching = spawnSync('python3', [verifier, rootNotice, openSourceTexts, coreLock], {
    encoding: 'utf8',
  });
  assert.equal(matching.status, 0, matching.stderr);

  const mismatching = spawnSync('python3', [verifier, path.join(projectRoot, 'LICENSE'), openSourceTexts, coreLock], {
    encoding: 'utf8',
  });
  assert.notEqual(mismatching.status, 0);
  assert.match(preflightScript, /verify_open_source_notice\.py/);
  assert.match(preflightScript, /in-app notice, THIRD_PARTY_NOTICES\.md, or core lock differs/);
});
