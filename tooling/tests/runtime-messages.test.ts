import assert from 'node:assert/strict'
import test from 'node:test'
import { localizeRuntimeMessage } from '../../entry/src/main/ets/ui/RuntimeMessages.ts'

const GENERIC_FAILURE: string = 'The operation could not be completed. Open Diagnostics for details.'

function english(value: string): string {
  return localizeRuntimeMessage(value, 'en-US', 'Cloudflare DoH')
}

test('known successful runtime operations never fall through to the English failure fallback', () => {
  const successes: Array<[string, string]> = [
    ['路由模式已切换为规则', 'Routing mode changed to Rule.'],
    ['路由模式已切换为全局代理', 'Routing mode changed to Global.'],
    ['路由模式已切换为直连', 'Routing mode changed to Direct.'],
    ['已切换为手动选点', 'Node strategy changed to Manual.'],
    ['已切换为自动优选', 'Node strategy changed to Auto-select.'],
    ['已切换为周期故障转移', 'Node strategy changed to Failover.'],
    ['核心日志等级已设为 info', 'Core log level changed to info.'],
    ['IPv6 已开启并接管双栈', 'IPv6 enabled. TUN now captures both IPv4 and IPv6.'],
    ['IPv6 已关闭，TUN 将接管并阻止 IPv6 泄漏',
      'IPv6 proxying disabled. TUN will capture and block IPv6 to prevent leaks.'],
    ['已选择 Cloudflare DoH', 'DNS preset selected: Cloudflare DoH.'],
    ['自定义加密 DNS 已保存', 'Custom encrypted DNS saved.'],
    ['已切换到 Example profile', 'Active subscription switched.'],
    ['已设置自动优选的偏好节点', 'Auto-select preference updated.'],
    ['已设置故障转移首选节点', 'Failover primary node updated.'],
    ['批量代理 URLTest 完成', 'Batch proxy URLTest completed.'],
    ['路由模式已切换为规则，VPN 已按新配置重新连接', 'Settings applied and VPN reconnected.']
  ]

  for (const [source, expected] of successes) {
    const localized: string = english(source)
    assert.equal(localized, expected, source)
    assert.notEqual(localized, GENERIC_FAILURE, source)
    assert.doesNotMatch(localized, /[\u3400-\u9FFF]/, source)
  }
})

test('common actionable runtime errors have specific English messages', () => {
  const errors: Array<[string, string]> = [
    ['VPN 运行状态文件超过安全上限', 'The VPN runtime status file exceeds its safety limit.'],
    ['无法安装 HTTPS 重定向安全检查，已拒绝下载订阅',
      'HTTPS redirect safety validation could not be installed. The subscription download was refused.'],
    ['订阅重定向试图离开 HTTPS，已拒绝下载',
      'The subscription redirect attempted to leave HTTPS. The download was refused.'],
    ['无法确认订阅最终地址仍为 HTTPS，已拒绝下载',
      'The final subscription URL could not be confirmed as HTTPS. The download was refused.'],
    ['代理配置不是有效 JSON', 'The proxy configuration is not valid JSON.'],
    ['代理配置结构不完整', 'The proxy configuration structure is incomplete.'],
    ['代理配置缺少 TUN 入站', 'The proxy configuration is missing its TUN inbound.'],
    ['安全存储密码更新未返回数据', 'The secure-storage cipher update returned no data.'],
    ['安全存储密码操作未返回数据', 'The secure-storage cipher operation returned no data.'],
    ['VMess alterId 必须是非负整数', 'VMess alterId must be a non-negative integer.'],
    ['节点链接缺少协议名', 'The proxy link is missing a protocol name.'],
    ['IPv6 地址缺少右方括号', 'The IPv6 address is missing its closing bracket.'],
    ['节点链接缺少端口', 'The proxy link is missing a port.'],
    ['Hysteria2 obfs 当前版本未完整支持，已跳过',
      'This Hysteria2 obfuscation mode is not fully supported and was skipped.'],
    ['同一匹配条件只能配置一次', 'The same match condition can be configured only once.'],
    ['一次运行配置事务只能修改订阅或网络设置之一',
      'One runtime transaction can change either the active subscription or network settings, not both.'],
    ['核心未确认原连接已恢复', 'The core did not confirm that the previous connection was restored.'],
    ['核心未确认当前 VPN 已停止', 'The core did not confirm that the current VPN stopped.'],
    ['核心未确认新配置正在运行', 'The core did not confirm that the new configuration is running.'],
    ['核心未确认新的运行节点', 'The core did not confirm the new runtime node.'],
    ['运行配置不是有效 JSON', 'The runtime configuration is not valid JSON.'],
    ['运行配置缺少 TUN 入站', 'The runtime configuration is missing its TUN inbound.'],
    ['运行配置缺少路由规则', 'The runtime configuration is missing routing rules.'],
    ['运行配置包含多个 TUN 入站', 'The runtime configuration contains more than one TUN inbound.'],
    ['运行配置缺少 TUN 地址', 'The runtime configuration is missing a TUN address.'],
    ['运行配置包含未授权的 TUN 地址', 'The runtime configuration contains an unauthorized TUN address.'],
    ['运行配置必须接管 IPv4 与 IPv6', 'The runtime configuration must capture both IPv4 and IPv6.'],
    ['订阅数据包含无法识别的记录，已保留原文件',
      'The subscription data contains an unrecognized record. The original file was kept.']
  ]

  for (const [source, expected] of errors) {
    const localized: string = english(source)
    assert.equal(localized, expected, source)
    assert.notEqual(localized, GENERIC_FAILURE, source)
    assert.doesNotMatch(localized, /[\u3400-\u9FFF]/, source)
  }
})

test('unknown Chinese errors and native diagnostic codes retain the safe English fallback', () => {
  assert.equal(english('未登记的内部错误'), GENERIC_FAILURE)
  assert.equal(english('原生错误 HNA-TUN-FD，附带本地细节'),
    'Runtime operation failed (HNA-TUN-FD). Open Diagnostics for the safe error category.')
  assert.equal(localizeRuntimeMessage('保持中文', 'zh-CN', 'Cloudflare DoH'), '保持中文')
})
