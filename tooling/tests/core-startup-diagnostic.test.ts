import test from 'node:test'
import assert from 'node:assert/strict'
import {
  classifyCoreStartupFailure,
  formatCoreStartupFailure,
  startupFailureDetail
} from '../../entry/src/main/ets/domain/CoreStartupDiagnostic.ts'

const cases: Array<{ nativeMessage: string, code: string, phrase: string }> = [{
  nativeMessage: 'OH_NetConn_BindSocket failed with NetConn result 2100003',
  code: 'HNA-SOCKET-PROTECT',
  phrase: '代理出站未能绕过 VPN TUN'
}, {
  nativeMessage: 'start dns/https[bootstrap-dns]: detour to an empty direct outbound makes no sense',
  code: 'HNA-DNS-EMPTY-DIRECT',
  phrase: 'DNS 直连出口配置无效'
}, {
  nativeMessage: 'start dns/udp[remote-dns]: initialize transport detour failed',
  code: 'HNA-DNS-TRANSPORT',
  phrase: 'DNS 传输或分流初始化失败'
}, {
  nativeMessage: 'external tun fd: bad file descriptor',
  code: 'HNA-TUN-FD',
  phrase: 'TUN 文件描述符不可用'
}, {
  nativeMessage: 'unix.SetNonblock(42) failed: operation not permitted',
  code: 'HNA-TUN-NONBLOCK',
  phrase: 'TUN 非阻塞模式初始化失败'
}, {
  nativeMessage: 'unix.Fstat(42,...) failed: operation not permitted',
  code: 'HNA-TUN-FSTAT',
  phrase: 'TUN 描述符类型检测失败'
}, {
  nativeMessage: 'createInboundDispatcher(...) = failed to create eventfd: operation not permitted',
  code: 'HNA-TUN-EVENTFD',
  phrase: 'TUN 停止事件初始化失败'
}, {
  nativeMessage: 'createInboundDispatcher(...) = newReadVDispatcher failed',
  code: 'HNA-TUN-DISPATCHER',
  phrase: 'TUN 数据分发器初始化失败'
}, {
  nativeMessage: 'initialize gVisor stack: netstack failed',
  code: 'HNA-TUN-GVISOR',
  phrase: 'TUN gVisor 网络栈初始化失败'
}, {
  nativeMessage: 'open tun interface: ioctl failed',
  code: 'HNA-TUN-INTERFACE',
  phrase: 'TUN 接口初始化失败'
}, {
  nativeMessage: 'open tun interface: operation not permitted',
  code: 'HNA-PERMISSION',
  phrase: 'VPN 系统权限不足'
}, {
  nativeMessage: 'TLS handshake failed: x509 certificate signed by unknown authority',
  code: 'HNA-TLS-CERT',
  phrase: 'TLS 证书校验或握手失败'
}, {
  nativeMessage: 'initialize outbound selector: selected outbound is unavailable',
  code: 'HNA-OUTBOUND',
  phrase: '代理出站初始化或连接失败'
}, {
  nativeMessage: 'unexpected native runtime failure',
  code: 'HNA-CORE-GENERIC',
  phrase: '代理核心启动失败'
}]

for (let index: number = 0; index < cases.length; index++) {
  const item: { nativeMessage: string, code: string, phrase: string } = cases[index]
  test(`maps native startup failure to ${item.code}`, () => {
    const diagnostic = classifyCoreStartupFailure('start-core', item.nativeMessage)
    assert.equal(diagnostic.stage, 'start-core')
    assert.equal(diagnostic.code, item.code)
    assert.equal(diagnostic.safePhrase, item.phrase)
  })
}

test('never returns or formats native secrets', () => {
  const nativeMessage: string = [
    'start dns/https[private-dns]',
    'https://subscription.example.test/s/6fcb570e-bb9f-4cd8-b54b-60ca391b8392',
    'password=super-secret',
    'detour initialization failed'
  ].join(' ')
  const diagnostic = classifyCoreStartupFailure('start-core', nativeMessage)
  const formatted: string = formatCoreStartupFailure(diagnostic)

  assert.equal(diagnostic.code, 'HNA-DNS-TRANSPORT')
  for (const forbidden of [
    'https://', 'subscription.example.test', '6fcb570e-bb9f-4cd8-b54b-60ca391b8392',
    'password', 'super-secret', 'private-dns'
  ]) {
    assert.equal(JSON.stringify(diagnostic).includes(forbidden), false)
    assert.equal(formatted.includes(forbidden), false)
  }
})

test('unknown stage is not allowed to become a log or status channel', () => {
  const diagnostic = classifyCoreStartupFailure(
    'start-core https://private.example.test password=secret',
    'dial tcp failed'
  )
  const formatted: string = formatCoreStartupFailure(diagnostic)

  assert.equal(diagnostic.stage, 'startup')
  assert.equal(diagnostic.code, 'HNA-OUTBOUND')
  assert.equal(formatted, 'VPN 启动失败（startup · HNA-OUTBOUND · 代理出站初始化或连接失败）')
  assert.equal(formatted.includes('private.example.test'), false)
  assert.equal(formatted.includes('secret'), false)
})

test('private error detail preserves the failure while removing subscription credentials', () => {
  const detail = startupFailureDetail('initialize rule-set geosite-cn: Get "https://example.test/private?token=abc": context deadline exceeded password=hidden uuid=12345678-1234-1234-1234-123456789abc')
  assert.ok(detail.includes('initialize rule-set geosite-cn'))
  assert.ok(detail.includes('context deadline exceeded'))
  for (const secret of ['example.test', 'token=abc', 'password=hidden', '12345678-1234']) {
    assert.equal(detail.includes(secret), false)
  }
  assert.equal(startupFailureDetail('x'.repeat(10000)).length, 4096)
})
