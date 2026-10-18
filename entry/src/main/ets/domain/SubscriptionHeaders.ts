import type { SubscriptionHeaders } from './Models.ts'
import { decodeBase64Text, decodeUrlComponent } from './TextCodec.ts'

function escapePattern(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

export function responseHeaderValue(serializedHeaders: string, name: string): string {
  const escaped: string = escapePattern(name)
  const stringPattern: RegExp = new RegExp(`"${escaped}"\\s*:\\s*"([^"\\r\\n]*)"`, 'i')
  const stringMatch: RegExpMatchArray | null = serializedHeaders.match(stringPattern)
  if (stringMatch && stringMatch.length > 1) return stringMatch[1]
  const arrayPattern: RegExp = new RegExp(`"${escaped}"\\s*:\\s*\\[\\s*"([^"\\r\\n]*)"`, 'i')
  const arrayMatch: RegExpMatchArray | null = serializedHeaders.match(arrayPattern)
  return arrayMatch && arrayMatch.length > 1 ? arrayMatch[1] : ''
}

function profileTitle(value: string): string {
  const trimmed: string = value.trim()
  if (trimmed.toLowerCase().startsWith('base64:')) {
    try {
      return decodeBase64Text(trimmed.slice('base64:'.length)).trim()
    } catch (_) {
      return ''
    }
  }
  return decodeUrlComponent(trimmed)
}

export function parseSubscriptionHeaders(serializedHeaders: string): SubscriptionHeaders {
  return {
    title: profileTitle(responseHeaderValue(serializedHeaders, 'profile-title')),
    subscriptionUserInfo: responseHeaderValue(serializedHeaders, 'subscription-userinfo')
  }
}

