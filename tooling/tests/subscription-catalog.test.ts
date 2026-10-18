import test from 'node:test'
import assert from 'node:assert/strict'

import {
  activeSubscription,
  emptySubscriptionStore,
  removeSubscription,
  renameSubscription,
  selectSubscriptionNode,
  setActiveSubscription,
  subscriptionDisplayName,
  upsertSubscription
} from '../../entry/src/main/ets/domain/SubscriptionCatalog.ts'
import type { ProxyNode, SubscriptionBundle } from '../../entry/src/main/ets/domain/Models.ts'
import { emptyMetadata, emptyTls, emptyTransport } from '../../entry/src/main/ets/domain/Models.ts'

function node(id: string, name: string): ProxyNode {
  return {
    id,
    name,
    protocol: 'trojan',
    server: `${id}.example.com`,
    port: 443,
    username: '',
    password: 'test-only',
    uuid: '',
    method: '',
    flow: '',
    tls: emptyTls(),
    transport: emptyTransport(),
    query: []
  }
}

function bundle(title: string, ids: string[]): SubscriptionBundle {
  const metadata = emptyMetadata('uri-list')
  metadata.title = title
  return {
    metadata,
    nodes: ids.map((id: string) => node(id, id)),
    policyGroups: [],
    rules: [],
    dns: { strategy: 'prefer_ipv4', servers: [] },
    warnings: []
  }
}

test('two different URLs remain as two subscriptions', () => {
  let state = emptySubscriptionStore()
  state = upsertSubscription(state, 'https://a.example/sub', bundle('A', ['a-1']), 10)
  state = upsertSubscription(state, 'https://b.example/sub', bundle('B', ['b-1']), 20)
  assert.equal(state.records.length, 2)
  assert.equal(activeSubscription(state)?.bundle.metadata.title, 'B')
})

test('updating one URL preserves the other subscription and selected node', () => {
  let state = emptySubscriptionStore()
  state = upsertSubscription(state, 'https://a.example/sub', bundle('A', ['a-1', 'a-2']), 10)
  const aId = state.activeSubscriptionId
  state = selectSubscriptionNode(state, aId, 'a-2')
  state = upsertSubscription(state, 'https://b.example/sub', bundle('B', ['b-1']), 20)
  const bId = state.activeSubscriptionId
  state = upsertSubscription(state, 'https://a.example/sub', bundle('A2', ['a-2', 'a-3']), 30)
  assert.equal(state.records.length, 2)
  assert.equal(state.activeSubscriptionId, bId)
  assert.equal(state.records.find((record) => record.id === aId)?.selectedNodeId, 'a-2')
  assert.equal(state.records.find((record) => record.bundle.metadata.title === 'B')?.bundle.nodes.length, 1)
})

test('switch, node selection and active fallback are deterministic', () => {
  let state = emptySubscriptionStore()
  state = upsertSubscription(state, 'https://a.example/sub', bundle('A', ['a-1', 'a-2']), 10)
  const aId = state.activeSubscriptionId
  state = upsertSubscription(state, 'https://b.example/sub', bundle('B', ['b-1']), 20)
  state = setActiveSubscription(state, aId)
  state = selectSubscriptionNode(state, aId, 'a-2')
  assert.equal(activeSubscription(state)?.selectedNodeId, 'a-2')
  state = removeSubscription(state, aId)
  assert.equal(state.records.length, 1)
  assert.equal(activeSubscription(state)?.bundle.metadata.title, 'B')
})

test('invalid update cannot mutate the previous catalog', () => {
  const original = upsertSubscription(
    emptySubscriptionStore(),
    'https://a.example/sub',
    bundle('A', ['a-1']),
    10
  )
  assert.throws(() => upsertSubscription(original, 'https://a.example/sub', bundle('bad', []), 20))
  assert.equal(original.records.length, 1)
  assert.equal(original.records[0].bundle.metadata.title, 'A')
})

test('custom subscription name is independent from URL and survives refresh', () => {
  let state = upsertSubscription(
    emptySubscriptionStore(),
    'https://named.example/sub',
    bundle('未命名订阅', ['a-1']),
    10,
    '工作机场'
  )
  const id = state.activeSubscriptionId
  assert.equal(subscriptionDisplayName(state.records[0]), '工作机场')
  state = upsertSubscription(state, 'https://named.example/sub', bundle('服务端标题', ['a-1']), 20)
  assert.equal(state.records[0].id, id)
  assert.equal(state.records[0].customName, '工作机场')
  assert.equal(subscriptionDisplayName(state.records[0]), '工作机场')
})

test('renaming can reset to metadata title and unnamed title falls back to host', () => {
  let state = upsertSubscription(
    emptySubscriptionStore(),
    'https://fallback.example/sub',
    bundle('服务端标题', ['a-1']),
    10,
    '我的订阅'
  )
  state = renameSubscription(state, state.activeSubscriptionId, '')
  assert.equal(subscriptionDisplayName(state.records[0]), '服务端标题')

  state = upsertSubscription(
    emptySubscriptionStore(),
    'https://fallback.example/sub',
    bundle('未命名订阅', ['a-1']),
    20
  )
  assert.equal(subscriptionDisplayName(state.records[0]), 'fallback.example')
})

test('unnamed display fallback never exposes URL query credentials', () => {
  const state = upsertSubscription(
    emptySubscriptionStore(),
    'https://safe.example?token=test-secret-must-not-display',
    bundle('未命名订阅', ['a-1']),
    10
  )
  assert.equal(subscriptionDisplayName(state.records[0]), 'safe.example')
  assert.equal(subscriptionDisplayName(state.records[0]).includes('token'), false)
})
