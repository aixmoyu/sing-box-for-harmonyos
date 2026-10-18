export type UiThemePreference = 'system' | 'light' | 'dark'
export type UiLanguagePreference = 'system' | 'zh' | 'en'

export interface AppTypography {
  display: number
  displayCompact: number
  pageTitle: number
  pageTitleCompact: number
  sectionTitle: number
  cardTitle: number
  metric: number
  body: number
  caption: number
  micro: number
  control: number
  controlCompact: number
  controlMin: number
  controlMaxScale: number
}

// Phone-first type scale. Display sizes stay deliberately restrained so
// Chinese, English and larger system font settings do not crowd fixed chrome.
export const APP_TYPOGRAPHY: AppTypography = {
  display: 24,
  displayCompact: 22,
  pageTitle: 20,
  pageTitleCompact: 18,
  sectionTitle: 16,
  cardTitle: 14,
  metric: 15,
  body: 12,
  caption: 10,
  micro: 9,
  // Controls keep a full 44/48 vp hit target while their labels stay compact.
  // `controlMin` is used by Button.labelStyle so long Chinese/English labels
  // shrink before they are ellipsized in split-screen and large-font modes.
  control: 10,
  controlCompact: 9,
  controlMin: 9,
  controlMaxScale: 1.3
}

export interface AppPalette {
  background: string
  backgroundGlow: string
  backgroundGlowSecondary: string
  surface: string
  surfaceElevated: string
  surfaceMuted: string
  surfaceGlass: string
  materialTint: string
  navigation: string
  border: string
  borderStrong: string
  textPrimary: string
  textSecondary: string
  textTertiary: string
  textDisabled: string
  placeholder: string
  accent: string
  accentStrong: string
  accentSoft: string
  accentForeground: string
  blue: string
  blueSoft: string
  warning: string
  warningSoft: string
  danger: string
  dangerSoft: string
  controlThumb: string
  shadow: string
}

export const DARK_PALETTE: AppPalette = {
  background: '#101114',
  backgroundGlow: '#0A1B2B',
  backgroundGlowSecondary: '#121B39',
  surface: '#1C1D21',
  surfaceElevated: '#25262B',
  surfaceMuted: '#17181C',
  surfaceGlass: '#CC0D1626',
  materialTint: '#5208111F',
  navigation: '#08111F',
  border: '#1D3047',
  borderStrong: '#2B4864',
  textPrimary: '#EAF0F7',
  textSecondary: '#B7C4D4',
  textTertiary: '#8FA3BA',
  textDisabled: '#6F849B',
  placeholder: '#7F94AA',
  accent: '#B9C4FF',
  accentStrong: '#A7B6FF',
  accentSoft: '#303A63',
  accentForeground: '#111C43',
  blue: '#63A9FF',
  blueSoft: '#122A47',
  warning: '#FFBE72',
  warningSoft: '#342518',
  danger: '#FF7D8D',
  dangerSoft: '#351B27',
  controlThumb: '#FFFFFF',
  shadow: '#66000000'
}

export const LIGHT_PALETTE: AppPalette = {
  background: '#FAF8FF',
  backgroundGlow: '#E7F8F5',
  backgroundGlowSecondary: '#E8EEFF',
  surface: '#F5F3FA',
  surfaceElevated: '#E3E2E8',
  surfaceMuted: '#DAD9DF',
  surfaceGlass: '#D9FFFFFF',
  materialTint: '#A6FFFFFF',
  navigation: '#EEEDF5',
  border: '#D8E3ED',
  borderStrong: '#B9CDDD',
  textPrimary: '#1B1B1F',
  textSecondary: '#44464F',
  textTertiary: '#526B82',
  textDisabled: '#566B80',
  placeholder: '#5E7387',
  accent: '#4D6099',
  accentStrong: '#3B4E9D',
  accentSoft: '#DAE2FF',
  accentForeground: '#FFFFFF',
  blue: '#145FAD',
  blueSoft: '#E4F0FF',
  warning: '#A55B08',
  warningSoft: '#FFF0DD',
  danger: '#A92E42',
  dangerSoft: '#FFE8EC',
  controlThumb: '#FFFFFF',
  shadow: '#1A18324A'
}

export const UI_PREFERENCES_FILE: string = 'ui-preferences-v1'
export const UI_LANGUAGE_KEY: string = 'language'
export const UI_THEME_KEY: string = 'theme'
export const UI_PRIVACY_CONSENT_KEY: string = 'privacy-consent-v1'

export function normalizedLanguagePreference(value: string): UiLanguagePreference {
  if (value === 'zh' || value === 'en') return value
  return 'system'
}

export function normalizedThemePreference(value: string): UiThemePreference {
  if (value === 'light' || value === 'dark') return value
  return 'system'
}
