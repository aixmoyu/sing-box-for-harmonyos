import test from 'node:test'
import assert from 'node:assert/strict'
import {
  classifyProxyUrlTestFailure,
  formatProxyUrlTestFailure
} from '../../entry/src/main/ets/domain/ProxyUrlTestDiagnostic.ts'

const cases: Array<{ message: string, code: string }> = [{
  message: 'VPN socket protection refused an unsafe underlay network',
  code: 'HNA-URL-PROTECT'
}, {
  message: 'lookup private-node.example.test: i/o timeout',
  code: 'HNA-URL-DNS'
}, {
  message: 'x509: certificate signed by unknown authority',
  code: 'HNA-URL-TLS'
}, {
  message: 'context deadline exceeded',
  code: 'HNA-URL-TIMEOUT'
}, {
  message: 'dial tcp 192.0.2.1:443: connection refused',
  code: 'HNA-URL-CONNECT'
}, {
  message: 'proxy handshake: unexpected EOF',
  code: 'HNA-URL-HANDSHAKE'
}, {
  message: 'TLS handshake: i/o timeout',
  code: 'HNA-URL-TIMEOUT'
}, {
  message: 'selected outbound is unavailable',
  code: 'HNA-URL-OUTBOUND'
}, {
  message: 'unclassified runtime error',
  code: 'HNA-URL-GENERIC'
}]

for (const item of cases) {
  test(`classifies proxy URLTest failure as ${item.code}`, () => {
    assert.equal(classifyProxyUrlTestFailure(item.message).code, item.code)
  })
}

test('formatted URLTest diagnostic never contains native host or credentials', () => {
  const nativeMessage: string =
    'lookup secret-node.example.test password=private-value: no such host'
  const diagnostic = classifyProxyUrlTestFailure(nativeMessage)
  const formatted: string = formatProxyUrlTestFailure(diagnostic)
  assert.equal(formatted, 'HNA-URL-DNS · 节点或测试目标 DNS 解析失败')
  assert.equal(formatted.includes('secret-node'), false)
  assert.equal(formatted.includes('private-value'), false)
  assert.equal(JSON.stringify(diagnostic).includes('secret-node'), false)
})
