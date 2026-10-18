import type {
  ProxyNode,
  SubscriptionBundle,
  SubscriptionRecord,
  SubscriptionStoreState
} from './Models.ts'
import { fnv1aId } from './TextCodec.ts'

export const SUBSCRIPTION_STORE_SCHEMA: number = 2

export function emptySubscriptionStore(): SubscriptionStoreState {
  return {
    schemaVersion: SUBSCRIPTION_STORE_SCHEMA,
    records: [],
    activeSubscriptionId: ''
  }
}

function normalizeUrl(sourceUrl: string): string {
  return sourceUrl.trim()
}

function recordId(sourceUrl: string): string {
  return fnv1aId(`subscription|${sourceUrl}`).replace('node-', 'subscription-')
}

function normalizedCustomName(customName: string | undefined): string {
  return customName === undefined ? '' : customName.trim()
}

function sourceHost(sourceUrl: string): string {
  const schemeIndex: number = sourceUrl.indexOf('://')
  const hostStart: number = schemeIndex >= 0 ? schemeIndex + 3 : 0
  let authorityEnd: number = sourceUrl.length
  const separators: string[] = ['/', '?', '#']
  for (let index: number = 0; index < separators.length; index++) {
    const separatorIndex: number = sourceUrl.indexOf(separators[index], hostStart)
    if (separatorIndex >= 0 && separatorIndex < authorityEnd) authorityEnd = separatorIndex
  }
  const authority: string = sourceUrl.substring(hostStart, authorityEnd)
  const atIndex: number = authority.lastIndexOf('@')
  const hostPort: string = atIndex >= 0 ? authority.substring(atIndex + 1) : authority
  if (hostPort.startsWith('[')) {
    const closeIndex: number = hostPort.indexOf(']')
    return closeIndex > 1 ? hostPort.substring(1, closeIndex) : ''
  }
  const colonIndex: number = hostPort.indexOf(':')
  return (colonIndex >= 0 ? hostPort.substring(0, colonIndex) : hostPort).trim()
}

export function subscriptionDisplayName(record: SubscriptionRecord): string {
  const customName: string = normalizedCustomName(record.customName)
  if (customName.length > 0) return customName
  const title: string = record.bundle.metadata.title.trim()
  if (title.length > 0 && title !== '未命名订阅') return title
  const host: string = sourceHost(record.sourceUrl)
  return host.length > 0 ? host : '未命名订阅'
}

function hasNode(bundle: SubscriptionBundle, nodeId: string): boolean {
  return bundle.nodes.some((node: ProxyNode) => node.id === nodeId)
}

export function upsertSubscription(
  state: SubscriptionStoreState,
  sourceUrl: string,
  bundle: SubscriptionBundle,
  nowMillis: number,
  requestedCustomName?: string
): SubscriptionStoreState {
  const normalized: string = normalizeUrl(sourceUrl)
  if (!normalized.startsWith('https://')) throw new Error('订阅地址必须使用 https://')
  if (bundle.nodes.length === 0) throw new Error('订阅中没有可用节点')

  const existing: SubscriptionRecord | undefined = state.records.find((record: SubscriptionRecord) =>
    record.sourceUrl === normalized)
  const selectedNodeId: string = existing && hasNode(bundle, existing.selectedNodeId) ?
    existing.selectedNodeId : bundle.nodes[0].id
  const updated: SubscriptionRecord = {
    id: existing ? existing.id : recordId(normalized),
    sourceUrl: normalized,
    customName: existing ?
      (normalizedCustomName(requestedCustomName).length > 0 ?
        normalizedCustomName(requestedCustomName) : existing.customName) :
      normalizedCustomName(requestedCustomName),
    bundle: bundle,
    selectedNodeId: selectedNodeId,
    createdAtMillis: existing ? existing.createdAtMillis : nowMillis,
    updatedAtMillis: nowMillis
  }

  const records: SubscriptionRecord[] = []
  let replaced: boolean = false
  for (let index: number = 0; index < state.records.length; index++) {
    const record: SubscriptionRecord = state.records[index]
    if (record.sourceUrl === normalized) {
      records.push(updated)
      replaced = true
    } else {
      records.push(record)
    }
  }
  if (!replaced) records.push(updated)

  return {
    schemaVersion: SUBSCRIPTION_STORE_SCHEMA,
    records: records,
    // Adding a new source activates it. Refreshing an existing, non-active
    // source must not unexpectedly switch the user's current subscription.
    activeSubscriptionId: existing ? state.activeSubscriptionId : updated.id
  }
}

export function setActiveSubscription(
  state: SubscriptionStoreState,
  subscriptionId: string
): SubscriptionStoreState {
  const exists: boolean = state.records.some((record: SubscriptionRecord) => record.id === subscriptionId)
  if (!exists) return state
  return {
    schemaVersion: SUBSCRIPTION_STORE_SCHEMA,
    records: state.records.slice(),
    activeSubscriptionId: subscriptionId
  }
}

export function selectSubscriptionNode(
  state: SubscriptionStoreState,
  subscriptionId: string,
  nodeId: string
): SubscriptionStoreState {
  const records: SubscriptionRecord[] = []
  let changed: boolean = false
  for (let index: number = 0; index < state.records.length; index++) {
    const record: SubscriptionRecord = state.records[index]
    if (record.id === subscriptionId && hasNode(record.bundle, nodeId)) {
      records.push({
        id: record.id,
        sourceUrl: record.sourceUrl,
        customName: record.customName,
        bundle: record.bundle,
        selectedNodeId: nodeId,
        createdAtMillis: record.createdAtMillis,
        updatedAtMillis: record.updatedAtMillis
      })
      changed = true
    } else {
      records.push(record)
    }
  }
  if (!changed) return state
  return {
    schemaVersion: SUBSCRIPTION_STORE_SCHEMA,
    records: records,
    activeSubscriptionId: subscriptionId
  }
}

export function renameSubscription(
  state: SubscriptionStoreState,
  subscriptionId: string,
  customName: string
): SubscriptionStoreState {
  const records: SubscriptionRecord[] = []
  let changed: boolean = false
  const normalized: string = normalizedCustomName(customName)
  for (let index: number = 0; index < state.records.length; index++) {
    const record: SubscriptionRecord = state.records[index]
    if (record.id === subscriptionId) {
      records.push({
        id: record.id,
        sourceUrl: record.sourceUrl,
        customName: normalized,
        bundle: record.bundle,
        selectedNodeId: record.selectedNodeId,
        createdAtMillis: record.createdAtMillis,
        updatedAtMillis: record.updatedAtMillis
      })
      changed = record.customName !== normalized
    } else {
      records.push(record)
    }
  }
  if (!changed) return state
  return {
    schemaVersion: SUBSCRIPTION_STORE_SCHEMA,
    records: records,
    activeSubscriptionId: state.activeSubscriptionId
  }
}

export function removeSubscription(
  state: SubscriptionStoreState,
  subscriptionId: string
): SubscriptionStoreState {
  const records: SubscriptionRecord[] = state.records.filter((record: SubscriptionRecord) =>
    record.id !== subscriptionId)
  let activeSubscriptionId: string = state.activeSubscriptionId
  if (activeSubscriptionId === subscriptionId) {
    activeSubscriptionId = records.length > 0 ? records[0].id : ''
  }
  return {
    schemaVersion: SUBSCRIPTION_STORE_SCHEMA,
    records: records,
    activeSubscriptionId: activeSubscriptionId
  }
}

export function activeSubscription(state: SubscriptionStoreState): SubscriptionRecord | undefined {
  return state.records.find((record: SubscriptionRecord) => record.id === state.activeSubscriptionId)
}
