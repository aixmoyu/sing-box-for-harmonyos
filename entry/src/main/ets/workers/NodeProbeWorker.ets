import { worker, MessageEvents, ThreadWorkerGlobalScope } from '@kit.ArkTS'
import { nodeProbeErrorCode } from '../domain/NodeProbeDiagnostic'
import * as nativeCore from '../core/NativeCore'

interface ProbeRequest { type: string; id: number; config: string; filesDir?: string; cacheDir?: string }
const port: ThreadWorkerGlobalScope = worker.workerPort
let busy: boolean = false
let closing: boolean = false
let initialized: boolean = false

port.onmessage = async (event: MessageEvents): Promise<void> => {
  const request: ProbeRequest = event.data as ProbeRequest
  if (request.type === 'close') {
    closing = true
    if (busy) { try { await nativeCore.control('{"action":"cancel-url-test"}') } catch (_) { } }
    if (!busy) port.close()
    return
  }
  if (closing || busy || request.type !== 'test') return
  busy = true
  let delay: number = -1
  let error: string = ''
  try {
    // The UI and VpnExtension have separate native processes. Initialize the
    // UI's libbox sandbox before constructing an outbound-only probe.
    if (!initialized) {
      if (!request.filesDir || !request.cacheDir) throw new Error('probe-init: missing sandbox paths')
      try { await nativeCore.initialize(request.filesDir + '/node-probe', request.cacheDir + '/node-probe') }
      catch (_) { throw new Error('probe-init: native setup failed') }
      initialized = true
    }
    if (!closing) delay = await nativeCore.testConfig(request.config, 'node-test')
  } catch (failure) { error = nodeProbeErrorCode(failure instanceof Error ? failure.message : '') }
  finally {
    busy = false
    if (closing) port.close()
    else port.postMessage({ id: request.id, delay: delay, error: error })
  }
}
