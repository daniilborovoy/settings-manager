import { useState, useMemo } from 'react'
import CodeMirror from '@uiw/react-codemirror'
import { yaml } from '@codemirror/lang-yaml'
import { StreamLanguage } from '@codemirror/language'
import { toml } from '@codemirror/legacy-modes/mode/toml'
import { oneDark } from '@codemirror/theme-one-dark'
import { useModalClose } from '../lib/useModalClose'

const LANGS = ['yaml', 'toml', 'text']

function detectLang(value) {
  if (/^---(\n|$)/.test(value) || /^\w[\w.]*:\s+\S/m.test(value)) return 'yaml'
  if (/^\[[\w.]+\]/m.test(value) || /^\w[\w.]*\s*=\s*\S/m.test(value)) return 'toml'
  return 'text'
}

export default function VariableValueEditorModal({ varKey, value, onSave, onClose }) {
  const [lang, setLang] = useState(() => detectLang(value))
  const [draft, setDraft] = useState(value)
  const { closing, requestClose } = useModalClose(onClose)

  const extensions = useMemo(() => {
    if (lang === 'yaml') return [yaml()]
    if (lang === 'toml') return [StreamLanguage.define(toml)]
    return []
  }, [lang])

  function handleSave() {
    onSave(draft)
    requestClose()
  }

  return (
    <div className={`modal-backdrop ${closing ? 'closing' : ''}`} onClick={requestClose}>
      <div className="var-value-modal" onClick={e => e.stopPropagation()}>
        <div className="modal-header">
          <h2 className="var-value-modal-key">{varKey}</h2>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <div className="lang-tabs">
              {LANGS.map(l => (
                <button
                  key={l}
                  className={`lang-tab ${lang === l ? 'active' : ''}`}
                  onClick={() => setLang(l)}
                >
                  {l === 'text' ? 'Plain Text' : l.toUpperCase()}
                </button>
              ))}
            </div>
            <button className="btn-close" onClick={requestClose}>×</button>
          </div>
        </div>

        <div className="var-value-cm">
          <CodeMirror
            value={draft}
            onChange={setDraft}
            extensions={extensions}
            theme={oneDark}
            height="100%"
            style={{ height: '100%', fontSize: '13px' }}
          />
        </div>

        <div className="modal-footer">
          <button className="btn-secondary" onClick={requestClose}>Cancel</button>
          <button className="btn-primary" onClick={handleSave}>Save</button>
        </div>
      </div>
    </div>
  )
}
