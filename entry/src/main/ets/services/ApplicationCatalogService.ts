import { bundle, Want } from '@kit.AbilityKit'
import {
  HARMONY_NET_BUNDLE_NAME,
  validateApplicationBundleName
} from '../domain/NetworkSettings'

export interface SelectableApplication {
  bundleName: string
  label: string
}

const HOME_WANT: Want = {
  action: 'ohos.want.action.home',
  entities: ['entity.system.home']
}

/**
 * Lists launchable applications visible to a normal consumer application.
 *
 * HarmonyOS does not expose the API 26 full installed-bundle inventory to a
 * normal app; that newer API requires an enterprise permission. Querying home
 * abilities uses the normal GET_BUNDLE_INFO permission and gives the user a
 * practical picker. A manual bundle-name field remains the explicit fallback
 * for applications that do not publish a home ability.
 */
export class ApplicationCatalogService {
  async listLaunchableApplications(): Promise<SelectableApplication[]> {
    const abilities = await bundle.queryAbilityByWant(HOME_WANT,
      bundle.BundleFlag.GET_ABILITY_INFO_WITH_APPLICATION)
    const applications: SelectableApplication[] = []
    const seen: string[] = []
    for (let index: number = 0; index < abilities.length; index++) {
      const ability = abilities[index]
      const rawBundleName: string = ability.bundleName
      if (rawBundleName === HARMONY_NET_BUNDLE_NAME || seen.includes(rawBundleName)) continue
      let bundleName: string
      try {
        bundleName = validateApplicationBundleName(rawBundleName)
      } catch (_) {
        continue
      }
      const appLabel: string = ability.applicationInfo.label.trim()
      const abilityLabel: string = ability.label.trim()
      const label: string = appLabel.length > 0 && !appLabel.startsWith('$') ? appLabel :
        (abilityLabel.length > 0 && !abilityLabel.startsWith('$') ? abilityLabel : bundleName)
      seen.push(bundleName)
      applications.push({ bundleName: bundleName, label: label })
    }
    applications.sort((left: SelectableApplication, right: SelectableApplication): number => {
      if (left.label === right.label) {
        if (left.bundleName === right.bundleName) return 0
        return left.bundleName < right.bundleName ? -1 : 1
      }
      return left.label < right.label ? -1 : 1
    })
    return applications
  }
}
