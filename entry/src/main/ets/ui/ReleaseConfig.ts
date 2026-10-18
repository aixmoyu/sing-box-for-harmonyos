/**
 * Public, non-secret release metadata.
 *
 * Debug/source builds deliberately keep these values empty and show a release
 * blocker. scripts/build_release_app.sh writes reviewed production values only
 * in its isolated build copy, then signs the resulting HAP and embeds the same
 * JSON as a raw resource for independent package verification.
 */
export interface ReleasePublicInfo {
  operatorName: string
  privacyUrl: string
  privacyUrlEn: string
  userAgreementUrl: string
  userAgreementUrlEn: string
  supportUrl: string
  supportEmail: string
  correspondingSourceUrl: string
}

export const RELEASE_PUBLIC_INFO: ReleasePublicInfo = {
  operatorName: '',
  privacyUrl: '',
  privacyUrlEn: '',
  userAgreementUrl: '',
  userAgreementUrlEn: '',
  supportUrl: '',
  supportEmail: '',
  correspondingSourceUrl: ''
}
