import { fileIo } from '@kit.CoreFileKit'

function waitForWrite(stream: fileIo.WriteStream, serialized: string): Promise<void> {
  return new Promise<void>((resolve: () => void, reject: (reason: Error) => void) => {
    try {
      stream.write(serialized, 'utf8', (error?: Error): void => {
        if (error instanceof Error) {
          reject(error)
          return
        }
        resolve()
      })
    } catch (error) {
      reject(error)
    }
  })
}

/**
 * Replaces a private text file through CoreFileKit's AtomicFile protocol.
 *
 * Writable.write() returns a buffer-capacity boolean, not a Promise. The
 * callback is the write-completion signal and must fire before finishWrite().
 * AtomicFile owns the WriteStream: callers must not close it themselves.
 */
export async function writeAtomicText(path: string, serialized: string): Promise<void> {
  const atomicFile: fileIo.AtomicFile = new fileIo.AtomicFile(path)
  let rollbackRequired: boolean = false
  try {
    const stream: fileIo.WriteStream = atomicFile.startWrite()
    rollbackRequired = true
    await waitForWrite(stream, serialized)
  } catch (error) {
    if (rollbackRequired) {
      try {
        atomicFile.failWrite()
      } catch (_) {
        // Preserve the initiating start/write failure.
      }
    }
    throw error
  }

  // finishWrite() finalizes and invalidates the native stream reference.
  // A commit failure must propagate directly; calling failWrite() afterwards
  // would attempt to finalize the same native reference twice on API 26.
  try {
    atomicFile.finishWrite()
  } catch (error) {
    // Commit may already have finalized the native stream reference. Preserve
    // that error without attempting a second finalization through failWrite().
    throw error
  }
}
