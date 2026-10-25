import type { ProxyNode, ProxyProtocol } from './Models.ts'
import { emptyTls, emptyTransport } from './Models.ts'
import { nodeShareUri } from './QuickStart.ts'

export interface NodeDraft {
  name: string; protocol: string; server: string; port: string; username: string; credential: string; method: string; alterId: string;
  security: string; sni: string; insecure: boolean; alpn: string; fingerprint: string; publicKey: string; shortId: string;
  flow: string; transport: string; path: string; host: string; serviceName: string
}
export function emptyNodeDraft(): NodeDraft {
  return { name: '', protocol: 'vless', server: '', port: '443', username: '', credential: '', method: '', alterId: '0', security: 'tls',
    sni: '', insecure: false, alpn: '', fingerprint: '', publicKey: '', shortId: '', flow: '', transport: 'tcp', path: '', host: '', serviceName: '' }
}
export function draftFromNode(node: ProxyNode): NodeDraft {
  return { name: node.name, protocol: node.protocol, server: node.server, port: node.port.toString(), username: node.username,
    credential: node.protocol === 'tuic' ? `${node.uuid}:${node.password}` : node.uuid || node.password,
    method: node.method, alterId: (node.alterId || 0).toString(), security: node.tls.reality.enabled ? 'reality' : node.tls.enabled ? 'tls' : 'none',
    sni: node.tls.serverName, insecure: node.tls.insecure, alpn: node.tls.alpn.join(','), fingerprint: node.tls.utls.fingerprint,
    publicKey: node.tls.reality.publicKey, shortId: node.tls.reality.shortId, flow: node.flow, transport: node.transport.type || 'tcp',
    path: node.transport.path, host: node.transport.host, serviceName: node.transport.serviceName }
}
export function draftNodeUri(draft: NodeDraft): string {
  if (!/^\d+$/.test(draft.port) || Number(draft.port) < 1 || Number(draft.port) > 65535) throw new Error('端口必须为 1–65535')
  if (!draft.server.trim() || /[\s\/?#@]/.test(draft.server)) throw new Error('请填写服务器域名或 IP')
  if (!/^\d+$/.test(draft.alterId)) throw new Error('alterId 必须为非负整数')
  const tls = emptyTls(); const transport = emptyTransport()
  tls.enabled = draft.security !== 'none'; tls.serverName = draft.sni.trim(); tls.insecure = draft.insecure
  tls.alpn = draft.alpn.split(',').map((value: string) => value.trim()).filter((value: string) => value.length > 0)
  tls.utls.enabled = draft.fingerprint.length > 0; tls.utls.fingerprint = draft.fingerprint
  tls.reality.enabled = draft.security === 'reality'; tls.reality.publicKey = draft.publicKey; tls.reality.shortId = draft.shortId
  transport.type = draft.transport; transport.path = draft.path; transport.host = draft.host; transport.serviceName = draft.serviceName
  if (draft.protocol === 'vmess' && (draft.insecure || draft.security === 'reality' || draft.transport === 'grpc')) throw new Error('当前 VMess 分享格式不支持这些参数，请使用完整 JSON 配置')
  const tuicParts: string[] = draft.protocol === 'tuic' ? draft.credential.split(':') : []
  const node: ProxyNode = { id: '', name: draft.name.trim(), protocol: draft.protocol as ProxyProtocol, server: draft.server.trim(), port: Number(draft.port),
    username: draft.protocol === 'socks' || draft.protocol === 'http' || draft.protocol === 'ssh' ? draft.username.trim() : '',
    password: draft.protocol === 'tuic' ? (tuicParts.length > 1 ? tuicParts.slice(1).join(':') : '') :
      (['trojan','hysteria2','hysteria','anytls','shadowtls','snell','ssh','shadowsocks','socks','http'].includes(draft.protocol) ? draft.credential : ''),
    uuid: draft.protocol === 'tuic' ? (tuicParts[0] || '') :
      (['vless','vmess'].includes(draft.protocol) ? draft.credential.trim() : ''), method: draft.method || (draft.protocol === 'vmess' ? 'auto' : ''),
    alterId: Number(draft.alterId), flow: draft.flow, tls: tls, transport: transport, query: [] }
  return nodeShareUri(node)
}
