import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { huks } from '@kit.UniversalKeystoreKit'

const ENVELOPE_SCHEMA_VERSION: number = 1
const ENVELOPE_ALGORITHM: string = 'HUKS-AES-256-GCM'
const AES_GCM_NONCE_BYTES: number = 12
const AES_GCM_TAG_BYTES: number = 16
// HUKS is a three-stage IPC API. Keep every update well below the IPC limit
// and aligned to the AES block size; the final (possibly shorter) segment is
// passed to finishSession so GCM can append or verify its authentication tag.
const HUKS_STREAM_CHUNK_BYTES: number = 32 * 1024

export interface SecureEnvelope {
  schemaVersion: number
  algorithm: string
  nonceBase64: string
  ciphertextBase64: string
  authTagBase64: string
}

/**
 * Encrypts private application data with a non-exportable, app-scoped HUKS
 * key. The key alias and AAD are deliberately non-sensitive constants. HUKS
 * binds the key material to this application on this device; only the nonce,
 * ciphertext and authentication tag leave the keystore operation.
 */
export class SecureCipher {
  private keyAlias: string
  private aad: Uint8Array
  private base64: util.Base64Helper = new util.Base64Helper()
  private encoder: util.TextEncoder = util.TextEncoder.create('utf-8')
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { fatal: true })

  constructor(keyAlias: string, aad: string) {
    if (keyAlias.length === 0 || aad.length === 0) throw new Error('安全存储参数无效')
    this.keyAlias = keyAlias
    this.aad = this.encoder.encodeInto(aad)
  }

  private keyProperties(): huks.HuksParam[] {
    return [{
      tag: huks.HuksTag.HUKS_TAG_ALGORITHM,
      value: huks.HuksKeyAlg.HUKS_ALG_AES
    }, {
      tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,
      value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256
    }, {
      tag: huks.HuksTag.HUKS_TAG_PURPOSE,
      value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT |
        huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
    }]
  }

  private async ensureKey(): Promise<void> {
    const emptyOptions: huks.HuksOptions = { properties: [] }
    let keyExists: boolean
    try {
      keyExists = await huks.hasKeyItem(this.keyAlias, emptyOptions)
    } catch (error) {
      // HUKS availability is part of the security boundary. Do not turn a
      // keystore failure into an empty key state or a software-crypto fallback.
      throw error
    }
    if (keyExists) return
    const options: huks.HuksOptions = { properties: this.keyProperties() }
    try {
      await huks.generateKeyItem(this.keyAlias, options)
    } catch (error) {
      // Another process can win the first-use key creation race. Only accept
      // the generation error when the exact alias now exists; otherwise keep
      // the initiating HUKS error intact for the caller.
      try {
        keyExists = await huks.hasKeyItem(this.keyAlias, emptyOptions)
      } catch (_) {
        // The generateKeyItem error remains the primary failure; a failed
        // race check is only cleanup/confirmation work and cannot replace it.
        throw error
      }
      if (keyExists) return
      throw error
    }
  }

  private operationProperties(purpose: huks.HuksKeyPurpose, nonce: Uint8Array,
    authTag: Uint8Array | null): huks.HuksParam[] {
    const properties: huks.HuksParam[] = [{
      tag: huks.HuksTag.HUKS_TAG_ALGORITHM,
      value: huks.HuksKeyAlg.HUKS_ALG_AES
    }, {
      tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,
      value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256
    }, {
      tag: huks.HuksTag.HUKS_TAG_PURPOSE,
      value: purpose
    }, {
      tag: huks.HuksTag.HUKS_TAG_PADDING,
      value: huks.HuksKeyPadding.HUKS_PADDING_NONE
    }, {
      tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE,
      value: huks.HuksCipherMode.HUKS_MODE_GCM
    }, {
      tag: huks.HuksTag.HUKS_TAG_NONCE,
      value: nonce
    }, {
      // Use the API 8+ GCM associated-data tag. The newer alias starts at
      // API 24 and is intentionally not part of the API 22 baseline.
      tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA,
      value: this.aad
    }, {
      tag: huks.HuksTag.HUKS_TAG_AE_TAG_LEN,
      value: AES_GCM_TAG_BYTES
    }]
    if (authTag !== null) {
      properties.push({
        tag: huks.HuksTag.HUKS_TAG_AE_TAG,
        value: authTag
      })
    }
    return properties
  }

  private async runOperation(properties: huks.HuksParam[], input: Uint8Array): Promise<Uint8Array> {
    let handle: number = -1
    let finished: boolean = false
    const outputParts: Uint8Array[] = []
    let outputLength: number = 0
    try {
      const initOptions: huks.HuksOptions = { properties: properties }
      const session: huks.HuksSessionHandle = await huks.initSession(this.keyAlias, initOptions)
      handle = session.handle

      let offset: number = 0
      // Retain one segment for finishSession. This mirrors the official HUKS
      // three-stage native helper and avoids sending a multi-megabyte payload
      // through a single ArkTS IPC request.
      while (input.length - offset > HUKS_STREAM_CHUNK_BYTES) {
        const chunk: Uint8Array = input.slice(offset, offset + HUKS_STREAM_CHUNK_BYTES)
        let updateResult: huks.HuksReturnResult
        try {
          const updateOptions: huks.HuksOptions = { properties: properties, inData: chunk }
          updateResult = await huks.updateSession(handle, updateOptions)
        } finally {
          chunk.fill(0)
        }
        if (updateResult.outData === undefined) {
          throw new Error('安全存储密码更新未返回数据')
        }
        const updateOutput: Uint8Array = updateResult.outData.slice()
        outputParts.push(updateOutput)
        outputLength += updateOutput.length
        offset += HUKS_STREAM_CHUNK_BYTES
      }

      const finalChunk: Uint8Array = input.slice(offset)
      let result: huks.HuksReturnResult
      try {
        const finishOptions: huks.HuksOptions = { properties: properties, inData: finalChunk }
        result = await huks.finishSession(handle, finishOptions)
      } finally {
        finalChunk.fill(0)
      }
      finished = true
      if (result.outData === undefined) throw new Error('安全存储密码操作未返回数据')
      const finishOutput: Uint8Array = result.outData.slice()
      outputParts.push(finishOutput)
      outputLength += finishOutput.length

      const combined: Uint8Array = new Uint8Array(outputLength)
      let outputOffset: number = 0
      for (const part of outputParts) {
        combined.set(part, outputOffset)
        outputOffset += part.length
        part.fill(0)
      }
      return combined
    } catch (error) {
      for (const part of outputParts) part.fill(0)
      // initSession does not expose a handle when it rejects. Once a handle is
      // available, however, every unfinished update/finish error path must
      // release it with abortSession. Abort failures never replace the
      // initiating HUKS error and no input/output data is logged.
      if (handle >= 0 && !finished) {
        try {
          await huks.abortSession(handle, { properties: [] })
        } catch (_) {
          // Preserve the original init/finish failure without logging data.
        }
      }
      throw error
    }
  }

  private isCanonicalBase64(value: string, allowEmpty: boolean = false): boolean {
    if (value.length === 0) return allowEmpty
    if (value.length % 4 !== 0) return false
    return /^[A-Za-z0-9+/]+={0,2}$/.test(value)
  }

  private decodeEnvelope(serialized: string): SecureEnvelope {
    let envelope: SecureEnvelope
    try {
      envelope = JSON.parse(serialized) as SecureEnvelope
    } catch (_) {
      throw new Error('安全存储封装不是有效 JSON')
    }
    if (envelope.schemaVersion !== ENVELOPE_SCHEMA_VERSION ||
      envelope.algorithm !== ENVELOPE_ALGORITHM ||
      typeof envelope.nonceBase64 !== 'string' ||
      typeof envelope.ciphertextBase64 !== 'string' ||
      typeof envelope.authTagBase64 !== 'string' ||
      !this.isCanonicalBase64(envelope.nonceBase64) ||
      !this.isCanonicalBase64(envelope.ciphertextBase64, true) ||
      !this.isCanonicalBase64(envelope.authTagBase64)) {
      throw new Error('安全存储封装版本或字段无效')
    }
    return envelope
  }

  async encrypt(plaintext: string): Promise<string> {
    await this.ensureKey()
    let nonceBlob: cryptoFramework.DataBlob
    try {
      // API 26 declares SystemCapability.Security.CryptoFramework.Rand. The
      // module targets only phone (where the SDK advertises this SysCap); if a
      // device nevertheless lacks it, fail closed rather than using a weaker
      // or deterministic nonce source.
      const random: cryptoFramework.Random = cryptoFramework.createRandom()
      nonceBlob = await random.generateRandom(AES_GCM_NONCE_BYTES)
    } catch (error) {
      throw error
    }
    const nonce: Uint8Array = nonceBlob.data
    if (nonce.length !== AES_GCM_NONCE_BYTES) throw new Error('安全随机数长度无效')
    const plaintextBytes: Uint8Array = this.encoder.encodeInto(plaintext)
    let sealed: Uint8Array
    try {
      const properties: huks.HuksParam[] = this.operationProperties(
        huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT, nonce, null)
      sealed = await this.runOperation(properties, plaintextBytes)
    } finally {
      plaintextBytes.fill(0)
    }
    if (sealed.length < AES_GCM_TAG_BYTES) throw new Error('安全存储密文长度无效')
    const ciphertext: Uint8Array = sealed.slice(0, sealed.length - AES_GCM_TAG_BYTES)
    const authTag: Uint8Array = sealed.slice(sealed.length - AES_GCM_TAG_BYTES)
    const envelope: SecureEnvelope = {
      schemaVersion: ENVELOPE_SCHEMA_VERSION,
      algorithm: ENVELOPE_ALGORITHM,
      nonceBase64: this.base64.encodeToStringSync(nonce),
      ciphertextBase64: this.base64.encodeToStringSync(ciphertext),
      authTagBase64: this.base64.encodeToStringSync(authTag)
    }
    return JSON.stringify(envelope)
  }

  async decrypt(serializedEnvelope: string): Promise<string> {
    // Reading must never create a replacement key for existing ciphertext.
    if (!await huks.hasKeyItem(this.keyAlias, { properties: [] })) throw new Error('原安全存储密钥不存在，原文件已保留')
    const envelope: SecureEnvelope = this.decodeEnvelope(serializedEnvelope)
    let nonce: Uint8Array
    let ciphertext: Uint8Array
    let authTag: Uint8Array
    try {
      nonce = this.base64.decodeSync(envelope.nonceBase64)
      ciphertext = this.base64.decodeSync(envelope.ciphertextBase64)
      authTag = this.base64.decodeSync(envelope.authTagBase64)
    } catch (_) {
      throw new Error('安全存储 Base64 字段无效')
    }
    if (nonce.length !== AES_GCM_NONCE_BYTES || authTag.length !== AES_GCM_TAG_BYTES) {
      throw new Error('安全存储 nonce、密文或认证标签长度无效')
    }
    const properties: huks.HuksParam[] = this.operationProperties(
      huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT, nonce, authTag)
    const plaintextBytes: Uint8Array = await this.runOperation(properties, ciphertext)
    try {
      return this.decoder.decodeToString(plaintextBytes)
    } finally {
      plaintextBytes.fill(0)
    }
  }
}
