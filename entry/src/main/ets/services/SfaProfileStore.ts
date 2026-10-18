import { SfaCatalog, emptySfaCatalog, parseSfaCatalog } from '../domain/SfaProfiles'
import { SecureFileStore } from './SecureFileStore'

export class SfaProfileStore {
  private store: SecureFileStore
  constructor(filesDir: string) {
    this.store = new SecureFileStore(`${filesDir}/sfa-profiles.secure.json`, `${filesDir}/sfa-profiles.json`,
      'sfa-profiles-v1', 32 * 1024 * 1024, (text: string): void => { parseSfaCatalog(text) })
  }
  async load(): Promise<SfaCatalog> {
    const text: string | null = await this.store.load()
    return text === null ? emptySfaCatalog() : parseSfaCatalog(text)
  }
  async save(catalog: SfaCatalog): Promise<void> { await this.store.save(JSON.stringify(catalog)) }
}
