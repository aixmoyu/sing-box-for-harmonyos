import { SecureFileStore } from './SecureFileStore'
import { prepareLocalConfig } from '../domain/LocalConfig'

export class LocalConfigStore {
  private store: SecureFileStore
  constructor(filesDir: string) {
    this.store = new SecureFileStore(`${filesDir}/local-profile.secure.json`,
      `${filesDir}/local-profile.json`, 'local-sing-box-profile', 4 * 1024 * 1024,
      (value: string): void => { prepareLocalConfig(value) })
  }
  async load(): Promise<string | null> { return this.store.load() }
  async save(value: string): Promise<void> { await this.store.save(value) }
  async clear(): Promise<void> { await this.store.clear() }
}
