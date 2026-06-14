import { useEffect, useRef, useState } from 'react'
import { SECRET_PRESETS, MIN_LENGTH, MAX_LENGTH, generateSecret } from '../lib/generate'

export default function SecretGenerator({ onUse, tone = 'light' }) {
  const [open, setOpen] = useState(false)
  const [presetIndex, setPresetIndex] = useState(0)
  const [length, setLength] = useState(SECRET_PRESETS[0].length)
  const [symbols, setSymbols] = useState(SECRET_PRESETS[0].symbols)
  const [secret, setSecret] = useState('')
  const [copied, setCopied] = useState(false)
  const rootRef = useRef(null)

  const preset = SECRET_PRESETS[presetIndex]

  function regenerate(len = length, useSymbols = symbols, kind = preset.kind) {
    setSecret(generateSecret(kind, len, useSymbols))
    setCopied(false)
  }

  // Generate a fresh secret whenever the popover opens.
  useEffect(() => {
    if (open) regenerate()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open])

  // Close on outside click or Escape. The capture-phase Escape handler stops the
  // event before the host modal's window-level listener can also close the modal.
  useEffect(() => {
    if (!open) return

    function onPointerDown(event) {
      if (rootRef.current && !rootRef.current.contains(event.target)) setOpen(false)
    }
    function onKeyDown(event) {
      if (event.key === 'Escape') {
        event.stopPropagation()
        setOpen(false)
      }
    }

    document.addEventListener('mousedown', onPointerDown)
    document.addEventListener('keydown', onKeyDown, true)
    return () => {
      document.removeEventListener('mousedown', onPointerDown)
      document.removeEventListener('keydown', onKeyDown, true)
    }
  }, [open])

  function selectPreset(index) {
    const next = SECRET_PRESETS[index]
    setPresetIndex(index)
    setLength(next.length)
    setSymbols(next.symbols)
    regenerate(next.length, next.symbols, next.kind)
  }

  function handleLength(value) {
    const clamped = Math.max(MIN_LENGTH, Math.min(MAX_LENGTH, value || MIN_LENGTH))
    setLength(clamped)
    regenerate(clamped, symbols, preset.kind)
  }

  function handleSymbols(value) {
    setSymbols(value)
    regenerate(length, value, preset.kind)
  }

  async function copy() {
    try {
      await navigator.clipboard.writeText(secret)
      setCopied(true)
      window.setTimeout(() => setCopied(false), 1500)
    } catch {}
  }

  function use() {
    onUse(secret)
    setOpen(false)
  }

  return (
    <div className="secret-gen" ref={rootRef}>
      <button
        type="button"
        className={`btn-icon ${tone === 'dark' ? 'btn-icon-dark' : ''}`}
        onClick={() => setOpen(value => !value)}
        title="Generate a secure API key or password"
      >
        Generate
      </button>

      {open && (
        <div className="secret-gen-popover">
          <div className="secret-gen-tabs">
            {SECRET_PRESETS.map((p, index) => (
              <button
                key={p.kind}
                type="button"
                className={`secret-gen-tab ${index === presetIndex ? 'active' : ''}`}
                onClick={() => selectPreset(index)}
              >
                {p.label}
              </button>
            ))}
          </div>

          <div className="secret-gen-preview">
            <code className="secret-gen-value">{secret}</code>
            <button
              type="button"
              className="secret-gen-refresh"
              onClick={() => regenerate()}
              title="Regenerate"
            >
              ↻
            </button>
          </div>

          <div className="secret-gen-controls">
            <label className="secret-gen-length">
              <span>Length</span>
              <input
                type="number"
                min={MIN_LENGTH}
                max={MAX_LENGTH}
                value={length}
                onChange={event => handleLength(Number(event.target.value))}
              />
            </label>
            {preset.hasSymbols && (
              <label className="secret-gen-symbols">
                <input
                  type="checkbox"
                  checked={symbols}
                  onChange={event => handleSymbols(event.target.checked)}
                />
                <span>Symbols</span>
              </label>
            )}
          </div>

          <div className="secret-gen-actions">
            <button type="button" className="secret-gen-copy" onClick={copy}>
              {copied ? 'Copied' : 'Copy'}
            </button>
            <button type="button" className="secret-gen-use" onClick={use}>
              Use value
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
