import { useState } from 'react'
import VariableValueEditorModal from './VariableValueEditorModal'
import EditGitlabVariableModal from './EditGitlabVariableModal'
import { newGitlabVariable, newLambdaVariable } from '../lib/variables'

export default function VariableEditor({
  source, sources, variables, onChange, onSave, onRefresh, onCopyFrom,
  loading, saving, isDirty, error, saveSuccess,
}) {
  const [showValues, setShowValues] = useState(false)
  const [search, setSearch] = useState('')
  const [newKey, setNewKey] = useState('')
  const [newValue, setNewValue] = useState('')
  const [copyingFrom, setCopyingFrom] = useState(false)
  const [editing, setEditing] = useState(null) // { index, isNew }

  const isGitlab = source.type === 'gitlab_cicd'
  const otherSources = sources.filter(s => s.id !== source.id)

  async function handleCopyFrom(e) {
    const fromId = Number(e.target.value)
    if (!fromId) return
    e.target.value = ''
    setCopyingFrom(true)
    try {
      await onCopyFrom(fromId)
    } finally {
      setCopyingFrom(false)
    }
  }

  const filtered = variables
    .map((v, index) => ({ v, index }))
    .filter(({ v }) => v.key.toLowerCase().includes(search.toLowerCase()))

  function updateAt(index, patch) {
    onChange(prev => prev.map((v, i) => i === index ? { ...v, ...patch } : v))
  }

  function replaceAt(index, nextVar) {
    onChange(prev => prev.map((v, i) => i === index ? { ...v, ...nextVar } : v))
  }

  function deleteAt(index) {
    onChange(prev => prev.filter((_, i) => i !== index))
  }

  function appendVar(newVar) {
    onChange(prev => [...prev, newVar])
  }

  function handleQuickAdd() {
    const key = newKey.trim()
    if (!key) return
    const next = isGitlab
      ? newGitlabVariable({ key, value: newValue })
      : newLambdaVariable({ key, value: newValue })
    appendVar(next)
    setNewKey('')
    setNewValue('')
  }

  function openEditor(index) {
    setEditing({ index, isNew: false })
  }

  function openNewGitlabVariable() {
    appendVar(newGitlabVariable())
    // Edit the just-added variable
    setEditing({ index: variables.length, isNew: true })
  }

  function badgeList(v) {
    const badges = []
    if (v.variable_type === 'file') badges.push({ label: 'file', className: 'badge-file' })
    if (v.protected) badges.push({ label: 'protected', className: 'badge-protected' })
    if (v.masked && v.hidden) badges.push({ label: 'masked • hidden', className: 'badge-masked' })
    else if (v.masked) badges.push({ label: 'masked', className: 'badge-masked' })
    if (v.raw) badges.push({ label: 'raw', className: 'badge-raw' })
    const scope = v.environment_scope
    if (scope && scope !== '*') badges.push({ label: `@${scope}`, className: 'badge-scope' })
    return badges
  }

  if (loading) {
    return (
      <div className="editor-loading">
        <div className="spinner" />
        <p>Loading variables...</p>
      </div>
    )
  }

  const editingVar = editing ? variables[editing.index] : null

  return (
    <div className="variable-editor">
      <div className="editor-header">
        <div className="editor-title">
          <h2>{source.name}</h2>
          <span className="var-count">{variables.length} variable{variables.length === 1 ? '' : 's'}</span>
        </div>
        <div className="editor-actions">
          {saveSuccess && <span className="success-msg">Saved successfully</span>}
          <button className="btn-secondary" onClick={onRefresh}>Refresh</button>
          <button
            className="btn-primary"
            onClick={onSave}
            disabled={!isDirty || saving}
          >
            {saving ? 'Saving...' : isDirty ? 'Save Changes' : 'No Changes'}
          </button>
        </div>
      </div>

      {error && <div className="editor-error">{error}</div>}

      <div className="editor-toolbar">
        <input
          className="search-input"
          type="text"
          placeholder="Search variables..."
          value={search}
          onChange={e => setSearch(e.target.value)}
        />
        {otherSources.length > 0 && (
          <select
            className="copy-from-select"
            defaultValue=""
            onChange={handleCopyFrom}
            disabled={copyingFrom}
          >
            <option value="" disabled>{copyingFrom ? 'Copying...' : 'Copy from...'}</option>
            {otherSources.map(s => (
              <option key={s.id} value={s.id}>
                {s.projectName ? `${s.projectName} / ${s.name}` : s.name}
              </option>
            ))}
          </select>
        )}
        <button className="btn-secondary" onClick={() => setShowValues(v => !v)}>
          {showValues ? 'Hide Values' : 'Show Values'}
        </button>
      </div>

      <div className="variables-table">
        <div className="table-header">
          <span>Key</span>
          <span>Value</span>
          <span />
        </div>
        {filtered.length === 0 && (
          <p className="no-vars">
            {search ? 'No variables match your search' : 'No variables yet'}
          </p>
        )}
        {filtered.map(({ v, index }) => {
          const badges = isGitlab ? badgeList(v) : []
          return (
            <div key={v._clientId ?? index} className="table-row">
              <div className="var-key-cell">
                <span className="var-key">{v.key || <em className="var-key-empty">(unnamed)</em>}</span>
                {badges.length > 0 && (
                  <span className="var-badges">
                    {badges.map((b, i) => (
                      <span key={i} className={`var-badge ${b.className}`}>{b.label}</span>
                    ))}
                  </span>
                )}
              </div>
              <input
                type={showValues ? 'text' : 'password'}
                className="var-value"
                value={v.value}
                onChange={e => updateAt(index, { value: e.target.value })}
                placeholder={v.hidden ? '(hidden — set new value to replace)' : ''}
              />
              <button
                className="btn-expand-var"
                onClick={() => openEditor(index)}
                title={isGitlab ? 'Edit variable' : 'Open in editor'}
              >
                ⤢
              </button>
              <button
                className="btn-delete-var"
                onClick={() => deleteAt(index)}
                title="Delete variable"
              >
                ×
              </button>
            </div>
          )
        })}
      </div>

      {isGitlab ? (
        <div className="add-variable add-variable-gitlab">
          <button className="btn-secondary" onClick={openNewGitlabVariable}>
            + Add variable
          </button>
          <span className="add-variable-hint">
            Use the full editor to set type, scope, and flags.
          </span>
        </div>
      ) : (
        <div className="add-variable">
          <input
            type="text"
            className="add-key"
            placeholder="NEW_VARIABLE_KEY"
            value={newKey}
            onChange={e => setNewKey(e.target.value)}
            onKeyDown={e => e.key === 'Enter' && handleQuickAdd()}
          />
          <input
            type={showValues ? 'text' : 'password'}
            className="add-value"
            placeholder="value"
            value={newValue}
            onChange={e => setNewValue(e.target.value)}
            onKeyDown={e => e.key === 'Enter' && handleQuickAdd()}
          />
          <button className="btn-secondary" onClick={handleQuickAdd} disabled={!newKey.trim()}>
            + Add
          </button>
        </div>
      )}

      {editing && editingVar && (
        isGitlab ? (
          <EditGitlabVariableModal
            variable={editingVar}
            isNew={editing.isNew}
            onSave={next => replaceAt(editing.index, next)}
            onClose={() => {
              // If it was a new empty variable and user cancelled without giving it a key, drop it
              if (editing.isNew && !variables[editing.index]?.key) {
                deleteAt(editing.index)
              }
              setEditing(null)
            }}
          />
        ) : (
          <VariableValueEditorModal
            varKey={editingVar.key}
            value={editingVar.value ?? ''}
            onSave={val => updateAt(editing.index, { value: val })}
            onClose={() => setEditing(null)}
          />
        )
      )}
    </div>
  )
}
