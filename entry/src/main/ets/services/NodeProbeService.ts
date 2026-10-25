import { nodeProbeErrorLabel } from '../domain/NodeProbeDiagnostic'
import { worker, MessageEvents } from '@kit.ArkTS'

interface ProbeMessage { id: number; delay: number; error: string }

// Lazy worker keeps native initialization out of page construction. Each test
// owns a short-lived outbound-only service; it never changes the active VPN.
export class NodeProbeService {
  private filesDir: string
  private cacheDir: string
  constructor(filesDir: string = '', cacheDir: string = '') { this.filesDir = filesDir; this.cacheDir = cacheDir }
  private thread: worker.ThreadWorker | null = null
  private sequence: number = 0
  private pendingId: number = 0
  private resolve: ((value: number) => void) | null = null
  private reject: ((error: Error) => void) | null = null
  private closed: boolean = false

  test(config: string): Promise<number> {
    if (this.closed || this.resolve !== null) return Promise.reject(new Error('测速已取消或正在进行'))
    if (this.thread === null) {
      this.thread = new worker.ThreadWorker('entry/ets/workers/NodeProbeWorker.ets')
      this.thread.onmessage = (event: MessageEvents): void => {
        const result: ProbeMessage = event.data as ProbeMessage
        if (result.id !== this.pendingId) return
        const resolve = this.resolve
        const reject = this.reject
        this.resolve = null; this.reject = null
        if (result.delay >= 0) { if (resolve !== null) resolve(result.delay) }
        else if (reject !== null) reject(new Error(nodeProbeErrorLabel(result.error)))
      }
      this.thread.onerror = (): void => {
        const reject = this.reject
        this.resolve = null; this.reject = null
        this.close()
        if (reject !== null) reject(new Error('测速线程启动或运行失败'))
      }
    }
    this.pendingId = ++this.sequence
    return new Promise<number>((resolve, reject) => {
      this.resolve = resolve; this.reject = reject
      try { this.thread?.postMessage({ type: 'test', id: this.pendingId, config: config, filesDir: this.filesDir, cacheDir: this.cacheDir }) }
      catch (_) { this.resolve = null; this.reject = null; reject(new Error('无法提交测速任务')); this.close() }
    })
  }

  close(): void {
    if (this.closed) return
    this.closed = true
    const reject = this.reject
    this.resolve = null; this.reject = null
    if (reject !== null) reject(new Error('测速已取消'))
    // Worker cancels and awaits native cleanup before closing its N-API env.
    try { this.thread?.postMessage({ type: 'close', id: 0, config: '' }) } catch (_) { }
    this.thread = null
  }
}
