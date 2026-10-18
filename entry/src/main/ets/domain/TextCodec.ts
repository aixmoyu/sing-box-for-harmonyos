const BASE64_ALPHABET: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

function normalizedBase64(input: string): string {
  let value: string = input.trim().replace(/-/g, '+').replace(/_/g, '/').replace(/\s/g, '')
  while (value.length % 4 !== 0) {
    value += '='
  }
  return value
}

export function decodeBase64Bytes(input: string): number[] {
  const value: string = normalizedBase64(input)
  const bytes: number[] = []
  let buffer: number = 0
  let bits: number = 0

  for (let index: number = 0; index < value.length; index++) {
    const character: string = value.charAt(index)
    if (character === '=') {
      break
    }
    const digit: number = BASE64_ALPHABET.indexOf(character)
    if (digit < 0) {
      throw new Error('订阅包含无效的 Base64 字符')
    }
    buffer = (buffer << 6) | digit
    bits += 6
    if (bits >= 8) {
      bits -= 8
      bytes.push((buffer >> bits) & 0xff)
    }
  }
  return bytes
}

export function decodeUtf8(bytes: number[]): string {
  let result: string = ''
  let index: number = 0
  while (index < bytes.length) {
    const first: number = bytes[index]
    if (first < 0x80) {
      result += String.fromCharCode(first)
      index += 1
    } else if ((first & 0xe0) === 0xc0 && index + 1 < bytes.length) {
      const codePoint: number = ((first & 0x1f) << 6) | (bytes[index + 1] & 0x3f)
      result += String.fromCharCode(codePoint)
      index += 2
    } else if ((first & 0xf0) === 0xe0 && index + 2 < bytes.length) {
      const codePoint: number = ((first & 0x0f) << 12) |
        ((bytes[index + 1] & 0x3f) << 6) |
        (bytes[index + 2] & 0x3f)
      result += String.fromCharCode(codePoint)
      index += 3
    } else if ((first & 0xf8) === 0xf0 && index + 3 < bytes.length) {
      const codePoint: number = ((first & 0x07) << 18) |
        ((bytes[index + 1] & 0x3f) << 12) |
        ((bytes[index + 2] & 0x3f) << 6) |
        (bytes[index + 3] & 0x3f)
      const adjusted: number = codePoint - 0x10000
      result += String.fromCharCode(0xd800 + (adjusted >> 10))
      result += String.fromCharCode(0xdc00 + (adjusted & 0x3ff))
      index += 4
    } else {
      result += '\uFFFD'
      index += 1
    }
  }
  return result
}

export function decodeBase64Text(input: string): string {
  return decodeUtf8(decodeBase64Bytes(input))
}

export function decodeUrlComponent(input: string): string {
  try {
    // Share links use RFC 3986 URI components, not HTML form encoding. A
    // literal `+` is therefore part of a password/UUID/name and must not be
    // rewritten to a space; `%2B` is decoded by decodeURIComponent itself.
    return decodeURIComponent(input)
  } catch (_) {
    return input
  }
}

export function fnv1aId(input: string): string {
  let hash: number = 0x811c9dc5
  for (let index: number = 0; index < input.length; index++) {
    hash ^= input.charCodeAt(index)
    hash = Math.imul(hash, 0x01000193)
  }
  return `node-${(hash >>> 0).toString(16).padStart(8, '0')}`
}
