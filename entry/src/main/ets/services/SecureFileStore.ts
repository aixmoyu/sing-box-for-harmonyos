import { util } from '@kit.ArkTS'
import { fileIo } from '@kit.CoreFileKit'
import { SecureCipher } from './SecureCipher'
import { writeFully } from '../domain/CompleteWrite'

const HUKS_KEY_ALIAS: string = 'com.harmonynet.assistant.secure-files.v1'
const CANDIDATE_SUFFIX: string = '.candidate'
const BACKUP_SUFFIX: string = '.backup'
const LOCK_SUFFIX: string = '.lock'

export type SecurePlaintextValidator = (plaintext: string) => void

/**
 * Versioned encrypted text storage with a fail-closed legacy migration.
 *
 * A legacy plaintext is kept until the encrypted file has been atomically
 * committed, read back, authenticated by HUKS and compared with the original.
 * If an encrypted file exists but is damaged, load throws and never falls back
 * to plaintext because that would hide tampering and potentially overwrite the
 * last known-good user state.
 */
export class SecureFileStore {
  private securePath: string
  private candidatePath: string
  private backupPath: string
  private lockPath: string
  private legacyPlaintextPath: string
  private maxPlaintextBytes: number
  private cipher: SecureCipher
  private validateContent: SecurePlaintextValidator
  private saveTail: Promise<void> = Promise.resolve()

  constructor(securePath: string, legacyPlaintextPath: string, aadPurpose: string,
    maxPlaintextBytes: number, validateContent: SecurePlaintextValidator) {
    if (securePath === legacyPlaintextPath || maxPlaintextBytes <= 0) {
      throw new Error('安全文件存储参数无效')
    }
    this.securePath = securePath
    this.candidatePath = `${securePath}${CANDIDATE_SUFFIX}`
    this.backupPath = `${securePath}${BACKUP_SUFFIX}`
    this.lockPath = `${securePath}${LOCK_SUFFIX}`
    this.legacyPlaintextPath = legacyPlaintextPath
    this.maxPlaintextBytes = maxPlaintextBytes
    this.validateContent = validateContent
    this.cipher = new SecureCipher(HUKS_KEY_ALIAS,
      `com.harmonynet.assistant|secure-file|v1|${aadPurpose}`)
  }

  private async exists(path: string): Promise<boolean> {
    try {
      return await fileIo.access(path)
    } catch (error) {
      // Treat an access error as an I/O failure, never as an absent secure
      // file. An absent-state fallback here would bypass authentication.
      throw error
    }
  }

  private async readText(path: string): Promise<string> {
    try {
      return await fileIo.readText(path)
    } catch (error) {
      throw error
    }
  }

  private async unlink(path: string): Promise<void> {
    try {
      await fileIo.unlink(path)
    } catch (error) {
      throw error
    }
  }

  private async rename(sourcePath: string, destinationPath: string): Promise<void> {
    try {
      await fileIo.rename(sourcePath, destinationPath)
    } catch (error) {
      throw error
    }
  }

  private validatePlaintext(plaintext: string): void {
    const plaintextBytes: Uint8Array = new util.TextEncoder().encodeInto(plaintext)
    const plaintextByteLength: number = plaintextBytes.length
    plaintextBytes.fill(0)
    if (plaintextByteLength > this.maxPlaintextBytes) {
      throw new Error('安全存储内容超过允许上限')
    }
    this.validateContent(plaintext)
  }

  private maxEnvelopeCharacters(): number {
    // Base64 expands authenticated ciphertext and its 16-byte GCM tag by at
    // most 4/3. The remaining allowance covers the versioned JSON field names,
    // quotes, algorithm identifier, nonce and future non-sensitive metadata.
    return Math.ceil((this.maxPlaintextBytes + 16) / 3) * 4 + 4096
  }

  private async verifyEncryptedFile(path: string, expectedPlaintext: string): Promise<void> {
    const verifiedPlaintext: string = await this.loadEncryptedFile(path)
    if (verifiedPlaintext !== expectedPlaintext) {
      throw new Error('安全存储写入后验证不一致')
    }
  }

  private async loadEncryptedFile(path: string): Promise<string> {
    const committedEnvelope: string = await this.readText(path)
    if (committedEnvelope.length > this.maxEnvelopeCharacters()) {
      throw new Error('安全存储封装超过允许上限')
    }
    const plaintext: string = await this.cipher.decrypt(committedEnvelope)
    this.validatePlaintext(plaintext)
    return plaintext
  }

  private async removeIfPresent(path: string): Promise<void> {
    if (await this.exists(path)) await this.unlink(path)
  }

  private async withExclusiveLock<T>(action: () => Promise<T>): Promise<T> {
    let lockFile: fileIo.File | null = null
    let locked: boolean = false
    let hasPrimaryFailure: boolean = false
    try {
      lockFile = await fileIo.open(this.lockPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
      await lockFile.lock(true)
      locked = true
      return await action()
    } catch (error) {
      // An inability to serialize UI/Extension access is a storage failure,
      // never an empty-state signal. Preserve the initiating error.
      hasPrimaryFailure = true
      throw error
    } finally {
      let cleanupFailure: unknown | null = null
      if (lockFile !== null && locked) {
        try {
          lockFile.unlock()
        } catch (error) {
          cleanupFailure = error
        }
      }
      if (lockFile !== null) {
        try {
          await fileIo.close(lockFile)
        } catch (error) {
          // Unlock is the more important cleanup failure. Do not replace it
          // with a later close failure, and never replace the primary action
          // failure captured above.
          if (cleanupFailure === null) cleanupFailure = error
        }
      }
      if (!hasPrimaryFailure && cleanupFailure !== null) throw cleanupFailure
    }
  }

  /**
   * Repairs only the explicitly transactional backup state. An ordinary
   * damaged secure file with no backup remains a hard error and can never be
   * hidden by the legacy plaintext path.
   */
  private async recoverInterruptedPromotion(): Promise<void> {
    if (!await this.exists(this.backupPath)) return
    if (!await this.exists(this.securePath)) {
      await this.rename(this.backupPath, this.securePath)
      return
    }
    try {
      await this.loadEncryptedFile(this.securePath)
      // The newly promoted file is authenticated and business-valid. A crash
      // merely left the prior verified copy behind.
      await this.unlink(this.backupPath)
      return
    } catch (secureError) {
      // Authenticate the rollback copy before removing the damaged promoted
      // file. If both copies are damaged, preserve both and fail closed.
      try {
        await this.loadEncryptedFile(this.backupPath)
      } catch (_) {
        throw secureError
      }
      await this.unlink(this.securePath)
      await this.rename(this.backupPath, this.securePath)
    }
  }

  private async removeLegacyAfterVerification(): Promise<void> {
    if (await this.exists(this.legacyPlaintextPath)) {
      await this.unlink(this.legacyPlaintextPath)
    }
  }

  // The candidate is never authoritative. Complete native writes, flush and
  // close before read-back authentication; no stream finalization can race it.
  private async writeCandidate(envelope: string): Promise<void> {
    const bytes: Uint8Array = new util.TextEncoder().encodeInto(envelope)
    const file: fileIo.File = await fileIo.open(this.candidatePath,
      fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    try {
      await writeFully(bytes, (chunk: ArrayBuffer): Promise<number> => fileIo.write(file.fd, chunk))
      await fileIo.fsync(file.fd)
    } finally {
      bytes.fill(0)
      await fileIo.close(file)
    }
  }

  private async saveNow(plaintext: string): Promise<void> {
    this.validatePlaintext(plaintext)
    await this.recoverInterruptedPromotion()
    await this.removeIfPresent(this.candidatePath)
    const envelope: string = await this.cipher.encrypt(plaintext)
    // Verify the HUKS envelope in memory before replacing the prior encrypted
    // state, then verify the exact committed bytes once more after AtomicFile.
    const memoryVerified: string = await this.cipher.decrypt(envelope)
    if (memoryVerified !== plaintext) throw new Error('安全存储加密验证不一致')
    // Never verify by first replacing the authoritative secure file. A fresh
    // candidate is authenticated and compared at its own path, and only then
    // atomically promoted. Any candidate/write/verify error leaves both the
    // previously verified secure file and legacy plaintext untouched.
    await this.writeCandidate(envelope)
    await this.verifyEncryptedFile(this.candidatePath, plaintext)
    let priorSecureMoved: boolean = false
    if (await this.exists(this.securePath)) {
      // Never overwrite an unverified or damaged authority through save().
      // loadEncryptedFile also applies the repository's business validator.
      await this.loadEncryptedFile(this.securePath)
      await this.rename(this.securePath, this.backupPath)
      priorSecureMoved = true
    }
    try {
      // The destination is absent, so API 26 rename does not rely on an
      // implementation-specific replace-existing behavior. The candidate's
      // exact inode content was already authenticated and business-validated;
      // same-filesystem rename is the atomic commit point.
      await this.rename(this.candidatePath, this.securePath)
    } catch (promotionError) {
      // A verified prior state is recoverable even if immediate rollback
      // fails: backupPath remains authoritative for the next locked load().
      if (priorSecureMoved) {
        try {
          await this.recoverInterruptedPromotion()
        } catch (_) {
          // Preserve the initiating promotion/verification failure.
        }
      }
      throw promotionError
    }
    if (priorSecureMoved) await this.unlink(this.backupPath)
    // This is deliberately the final step. A failure above leaves a legacy
    // plaintext untouched, so migration can be retried without data loss.
    await this.removeLegacyAfterVerification()
  }

  save(plaintext: string): Promise<void> {
    const operation: Promise<void> = this.saveTail.then(async (): Promise<void> => {
      await this.withExclusiveLock(async (): Promise<void> => {
        await this.saveNow(plaintext)
      })
    })
    // Keep the queue live after a failed save while returning the original
    // rejecting Promise to its caller.
    this.saveTail = operation.then((): void => {}, (): void => {})
    return operation
  }

  clear(): Promise<void> {
    const operation: Promise<void> = this.saveTail.then(async (): Promise<void> => {
      await this.withExclusiveLock(async (): Promise<void> => {
        // Each unlink is conditional and therefore idempotent. Do not delete
        // the lock inode while another process may be queued on it, or the
        // shared HUKS alias needed by another encrypted repository.
        if (await this.exists(this.securePath)) await this.unlink(this.securePath)
        if (await this.exists(this.candidatePath)) await this.unlink(this.candidatePath)
        if (await this.exists(this.backupPath)) await this.unlink(this.backupPath)
        if (await this.exists(this.legacyPlaintextPath)) await this.unlink(this.legacyPlaintextPath)
      })
    })
    this.saveTail = operation.then((): void => {}, (): void => {})
    return operation
  }

  private async loadNow(): Promise<string | null> {
    await this.recoverInterruptedPromotion()
    // A process can die after writing a candidate but before promotion. It was
    // never authoritative and is safe to discard without inspecting content.
    if (await this.exists(this.candidatePath)) await this.unlink(this.candidatePath)
    if (await this.exists(this.securePath)) {
      // Do not catch this failure or look at the legacy path: authenticated
      // ciphertext damage is a hard failure, not an empty-state signal.
      const plaintext: string = await this.loadEncryptedFile(this.securePath)
      await this.removeLegacyAfterVerification()
      return plaintext
    }
    if (!await this.exists(this.legacyPlaintextPath)) return null
    const legacyPlaintext: string = await this.readText(this.legacyPlaintextPath)
    this.validatePlaintext(legacyPlaintext)
    // loadNow already owns the same repository's cross-process lock and local
    // queue slot, so migrate directly without recursively acquiring either.
    await this.saveNow(legacyPlaintext)
    return legacyPlaintext
  }

  load(): Promise<string | null> {
    const operation: Promise<string | null> = this.saveTail.then(
      async (): Promise<string | null> => {
        return await this.withExclusiveLock(async (): Promise<string | null> => {
          return await this.loadNow()
        })
      })
    // load, save and clear are totally ordered inside this process; the file
    // lock extends the same ordering across UIAbility and VPN Extension.
    this.saveTail = operation.then((): void => {}, (): void => {})
    return operation
  }
}
