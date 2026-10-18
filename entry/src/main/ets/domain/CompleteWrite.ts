export type WriteChunk = (chunk: ArrayBuffer) => Promise<number>

export async function writeFully(bytes: Uint8Array, write: WriteChunk): Promise<void> {
  let offset: number = 0
  while (offset < bytes.length) {
    const chunk: ArrayBuffer = bytes.slice(offset).buffer as ArrayBuffer
    const written: number = await write(chunk)
    if (!Number.isInteger(written) || written <= 0 || written > chunk.byteLength) {
      throw new Error('安全存储写入不完整')
    }
    offset += written
  }
}
