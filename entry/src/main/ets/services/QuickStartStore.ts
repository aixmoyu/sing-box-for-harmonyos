import { QuickCatalog, emptyQuickCatalog, parseQuickCatalog } from '../domain/QuickStart'
import { SecureFileStore } from './SecureFileStore'

export class QuickStartStore {
  private store: SecureFileStore
  constructor(filesDir: string) {
    this.store = new SecureFileStore(filesDir + '/quick-nodes.secure.json', filesDir + '/quick-nodes.json',
      'quick-nodes-v1', 32 * 1024 * 1024, (text: string): void => { parseQuickCatalog(text) })
  }
  async load(): Promise<QuickCatalog> {
    const text: string | null = await this.store.load()
    return text === null ? emptyQuickCatalog() : parseQuickCatalog(text)
  }
  async save(catalog: QuickCatalog): Promise<void> { await this.store.save(JSON.stringify(catalog)) }
}
