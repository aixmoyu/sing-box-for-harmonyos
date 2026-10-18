import type { SubscriptionRecord, SubscriptionStoreState } from '../domain/Models.ts'
import { emptySubscriptionStore, SUBSCRIPTION_STORE_SCHEMA } from '../domain/SubscriptionCatalog.ts'
import { SecureFileStore } from '../services/SecureFileStore'

const LEGACY_STORE_FILE: string = 'subscriptions-v1.json'
const SECURE_STORE_FILE: string = 'subscriptions-v1.secure.json'
const MAX_SUBSCRIPTION_STORE_BYTES: number = 16 * 1024 * 1024

function decodeSubscriptionStore(serialized: string): SubscriptionStoreState {
  if (serialized.length === 0) return emptySubscriptionStore()
  const decoded: SubscriptionStoreState = JSON.parse(serialized) as SubscriptionStoreState
  if ((decoded.schemaVersion !== 1 && decoded.schemaVersion !== SUBSCRIPTION_STORE_SCHEMA) ||
    !Array.isArray(decoded.records)) {
    throw new Error('订阅数据版本无法识别，请先导出后重置')
  }
  const records: SubscriptionRecord[] = decoded.records.filter((record: SubscriptionRecord) =>
    record.id.length > 0 && record.sourceUrl.startsWith('https://') &&
    record.bundle !== undefined && Array.isArray(record.bundle.nodes)).map((record: SubscriptionRecord) => {
      return {
        id: record.id,
        sourceUrl: record.sourceUrl,
        customName: typeof record.customName === 'string' ? record.customName.trim() : '',
        bundle: record.bundle,
        selectedNodeId: record.selectedNodeId,
        createdAtMillis: record.createdAtMillis,
        updatedAtMillis: record.updatedAtMillis
      }
    })
  let activeSubscriptionId: string = decoded.activeSubscriptionId
  if (!records.some((record: SubscriptionRecord) => record.id === activeSubscriptionId)) {
    activeSubscriptionId = records.length > 0 ? records[0].id : ''
  }
  return {
    schemaVersion: SUBSCRIPTION_STORE_SCHEMA,
    records: records,
    activeSubscriptionId: activeSubscriptionId
  }
}

function validateSubscriptionStore(serialized: string): void {
  // Migration may delete a legacy plaintext only after the exact business
  // schema and every persisted record are accepted. Do not silently filter a
  // malformed record and then delete the only plaintext copy containing it.
  if (serialized.length === 0) return
  const decoded: SubscriptionStoreState = JSON.parse(serialized) as SubscriptionStoreState
  if ((decoded.schemaVersion !== 1 && decoded.schemaVersion !== SUBSCRIPTION_STORE_SCHEMA) ||
    !Array.isArray(decoded.records) || typeof decoded.activeSubscriptionId !== 'string') {
    throw new Error('订阅数据版本无法识别，请先导出后重置')
  }
  for (let index: number = 0; index < decoded.records.length; index++) {
    const record: SubscriptionRecord = decoded.records[index]
    if (!record || typeof record.id !== 'string' || record.id.length === 0 ||
      typeof record.sourceUrl !== 'string' || !record.sourceUrl.startsWith('https://') ||
      !record.bundle || !Array.isArray(record.bundle.nodes) ||
      typeof record.selectedNodeId !== 'string' ||
      typeof record.createdAtMillis !== 'number' || typeof record.updatedAtMillis !== 'number') {
      throw new Error('订阅数据包含无法识别的记录，已保留原文件')
    }
  }
  decodeSubscriptionStore(serialized)
}

export class SubscriptionRepository {
  private secureStore: SecureFileStore

  constructor(filesDir: string) {
    this.secureStore = new SecureFileStore(
      `${filesDir}/${SECURE_STORE_FILE}`,
      `${filesDir}/${LEGACY_STORE_FILE}`,
      'subscription-catalog',
      MAX_SUBSCRIPTION_STORE_BYTES,
      validateSubscriptionStore)
  }

  async load(): Promise<SubscriptionStoreState> {
    const serialized: string | null = await this.secureStore.load()
    if (serialized === null) return emptySubscriptionStore()
    return decodeSubscriptionStore(serialized)
  }

  async save(state: SubscriptionStoreState): Promise<void> {
    await this.secureStore.save(JSON.stringify(state))
  }

  async clear(): Promise<void> {
    await this.secureStore.clear()
  }
}
