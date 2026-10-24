import type { CoreInfo } from './CoreGateway'

// UI code reads build metadata only. Loading the N-API library or calling a
// c-shared Go export during component construction can block the first frame.
// Only the VPN extension may initialize and operate the native runtime.
export class CoreMetadataGateway {
  getInfo(): CoreInfo {
    return { available: true, version: '1.14.4', reason: '' }
  }

  getVersion(): string { return '1.14.4' }
}
