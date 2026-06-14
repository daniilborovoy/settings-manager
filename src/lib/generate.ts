export type SecretKind = 'api-key' | 'password' | 'hex'

const ALPHANUMERIC = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
// Symbols that are safe in shell/env-file contexts (no quotes, spaces, or backslash).
const SYMBOLS = '!#$%&*+-=?@^_'
const HEX = '0123456789abcdef'

export interface SecretPreset {
  kind: SecretKind
  label: string
  length: number
  symbols: boolean
  hasSymbols: boolean
}

export const SECRET_PRESETS: SecretPreset[] = [
  { kind: 'api-key', label: 'API key', length: 32, symbols: false, hasSymbols: false },
  { kind: 'password', label: 'Password', length: 20, symbols: true, hasSymbols: true },
  { kind: 'hex', label: 'Hex token', length: 64, symbols: false, hasSymbols: false },
]

export const MIN_LENGTH = 8
export const MAX_LENGTH = 128

function charsetFor(kind: SecretKind, symbols: boolean): string {
  if (kind === 'hex') return HEX
  return symbols ? ALPHANUMERIC + SYMBOLS : ALPHANUMERIC
}

// Draws `length` characters uniformly from `charset` using crypto randomness.
// Rejection sampling discards bytes above the largest whole multiple of the
// charset size, which avoids the modulo bias a plain `byte % n` would introduce.
function randomString(length: number, charset: string): string {
  const n = charset.length
  const limit = Math.floor(256 / n) * n
  const out: string[] = []
  const buffer = new Uint8Array(Math.max(length, 16))

  while (out.length < length) {
    crypto.getRandomValues(buffer)
    for (let i = 0; i < buffer.length && out.length < length; i++) {
      if (buffer[i] < limit) out.push(charset[buffer[i] % n])
    }
  }

  return out.join('')
}

export function generateSecret(kind: SecretKind, length: number, symbols = false): string {
  return randomString(length, charsetFor(kind, symbols))
}
