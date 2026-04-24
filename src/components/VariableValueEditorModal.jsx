import { useState, useMemo } from 'react'
import CodeMirror from '@uiw/react-codemirror'
import { oneDark } from '@codemirror/theme-one-dark'
import { useModalClose } from '../lib/useModalClose'
import { detectLang, formatEditorValue, getCodeMirrorExtensions, LANGS } from '../lib/codeEditor'

export default function VariableValueEditorModal({ varKey, value, onSave, onClose }) {
  const [lang, setLang] = useState(() => detectLang(value))
  const [draft, setDraft] = useState(value)
  const [formatError, setFormatError] = useState('')
  const { closing, requestClose } = useModalClose(onClose)

  const extensions = useMemo(() => getCodeMirrorExtensions(lang), [lang])

  function handleFormat() {
    try {
      setDraft(formatEditorValue(draft, lang))
      setFormatError('')
    } catch (error) {
      setFormatError(error.message || 'Failed to format value')
    }
  }

  function handleSave() {
    onSave(draft)
    requestClose()
  }

  return (
    <div className={`modal-backdrop editor-backdrop ${closing ? 'closing' : ''}`}>
      <div className="var-value-modal" onClick={e => e.stopPropagation()}>
        <div className="modal-header">
          <h2 className="var-value-modal-key">{varKey}</h2>
          <div className="editor-modal-actions">
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
            <button className="btn-icon btn-icon-dark" onClick={handleFormat} type="button">
              Format
            </button>
            <button className="btn-close" onClick={requestClose}>×</button>
          </div>
        </div>

        {formatError && <div className="editor-format-error">{formatError}</div>}

        <div className="var-value-cm">
          <CodeMirror
            value={draft}
            onChange={nextValue => {
              setDraft(nextValue)
              if (formatError) setFormatError('')
            }}
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
