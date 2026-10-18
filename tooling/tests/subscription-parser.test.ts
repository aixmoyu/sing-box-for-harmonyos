import test from 'node:test'
import assert from 'node:assert/strict'
import { SubscriptionParser } from '../../entry/src/main/ets/domain/SubscriptionParser.ts'
import { parseSubscriptionHeaders } from '../../entry/src/main/ets/domain/SubscriptionHeaders.ts'

const parser = new SubscriptionParser()

test('extracts case-insensitive quota and base64 profile title headers', () => {
  const title = Buffer.from('示例机场', 'utf8').toString('base64')
  const headers = parseSubscriptionHeaders(JSON.stringify({
    'Profile-Title': `base64:${title}`,
    'Subscription-UserInfo': ['upload=100; download=200; total=1000; expire=1893456000']
  }))
  assert.equal(headers.title, '示例机场')
  assert.equal(headers.subscriptionUserInfo, 'upload=100; download=200; total=1000; expire=1893456000')
})

test('parses a base64 URI subscription and quota metadata', () => {
  const uriList = [
    'ss://YWVzLTEyOC1nY206cGFzc3dvcmQ@198.51.100.10:443#HongKong-SS',
    'trojan://fake-password@203.0.113.8:443?security=tls&sni=edge.example.test#Tokyo-Trojan',
    'vless://11111111-2222-3333-4444-555555555555@192.0.2.7:8443?security=tls&sni=vless.example.test&type=ws&path=%2Fsocket#Singapore-VLESS',
    'hysteria2://hy2-password@192.0.2.9:443?sni=hy2.example.test#US-HY2'
  ].join('\n')
  const encoded = Buffer.from(uriList, 'utf8').toString('base64')
  const bundle = parser.parse(encoded, {
    title: '测试订阅',
    subscriptionUserInfo: 'upload=100; download=200; total=1000; expire=1893456000'
  })

  assert.equal(bundle.metadata.title, '测试订阅')
  assert.equal(bundle.metadata.sourceFormat, 'uri-list')
  assert.equal(bundle.metadata.totalBytes, 1000)
  assert.equal(bundle.metadata.expireAtSeconds, 1893456000)
  assert.equal(bundle.nodes.length, 4)
  assert.deepEqual(bundle.nodes.map((node) => node.protocol), [
    'shadowsocks', 'trojan', 'vless', 'hysteria2'
  ])
  assert.equal(bundle.nodes[2].transport.type, 'ws')
  assert.equal(bundle.nodes[2].transport.path, '/socket')
  assert.equal(bundle.policyGroups[0].nodeIds.length, 4)
})

test('preserves literal and percent-encoded plus signs in URI credentials', () => {
  const bundle = parser.parse(
    'trojan://literal+plus%2Band%20space@203.0.113.18:443?security=tls&sni=plus.example.test#Plus-Credential'
  )

  assert.equal(bundle.nodes.length, 1)
  assert.equal(bundle.nodes[0].password, 'literal+plus+and space')
})

test('parses vmess JSON URI without exposing real credentials', () => {
  const vmessPayload = {
    v: '2',
    ps: 'VMess-Test',
    add: '198.51.100.20',
    port: '443',
    id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
    aid: '64',
    scy: 'auto',
    net: 'ws',
    host: 'cdn.example.test',
    path: '/vmess',
    tls: 'tls',
    sni: 'cdn.example.test'
  }
  const uri = `vmess://${Buffer.from(JSON.stringify(vmessPayload), 'utf8').toString('base64')}`
  const bundle = parser.parse(uri)

  assert.equal(bundle.nodes.length, 1)
  assert.equal(bundle.nodes[0].protocol, 'vmess')
  assert.equal(bundle.nodes[0].name, 'VMess-Test')
  assert.equal(bundle.nodes[0].alterId, 64)
  assert.equal(bundle.nodes[0].tls.enabled, true)
  assert.equal(bundle.nodes[0].transport.host, 'cdn.example.test')
})

test('imports sing-box outbounds, selector, DNS and routing rules', () => {
  const source = JSON.stringify({
    dns: {
      strategy: 'ipv4_only',
      servers: [{ type: 'https', address: 'https://1.1.1.1/dns-query' }]
    },
    outbounds: [
      {
        type: 'shadowsocks',
        tag: 'HK-01',
        server: '198.51.100.11',
        server_port: 8443,
        method: '2022-blake3-aes-128-gcm',
        password: 'MDEyMzQ1Njc4OWFiY2RlZg=='
      },
      {
        type: 'trojan',
        tag: 'JP-01',
        server: '203.0.113.11',
        server_port: 443,
        password: 'fake-password',
        tls: { enabled: true, server_name: 'jp.example.test' }
      },
      { type: 'selector', tag: 'PROXY', outbounds: ['HK-01', 'JP-01'], default: 'JP-01' },
      { type: 'direct', tag: 'DIRECT' }
    ],
    route: {
      rules: [
        { domain_suffix: ['example.cn'], outbound: 'DIRECT' },
        { domain: ['blocked.example'], action: 'reject' }
      ],
      final: 'PROXY'
    }
  })

  const bundle = parser.parse(source)
  assert.equal(bundle.metadata.sourceFormat, 'sing-box-json')
  assert.equal(bundle.nodes.length, 2)
  assert.equal(bundle.policyGroups[0].name, 'PROXY')
  assert.equal(bundle.policyGroups[0].selectedNodeId, bundle.nodes[1].id)
  assert.equal(bundle.dns.strategy, 'ipv4_only')
  assert.equal(bundle.rules.length, 3)
  assert.equal(bundle.rules[1].target, 'reject')
})

test('maps sing-box outbound tags to safe routing targets', () => {
  const source = JSON.stringify({
    outbounds: [
      {
        type: 'shadowsocks', tag: 'NODE', server: '198.51.100.22', server_port: 443,
        method: 'aes-128-gcm', password: 'fake-password'
      },
      { type: 'selector', tag: 'GROUP', outbounds: ['NODE'] },
      { type: 'urltest', tag: 'AUTO', outbounds: ['NODE'] },
      { type: 'direct', tag: 'LAN' },
      { type: 'block', tag: 'BLOCK' },
      { type: 'reject', tag: 'DENY' },
      { type: 'dns', tag: 'LEGACY-DNS' },
      { type: 'mystery-special', tag: 'SPECIAL' }
    ],
    route: {
      rules: [
        { domain: 'node.example', outbound: 'NODE' },
        { domain: 'group.example', outbound: 'GROUP' },
        { domain: 'auto.example', outbound: 'AUTO' },
        { domain: 'lan.example', outbound: 'LAN' },
        { domain: 'block.example', outbound: 'BLOCK' },
        { domain: 'deny.example', outbound: 'DENY' },
        { domain: 'dns.example', outbound: 'LEGACY-DNS' },
        { domain: 'special.example', outbound: 'SPECIAL' },
        { domain: 'missing.example', outbound: 'MISSING' }
      ],
      final: 'LAN'
    }
  })
  const bundle = parser.parse(source)
  const ruleFor = (value: string) => bundle.rules.find((rule) => rule.value === value)

  assert.equal(ruleFor('node.example')?.target, 'proxy')
  assert.equal(ruleFor('group.example')?.target, 'GROUP')
  assert.equal(ruleFor('auto.example')?.target, 'AUTO')
  assert.equal(ruleFor('lan.example')?.target, 'direct')
  assert.equal(ruleFor('block.example')?.target, 'reject')
  assert.equal(ruleFor('deny.example')?.target, 'reject')
  assert.equal(bundle.rules.filter((rule) => rule.kind === 'unsupported').length, 3)
  assert.ok(bundle.rules.some((rule) => rule.kind === 'unsupported' && rule.value.includes('LEGACY-DNS')))
  assert.ok(bundle.rules.some((rule) => rule.kind === 'unsupported' && rule.value.includes('SPECIAL')))
  assert.ok(bundle.rules.some((rule) => rule.kind === 'unsupported' && rule.value.includes('MISSING')))
  assert.equal(bundle.rules[bundle.rules.length - 1].kind, 'final')
  assert.equal(bundle.rules[bundle.rules.length - 1].target, 'direct')
  assert.ok(bundle.warnings.some((warning) => warning.includes('规则模式已被安全阻止')))
})

test('retains unsupported sing-box route semantics as rule-mode blockers', () => {
  const source = JSON.stringify({
    outbounds: [
      {
        type: 'shadowsocks',
        tag: 'HK',
        server: '198.51.100.21',
        server_port: 443,
        method: 'aes-128-gcm',
        password: 'fake-password'
      },
      { type: 'direct', tag: 'direct' }
    ],
    route: {
      rules: [
        { domain_suffix: 'safe.example', outbound: 'direct' },
        { domain: ['port.example'], port: [443], outbound: 'direct' },
        { type: 'logical', mode: 'and', rules: [{ domain: ['a.example'] }], outbound: 'direct' },
        { domain: ['a.example'], domain_suffix: ['b.example'], outbound: 'direct' },
        { domain: ['action.example'], action: 'resolve' },
        { domain: ['inverted.example'], invert: true, outbound: 'direct' }
      ]
    }
  })
  const bundle = parser.parse(source)
  const unsupported = bundle.rules.filter((rule) => rule.kind === 'unsupported')

  assert.equal(bundle.rules[0].kind, 'domain_suffix')
  assert.equal(bundle.rules[0].value, 'safe.example')
  assert.equal(unsupported.length, 5)
  assert.ok(unsupported.some((rule) => rule.value.includes('未建模字段 port')))
  assert.ok(unsupported.some((rule) => rule.value.includes('未建模字段 mode, rules')))
  assert.ok(unsupported.some((rule) => rule.value.includes('复合匹配')))
  assert.ok(unsupported.some((rule) => rule.value.includes('规则动作 resolve')))
  assert.ok(unsupported.some((rule) => rule.value.includes('未建模字段 invert')))
  assert.ok(bundle.warnings.some((warning) => warning.includes('规则模式已被安全阻止')))
})

test('imports common multiline Clash YAML fields', () => {
  const yaml = `
proxies:
  - name: HK-SS
    type: ss
    server: 198.51.100.31
    port: 443
    cipher: aes-128-gcm
    password: fake-password
  - name: JP-Trojan
    type: trojan
    server: 203.0.113.31
    port: 443
    password: fake-password
    sni: jp.example.test
    skip-cert-verify: false
proxy-groups:
  - name: PROXY
    type: select
    proxies: [HK-SS, JP-Trojan]
rules:
  - DOMAIN-SUFFIX,example.cn,DIRECT
  - DOMAIN,blocked.example,REJECT
  - DOMAIN,tiny.gif,REJECT-TINYGIF
  - MATCH,PROXY
`
  const bundle = parser.parse(yaml)

  assert.equal(bundle.metadata.sourceFormat, 'clash-yaml')
  assert.equal(bundle.nodes.length, 2)
  assert.equal(bundle.policyGroups[0].nodeIds.length, 2)
  assert.equal(bundle.rules[0].kind, 'domain_suffix')
  assert.equal(bundle.rules[1].target, 'reject')
  assert.equal(bundle.rules[2].target, 'reject')
  assert.equal(bundle.rules[3].kind, 'final')
  assert.ok(bundle.warnings.length >= 1)
})

test('imports common Clash inline-map proxy and group fields', () => {
  const yaml = `
proxies:
  - { name: "HK, Inline", type: ss, server: 198.51.100.41, port: 443, cipher: aes-128-gcm, password: fake-password }
  - { name: JP-Inline, type: trojan, server: 203.0.113.41, port: 443, password: fake-password, sni: jp.example.test }
proxy-groups:
  - { name: PROXY, type: select, proxies: ["HK, Inline", JP-Inline] }
rules:
  - MATCH,PROXY
`
  const bundle = parser.parse(yaml)

  assert.equal(bundle.nodes.length, 2)
  assert.equal(bundle.nodes[0].name, 'HK, Inline')
  assert.equal(bundle.nodes[1].tls.serverName, 'jp.example.test')
  // The lightweight CSV group parser deliberately does not support a comma in
  // a group member name, but must still retain the other valid member.
  assert.ok(bundle.policyGroups[0].nodeIds.includes(bundle.nodes[1].id))
})

test('imports nested inline Clash WebSocket and gRPC transport options', () => {
  const yaml = `
proxies:
  - { name: WS-Inline, type: vless, server: 198.51.100.42, port: 443, uuid: 11111111-2222-3333-4444-555555555555, tls: true, servername: ws.example.test, network: ws, ws-opts: { path: /edge/socket, headers: { Host: cdn.example.test } } }
  - { name: GRPC-Inline, type: trojan, server: 203.0.113.42, port: 443, password: fake-password, sni: grpc.example.test, network: grpc, grpc-opts: { grpc-service-name: tunnel-service } }
rules:
  - MATCH,PROXY
`
  const bundle = parser.parse(yaml)

  assert.equal(bundle.nodes.length, 2)
  assert.equal(bundle.nodes[0].transport.type, 'ws')
  assert.equal(bundle.nodes[0].transport.path, '/edge/socket')
  assert.equal(bundle.nodes[0].transport.host, 'cdn.example.test')
  assert.equal(bundle.nodes[1].transport.type, 'grpc')
  assert.equal(bundle.nodes[1].transport.serviceName, 'tunnel-service')
})

test('retains unsupported Clash rules as blockers with compatibility warnings', () => {
  const yaml = `
proxies:
  - { name: HK, type: ss, server: 198.51.100.43, port: 443, cipher: aes-128-gcm, password: fake-password }
rules:
  - GEOIP,CN,DIRECT
  - GEOSITE,category-ads-all,REJECT
  - IP-ASN,64512,DIRECT
  - PROCESS-NAME,example-app,REJECT
  - DST-PORT,443,PROXY
  - MATCH,PROXY
`
  const bundle = parser.parse(yaml)
  const unsupported = bundle.rules.filter((rule) => rule.kind === 'unsupported')

  assert.equal(unsupported.length, 5)
  assert.deepEqual(unsupported.map((rule) => rule.value), [
    'GEOIP,CN,DIRECT',
    'GEOSITE,category-ads-all,REJECT',
    'IP-ASN,64512,DIRECT',
    'PROCESS-NAME,example-app,REJECT',
    'DST-PORT,443,PROXY'
  ])
  assert.ok(bundle.warnings.some((warning) => warning.includes('GEOIP') && warning.includes('安全阻止')))
  assert.equal(bundle.rules[bundle.rules.length - 1].kind, 'final')
})

test('skips nodes with missing protocol credentials without poisoning valid nodes', () => {
  const source = [
    'ss://YWVzLTEyOC1nY206cGFzc3dvcmQ@198.51.100.51:443#Valid-SS',
    'vless://@198.51.100.52:443?security=tls&sni=bad.example.test#Missing-UUID',
    'trojan://@198.51.100.53:443?security=tls&sni=bad.example.test#Missing-Password'
  ].join('\n')
  const bundle = parser.parse(source)

  assert.equal(bundle.nodes.length, 1)
  assert.equal(bundle.nodes[0].name, 'Valid-SS')
  assert.ok(bundle.warnings.some((warning) => warning.includes('缺少 UUID')))
  assert.ok(bundle.warnings.some((warning) => warning.includes('缺少密码')))
})

test('uses connection-complete node identity for the same endpoint', () => {
  const uuid = '11111111-2222-3333-4444-555555555555'
  const source = [
    `vless://${uuid}@198.51.100.61:443?security=tls&sni=a.example.test&type=ws&path=%2Fa#Route-A`,
    `vless://${uuid}@198.51.100.61:443?security=tls&sni=b.example.test&type=grpc&serviceName=route-b#Route-B`
  ].join('\n')
  const bundle = parser.parse(source)

  assert.equal(bundle.nodes.length, 2)
  assert.notEqual(bundle.nodes[0].id, bundle.nodes[1].id)
})

test('stably deduplicates repeated URI nodes and keeps policy references valid', () => {
  const duplicate = 'ss://YWVzLTEyOC1nY206cGFzc3dvcmQ@198.51.100.62:443#Repeated-URI'
  const unique = 'trojan://fake-password@203.0.113.62:443?security=tls&sni=unique.example.test#Unique-URI'
  const bundle = parser.parse([duplicate, duplicate, unique, duplicate].join('\n'))

  assert.equal(bundle.nodes.length, 2)
  assert.equal(bundle.nodes[0].name, 'Repeated-URI')
  assert.equal(bundle.nodes[1].name, 'Unique-URI')
  assert.equal(new Set(bundle.nodes.map((node) => node.id)).size, bundle.nodes.length)
  assert.deepEqual(bundle.policyGroups[0].nodeIds, bundle.nodes.map((node) => node.id))
  assert.ok(bundle.policyGroups[0].nodeIds.includes(bundle.policyGroups[0].selectedNodeId))
  const warning = bundle.warnings.find((item) => item.includes('2 个重复节点'))
  assert.ok(warning)
  assert.equal(warning?.includes('198.51.100.62'), false)
  assert.equal(warning?.includes('fake-password'), false)
})

test('deduplicates identical sing-box outbounds and selector members', () => {
  const duplicateOutbound = {
    type: 'shadowsocks', tag: 'Repeated-SingBox', server: '198.51.100.63', server_port: 443,
    method: 'aes-128-gcm', password: 'fake-password'
  }
  const bundle = parser.parse(JSON.stringify({
    outbounds: [
      duplicateOutbound,
      { ...duplicateOutbound },
      { type: 'selector', tag: 'PROXY', outbounds: ['Repeated-SingBox', 'Repeated-SingBox'] }
    ]
  }))

  assert.equal(bundle.nodes.length, 1)
  assert.deepEqual(bundle.policyGroups[0].nodeIds, [bundle.nodes[0].id])
  assert.equal(bundle.policyGroups[0].selectedNodeId, bundle.nodes[0].id)
  assert.ok(bundle.warnings.some((warning) => warning.includes('1 个重复节点')))
})

test('deduplicates identical Clash proxies and group members', () => {
  const yaml = `
proxies:
  - { name: Repeated-Clash, type: ss, server: 198.51.100.64, port: 443, cipher: aes-128-gcm, password: fake-password }
  - { name: Repeated-Clash, type: ss, server: 198.51.100.64, port: 443, cipher: aes-128-gcm, password: fake-password }
proxy-groups:
  - { name: PROXY, type: select, proxies: [Repeated-Clash, Repeated-Clash] }
rules:
  - MATCH,PROXY
`
  const bundle = parser.parse(yaml)

  assert.equal(bundle.nodes.length, 1)
  assert.deepEqual(bundle.policyGroups[0].nodeIds, [bundle.nodes[0].id])
  assert.equal(bundle.policyGroups[0].selectedNodeId, bundle.nodes[0].id)
  assert.ok(bundle.warnings.some((warning) => warning.includes('1 个重复节点')))
})

test('parses VLESS Reality and uTLS from a share URI', () => {
  const publicKey = Buffer.from(Array.from({ length: 32 }, (_, index) => index + 1)).toString('base64url')
  const uri = 'vless://11111111-2222-3333-4444-555555555555@198.51.100.71:443' +
    `?security=reality&sni=reality.example.test&pbk=${publicKey}&sid=0123456789abcdef&fp=chrome#Reality`
  const bundle = parser.parse(uri)
  const node = bundle.nodes[0]

  assert.equal(node.tls.enabled, true)
  assert.equal(node.tls.utls.enabled, true)
  assert.equal(node.tls.utls.fingerprint, 'chrome')
  assert.equal(node.tls.reality.enabled, true)
  assert.equal(node.tls.reality.publicKey, publicKey)
  assert.equal(node.tls.reality.shortId, '0123456789abcdef')
})

test('imports Reality and uTLS from sing-box JSON', () => {
  const publicKey = Buffer.from(Array.from({ length: 32 }, (_, index) => 32 - index)).toString('base64url')
  const bundle = parser.parse(JSON.stringify({
    outbounds: [{
      type: 'vless',
      tag: 'Reality-JSON',
      server: '198.51.100.72',
      server_port: 443,
      uuid: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      tls: {
        enabled: true,
        server_name: 'json-reality.example.test',
        utls: { enabled: true, fingerprint: 'firefox' },
        reality: { enabled: true, public_key: publicKey, short_id: 'a1b2c3d4' }
      }
    }]
  }))
  const node = bundle.nodes[0]

  assert.equal(node.tls.utls.fingerprint, 'firefox')
  assert.equal(node.tls.reality.publicKey, publicKey)
  assert.equal(node.tls.reality.shortId, 'a1b2c3d4')
})

test('imports common Clash inline and multiline Reality options', () => {
  const inlineKey = Buffer.from(Array.from({ length: 32 }, (_, index) => index + 1)).toString('base64url')
  const multilineKey = Buffer.from(Array.from({ length: 32 }, (_, index) => 32 - index)).toString('base64url')
  const yaml = `
proxies:
  - { name: Reality-Inline, type: vless, server: 198.51.100.73, port: 443, uuid: 11111111-2222-3333-4444-555555555555, servername: inline.example.test, client-fingerprint: chrome, reality-opts: { public-key: ${inlineKey}, short-id: a1b2c3d4 } }
  - name: Reality-Multiline
    type: vless
    server: 198.51.100.74
    port: 443
    uuid: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
    servername: multiline.example.test
    client-fingerprint: firefox
    reality-opts:
      public-key: ${multilineKey}
      short-id: 01020304
`
  const bundle = parser.parse(yaml)

  assert.equal(bundle.nodes.length, 2)
  assert.equal(bundle.nodes[0].tls.reality.publicKey, inlineKey)
  assert.equal(bundle.nodes[0].tls.utls.fingerprint, 'chrome')
  assert.equal(bundle.nodes[1].tls.reality.publicKey, multilineKey)
  assert.equal(bundle.nodes[1].tls.reality.shortId, '01020304')
  assert.equal(bundle.nodes[1].tls.utls.fingerprint, 'firefox')
})

test('skips Hysteria2 obfs instead of presenting it as usable', () => {
  const source = [
    'ss://YWVzLTEyOC1nY206cGFzc3dvcmQ@198.51.100.81:443#Valid-SS',
    'hysteria2://fake-password@198.51.100.82:443?obfs=salamander&obfs-password=fake-obfs#Unsupported-HY2'
  ].join('\n')
  const bundle = parser.parse(source)

  assert.equal(bundle.nodes.length, 1)
  assert.ok(bundle.warnings.some((warning) => warning.includes('Hysteria2 obfs')))
})

test('skips Shadowsocks SIP002 plugin links instead of dropping plugin semantics', () => {
  const source = [
    'ss://YWVzLTEyOC1nY206cGFzc3dvcmQ@198.51.100.83:443#Valid-SS',
    'ss://YWVzLTEyOC1nY206cGFzc3dvcmQ@198.51.100.84:443?plugin=obfs-local%3Bobfs%3Dhttp%3Bobfs-host%3Dcdn.example.test#Plugin-SS'
  ].join('\n')
  const bundle = parser.parse(source)

  assert.equal(bundle.nodes.length, 1)
  assert.equal(bundle.nodes[0].name, 'Valid-SS')
  assert.ok(bundle.warnings.some((warning) => warning.includes('SIP002/SIP003 plugin')))
})

test('skips Clash Shadowsocks plugin nodes instead of presenting them as plain Shadowsocks', () => {
  const yaml = `
proxies:
  - { name: Valid-SS, type: ss, server: 198.51.100.85, port: 443, cipher: aes-128-gcm, password: fake-password }
  - { name: Plugin-SS, type: ss, server: 198.51.100.86, port: 443, cipher: aes-128-gcm, password: fake-password, plugin: v2ray-plugin, plugin-opts: { mode: websocket, host: cdn.example.test, path: /ws } }
rules:
  - MATCH,PROXY
`
  const bundle = parser.parse(yaml)

  assert.equal(bundle.nodes.length, 1)
  assert.equal(bundle.nodes[0].name, 'Valid-SS')
  assert.ok(bundle.warnings.some((warning) => warning.includes('SIP002/SIP003 plugin')))
})

test('skips sing-box Shadowsocks plugin outbounds until plugin options are modeled', () => {
  const bundle = parser.parse(JSON.stringify({
    outbounds: [
      {
        type: 'shadowsocks', tag: 'Valid-SS', server: '198.51.100.87', server_port: 443,
        method: 'aes-128-gcm', password: 'fake-password'
      },
      {
        type: 'shadowsocks', tag: 'Plugin-SS', server: '198.51.100.88', server_port: 443,
        method: 'aes-128-gcm', password: 'fake-password', plugin: 'obfs-local', plugin_opts: 'obfs=http'
      }
    ]
  }))

  assert.equal(bundle.nodes.length, 1)
  assert.equal(bundle.nodes[0].name, 'Valid-SS')
  assert.ok(bundle.warnings.some((warning) => warning.includes('SIP002/SIP003 plugin')))
})

test('skips unsupported cipher and transport without poisoning valid nodes', () => {
  const content = [
    'ss://bm90LWEtcmVhbC1jaXBoZXI6cGFzc3dvcmQ@198.51.100.80:443#Bad-Cipher',
    'vless://11111111-2222-3333-4444-555555555555@198.51.100.81:443?type=xhttp#Bad-Transport',
    'ss://YWVzLTEyOC1nY206cGFzc3dvcmQ@198.51.100.82:443#Good'
  ].join('\n')
  const bundle = parser.parse(content)

  assert.equal(bundle.nodes.length, 1)
  assert.equal(bundle.nodes[0].name, 'Good')
  assert.ok(bundle.warnings.some((warning: string) => warning.includes('Shadowsocks 加密方式')))
  assert.ok(bundle.warnings.some((warning: string) => warning.includes('传输类型')))
})

test('normalizes common transport aliases and rejects unsupported VMess security', () => {
  const invalidPayload = Buffer.from(JSON.stringify({
    v: '2', ps: 'Bad-VMess', add: '198.51.100.83', port: '443',
    id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee', aid: '0', scy: 'invalid-security'
  }), 'utf8').toString('base64')
  const content = [
    `vmess://${invalidPayload}`,
    'vless://11111111-2222-3333-4444-555555555555@198.51.100.84:443?type=websocket&path=%2Fws#Alias'
  ].join('\n')
  const bundle = parser.parse(content)

  assert.equal(bundle.nodes.length, 1)
  assert.equal(bundle.nodes[0].transport.type, 'ws')
  assert.ok(bundle.warnings.some((warning: string) => warning.includes('VMess 加密方式')))
})

test('skips unmodeled WebSocket early-data instead of emitting a broken node', () => {
  const good = 'vless://11111111-2222-3333-4444-555555555555@198.51.100.71:443?type=ws&path=%2Fok#Good'
  const early = 'vless://11111111-2222-3333-4444-555555555555@198.51.100.72:443?type=ws&path=%2Fed&ed=2048&eh=Sec-WebSocket-Protocol#Early'
  const bundle = parser.parse([early, good].join('\n'))

  assert.equal(bundle.nodes.length, 1)
  assert.equal(bundle.nodes[0].name, 'Good')
  assert.match(bundle.warnings.join('\n'), /early-data/)
})

test('imports standard sing-box VMess security and HTTP transport host', () => {
  const bundle = parser.parse(JSON.stringify({
    outbounds: [{
      type: 'vmess',
      tag: 'VMess-HTTP',
      server: '198.51.100.73',
      server_port: 443,
      uuid: '11111111-2222-3333-4444-555555555555',
      security: 'auto',
      transport: { type: 'http', host: ['h2.example.test'], path: '/h2' }
    }]
  }))

  assert.equal(bundle.nodes.length, 1)
  assert.equal(bundle.nodes[0].method, 'auto')
  assert.equal(bundle.nodes[0].transport.host, 'h2.example.test')
})

test('skips sing-box custom transport headers that cannot be preserved', () => {
  const bundle = parser.parse(JSON.stringify({
    outbounds: [
      {
        type: 'vless', tag: 'Unsupported-Headers', server: '198.51.100.74', server_port: 443,
        uuid: '11111111-2222-3333-4444-555555555555',
        transport: { type: 'ws', path: '/ws', headers: { Host: 'cdn.example.test', Origin: 'https://origin.example' } }
      },
      {
        type: 'vless', tag: 'Good', server: '198.51.100.75', server_port: 443,
        uuid: '11111111-2222-3333-4444-555555555555'
      }
    ]
  }))

  assert.equal(bundle.nodes.length, 1)
  assert.equal(bundle.nodes[0].name, 'Good')
  assert.match(bundle.warnings.join('\n'), /自定义 headers/)
})
