export interface CoreInfo {
  available: boolean
  version: string
  reason: string
}

export interface ValidationResult {
  valid: boolean
  error: string
}

export interface CoreStatus {
  snapshotJson?: string
  running: boolean
  uploadBytes: number
  downloadBytes: number
  activeConnections: number
  selectedOutboundTag: string
  version: string
  lastError: string
}

export const initialize: (workingDirectory: string, temporaryDirectory: string) => Promise<CoreInfo>
export const validateConfig: (configJson: string) => Promise<ValidationResult>
export const start: (tunFd: number, configJson: string) => Promise<void>
export const reload: (configJson: string) => Promise<void>
export const stop: () => Promise<void>
export const urlTest: (nodeTag: string) => Promise<number>
export const selectOutbound: (nodeTag: string) => Promise<string>
export const getStatus: () => Promise<CoreStatus>
export const getStatusLite: () => Promise<CoreStatus>
export const version: () => string
export const lastError: () => string

export const control: (payload: string) => Promise<void>
