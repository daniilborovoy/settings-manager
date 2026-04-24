import { useMemo, useState } from 'react'
import CodeMirror from '@uiw/react-codemirror'
import { oneDark } from '@codemirror/theme-one-dark'
import { useModalClose } from '../lib/useModalClose'
import { detectLang, formatEditorValue, getCodeMirrorExtensions, LANGS } from '../lib/codeEditor'

const TYPES = [
  { value: 'env_var', label: 'Variable' },
  { value: 'file', label: 'File' },
]

function visibilityFromFlags({ masked, hidden }) {
  if (masked && hidden) return 'masked_hidden'
  if (masked) return 'masked'
  return 'visible'
}

function flagsFromVisibility(visibility) {
  switch (visibility) {
    case 'masked_hidden': return { masked: true, hidden: true }
    case 'masked': return { masked: true, hidden: false }
    default: return { masked: false, hidden: false }
  }
}

export default function EditGitlabVariableModal({ variable, isNew, onSave, onClose }) {
  const [draft, setDraft] = useState({ ...variable })
  const [lang, setLang] = useState(() => detectLang(variable.value || ''))
  const [formatError, setFormatError] = useState('')
  const { closing, requestClose } = useModalClose(onClose)

  const visibility = visibilityFromFlags(draft)
  const expand = !(draft.raw ?? false)

  const extensions = useMemo(() => getCodeMirrorExtensions(lang), [lang])

  function update(patch) {
    setDraft(prev => ({ ...prev, ...patch }))
  }

  function handleVisibilityChange(v) {
    update(flagsFromVisibility(v))
  }

  function handleFormat() {
    try {
      update({ value: formatEditorValue(draft.value || '', lang) })
      setFormatError('')
    } catch (error) {
      setFormatError(error.message || 'Failed to format value')
    }
  }

  function handleSubmit(e) {
    e.preventDefault()
    if (!draft.key.trim()) return
    onSave(draft)
    requestClose()
  }

  return (
    <div className={`modal-backdrop editor-backdrop ${closing ? 'closing' : ''}`}>
      <div className="modal gitlab-var-modal" onClick={e => e.stopPropagation()}>
        <div className="modal-header">
          <h2>{isNew ? 'Add variable' : 'Edit variable'}</h2>
          <button className="btn-close" onClick={requestClose} type="button">×</button>
        </div>
        <form onSubmit={handleSubmit}>
          <div className="gitlab-var-grid">
            <div className="form-group">
              <label>Type</label>
              <select
                style={{height: "36px"}}
                value={draft.variable_type ?? 'env_var'}
                onChange={e => update({ variable_type: e.target.value })}
              >
                {TYPES.map(t => (
                  <option key={t.value} value={t.value}>{t.label}</option>
                ))}
              </select>
            </div>

            <div className="form-group">
              <label>Environment scope</label>
              <input
                type="text"
                value={draft.environment_scope ?? '*'}
                onChange={e => update({ environment_scope: e.target.value })}
                placeholder="* (All)"
              />
            </div>
          </div>

          <div className="form-group">
            <label>Visibility</label>
            <div className="radio-list">
              <label className="radio-item">
                <input
                  type="radio"
                  name="visibility"
                  checked={visibility === 'visible'}
                  onChange={() => handleVisibilityChange('visible')}
                />
                <div>
                  <strong>Visible</strong>
                  <span>Can be seen in job logs.</span>
                </div>
              </label>
              <label className="radio-item">
                <input
                  type="radio"
                  name="visibility"
                  checked={visibility === 'masked'}
                  onChange={() => handleVisibilityChange('masked')}
                />
                <div>
                  <strong>Masked</strong>
                  <span>Masked in job logs but can be revealed in CI/CD settings.</span>
                </div>
              </label>
              <label className="radio-item">
                <input
                  type="radio"
                  name="visibility"
                  checked={visibility === 'masked_hidden'}
                  onChange={() => handleVisibilityChange('masked_hidden')}
                  disabled={!isNew}
                />
                <div>
                  <strong>Masked and hidden</strong>
                  <span>
                    {isNew
                      ? 'Masked in job logs and can never be revealed again.'
                      : 'Only configurable when creating a new variable.'}
                  </span>
                </div>
              </label>
            </div>
          </div>

          <div className="form-group">
            <label>Flags</label>
            <div className="checkbox-list">
              <label className="checkbox-item">
                <input
                  type="checkbox"
                  checked={draft.protected ?? false}
                  onChange={e => update({ protected: e.target.checked })}
                />
                <div>
                  <strong>Protect variable</strong>
                  <span>Export variable only to pipelines running on protected branches and tags.</span>
                </div>
              </label>
              <label className="checkbox-item">
                <input
                  type="checkbox"
                  checked={expand}
                  onChange={e => update({ raw: !e.target.checked })}
                />
                <div>
                  <strong>Expand variable reference</strong>
                  <span>$ will be treated as the start of a reference to another variable.</span>
                </div>
              </label>
            </div>
          </div>

          <div className="form-group">
            <label>Description (optional)</label>
            <input
              type="text"
              value={draft.description ?? ''}
              onChange={e => update({ description: e.target.value || null })}
              placeholder="The description of the variable's value or usage."
            />
          </div>

          <div className="form-group">
            <label>Key</label>
            <input
              type="text"
              value={draft.key}
              onChange={e => update({ key: e.target.value })}
              placeholder="VARIABLE_KEY"
              required
            />
          </div>

          <div className="form-group">
            <div className="value-label-row">
              <label>Value</label>
              <div className="value-actions">
                <div className="lang-tabs">
                  {LANGS.map(l => (
                    <button
                      key={l}
                      type="button"
                      className={`lang-tab ${lang === l ? 'active' : ''}`}
                      onClick={() => setLang(l)}
                    >
                      {l === 'text' ? 'Plain' : l.toUpperCase()}
                    </button>
                  ))}
                </div>
                <button
                  type="button"
                  className="btn-icon"
                  onClick={handleFormat}
                  title="Format value"
                >
                  Format
                </button>
              </div>
            </div>
            {formatError && <div className="editor-format-error editor-format-error-light">{formatError}</div>}
            <div className="value-editor">
              <CodeMirror
                value={draft.value}
                onChange={v => {
                  update({ value: v })
                  if (formatError) setFormatError('')
                }}
                extensions={extensions}
                theme={oneDark}
                height="100%"
                style={{ height: '100%', fontSize: '13px' }}
              />
            </div>
          </div>

          <div className="modal-footer">
            <button type="button" className="btn-secondary" onClick={requestClose}>Cancel</button>
            <button type="submit" className="btn-primary" disabled={!draft.key.trim()}>
              {isNew ? 'Add variable' : 'Save changes'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
