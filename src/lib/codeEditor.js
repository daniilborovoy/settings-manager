import YAML from 'yaml'
import { yaml } from '@codemirror/lang-yaml'
import { StreamLanguage } from '@codemirror/language'
import { toml } from '@codemirror/legacy-modes/mode/toml'
import parseToml from '@iarna/toml/parse-string'
import stringifyToml from '@iarna/toml/stringify'

export const LANGS = ['yaml', 'toml', 'text']

export function detectLang(value = '') {
  if (/^---(\n|$)/.test(value) || /^\w[\w.-]*:\s+\S/m.test(value)) return 'yaml'
  if (/^\[[\w.-]+\]/m.test(value) || /^\w[\w.-]*\s*=\s*\S/m.test(value)) return 'toml'
  return 'text'
}

export function getCodeMirrorExtensions(lang) {
  if (lang === 'yaml') return [yaml()]
  if (lang === 'toml') return [StreamLanguage.define(toml)]
  return []
}

export function formatEditorValue(value, lang) {
  if (!value) return ''

  if (lang === 'yaml') {
    const doc = YAML.parseDocument(value)
    if (doc.errors.length > 0) throw doc.errors[0]
    return String(doc)
  }

  if (lang === 'toml') {
    return stripTomlNumericSeparators(stringifyToml(parseToml(value)))
  }

  return normalizePlainText(value)
}

function normalizePlainText(value) {
  const normalized = value
    .replace(/\r\n?/g, '\n')
    .split('\n')
    .map(line => line.replace(/[ \t]+$/g, ''))
    .join('\n')

  if (normalized && normalized.includes('\n') && !normalized.endsWith('\n')) {
    return `${normalized}\n`
  }

  return normalized
}

function stripTomlNumericSeparators(value) {
  let result = ''
  let token = ''
  let inBasicString = false
  let inLiteralString = false
  let inMultilineBasicString = false
  let inMultilineLiteralString = false

  for (let i = 0; i < value.length; i += 1) {
    const char = value[i]
    const next3 = value.slice(i, i + 3)

    if (inMultilineBasicString) {
      if (next3 === '"""') {
        result += next3
        i += 2
        inMultilineBasicString = false
      } else {
        result += char
      }
      continue
    }

    if (inMultilineLiteralString) {
      if (next3 === "'''") {
        result += next3
        i += 2
        inMultilineLiteralString = false
      } else {
        result += char
      }
      continue
    }

    if (inBasicString) {
      result += char
      if (char === '\\') {
        result += value[i + 1] ?? ''
        i += 1
      } else if (char === '"') {
        inBasicString = false
      }
      continue
    }

    if (inLiteralString) {
      result += char
      if (char === "'") inLiteralString = false
      continue
    }

    if (next3 === '"""') {
      flushToken()
      result += next3
      i += 2
      inMultilineBasicString = true
      continue
    }

    if (next3 === "'''") {
      flushToken()
      result += next3
      i += 2
      inMultilineLiteralString = true
      continue
    }

    if (char === '"') {
      flushToken()
      result += char
      inBasicString = true
      continue
    }

    if (char === "'") {
      flushToken()
      result += char
      inLiteralString = true
      continue
    }

    if (/[A-Za-z0-9_+.-]/.test(char)) {
      token += char
      continue
    }

    flushToken()
    result += char
  }

  flushToken()
  return result

  function flushToken() {
    if (!token) return
    result += normalizeTomlNumberToken(token)
    token = ''
  }
}

function normalizeTomlNumberToken(token) {
  if (/^[+-]?\d[\d_]*$/.test(token)) {
    return token.replace(/_/g, '')
  }

  if (/^[+-]?\d[\d_]*(\.\d[\d_]*)?([eE][+-]?\d[\d_]*)?$/.test(token) && token.includes('_')) {
    return token.replace(/_/g, '')
  }

  return token
}
