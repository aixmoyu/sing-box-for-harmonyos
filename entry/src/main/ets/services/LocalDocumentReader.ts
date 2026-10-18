import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'

export async function readLocalDocument(uri: string): Promise<string> {
  const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY)
  const maximum: number = 4 * 1024 * 1024
  const bytes = new Uint8Array(maximum + 1)
  let total: number = 0
  try {
    // Picker returns a document URI, not a sandbox path. Keep the granted
    // descriptor open and handle short reads instead of reopening with readText.
    while (total <= maximum) {
      const chunk = new ArrayBuffer(Math.min(65536, maximum + 1 - total))
      const count: number = await fileIo.read(file.fd, chunk)
      if (count === 0) break
      bytes.set(new Uint8Array(chunk, 0, count), total)
      total += count
      if (total > maximum) throw new Error('配置文件不能超过 4 MiB')
    }
    if (total === 0) throw new Error('配置文件为空')
    return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(bytes.subarray(0, total))
  } finally {
    bytes.fill(0)
    await fileIo.close(file)
  }
}
