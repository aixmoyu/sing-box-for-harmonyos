import {
  defaultNetworkSettings,
  decodeNetworkSettings,
  NetworkSettings
} from '../domain/NetworkSettings.ts'
import { SecureFileStore } from '../services/SecureFileStore'

const LEGACY_SETTINGS_FILE: string = 'network-settings-v1.json'
const SECURE_SETTINGS_FILE: string = 'network-settings-v1.secure.json'
const MAX_NETWORK_SETTINGS_BYTES: number = 64 * 1024

function validateNetworkSettings(serialized: string): void {
  // An empty legacy settings file historically meant defaults and carries no
  // secret. Non-empty content must pass the same domain decoder as load()
  // before migration is allowed to remove the plaintext.
  if (serialized.trim().length > 0) decodeNetworkSettings(serialized)
}

export class NetworkSettingsRepository {
  private secureStore: SecureFileStore

  constructor(filesDir: string) {
    this.secureStore = new SecureFileStore(
      `${filesDir}/${SECURE_SETTINGS_FILE}`,
      `${filesDir}/${LEGACY_SETTINGS_FILE}`,
      'network-settings',
      MAX_NETWORK_SETTINGS_BYTES,
      validateNetworkSettings)
  }

  async load(): Promise<NetworkSettings> {
    const serialized: string | null = await this.secureStore.load()
    if (serialized === null) return defaultNetworkSettings()
    if (serialized.trim().length === 0) return defaultNetworkSettings()
    return decodeNetworkSettings(serialized)
  }

  async save(settings: NetworkSettings): Promise<void> {
    await this.secureStore.save(JSON.stringify(settings))
  }

  async clear(): Promise<void> {
    await this.secureStore.clear()
  }
}
