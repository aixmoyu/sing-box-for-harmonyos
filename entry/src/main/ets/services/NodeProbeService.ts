import { socket } from '@kit.NetworkKit'
import type { ProxyNode } from '../domain/Models.ts'

export class NodeProbeService {
  async measureTcpLatency(node: ProxyNode): Promise<number> {
    const tcp: socket.TCPSocket = socket.constructTCPSocketInstance()
    const startedAt: number = Date.now()
    try {
      await tcp.connect({
        address: {
          address: node.server,
          port: node.port
        },
        timeout: 3500
      })
      return Math.max(1, Date.now() - startedAt)
    } catch (_) {
      return -1
    } finally {
      try {
        await tcp.close()
      } catch (_) {
        // A failed connect may already have closed the socket.
      }
    }
  }
}
