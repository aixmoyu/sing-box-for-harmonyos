import * as nativeCore from 'libentry.so'
export const testConfig: (config: string, tag: string) => Promise<number> = nativeCore.testConfig
export const control: (payload: string) => Promise<void> = nativeCore.control

export const initialize: typeof nativeCore.initialize = nativeCore.initialize
