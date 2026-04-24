import { useState } from 'react'
import { useModalClose } from '../lib/useModalClose'

const SOURCE_TYPES = [
  { value: 'lambda', label: 'AWS Lambda' },
  { value: 'gitlab_cicd', label: 'GitLab CI/CD' },
]

const FIELDS = {
  lambda: [
    { key: 'function_name', label: 'Function Name', placeholder: 'ai-sourcing-bot-prod' },
    { key: 'aws_region', label: 'AWS Region', placeholder: 'eu-west-1' },
    { key: 'aws_access_key_id', label: 'AWS Access Key ID', placeholder: 'AKIAIOSFODNN7EXAMPLE' },
    { key: 'aws_secret_access_key', label: 'AWS Secret Access Key', type: 'password', placeholder: '••••••••' },
  ],
  gitlab_cicd: [
    { key: 'gitlab_url', label: 'GitLab URL', placeholder: 'https://gitlab.company.com' },
    { key: 'project_id', label: 'Project ID or Path', placeholder: '123 or namespace/project' },
    { key: 'private_token', label: 'Private Token', type: 'password', placeholder: 'glpat-••••••••' },
  ],
}

export default function AddSourceModal({ onClose, onAdd, projectName }) {
  const [name, setName] = useState('')
  const [type, setType] = useState('lambda')
  const [config, setConfig] = useState({})
  const [error, setError] = useState(null)
  const [loading, setLoading] = useState(false)
  const { closing, requestClose } = useModalClose(onClose)

  async function handleSubmit(e) {
    e.preventDefault()
    setError(null)
    setLoading(true)
    try {
      await onAdd({ name, type, config })
      requestClose()
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className={`modal-backdrop ${closing ? 'closing' : ''}`} onClick={requestClose}>
      <div className="modal" onClick={e => e.stopPropagation()}>
        <div className="modal-header">
          <h2>{projectName ? `Add Source to ${projectName}` : 'Add Source'}</h2>
          <button className="btn-close" onClick={requestClose}>×</button>
        </div>
        <form onSubmit={handleSubmit}>
          <div className="form-group">
            <label>Name</label>
            <input
              type="text"
              value={name}
              onChange={e => setName(e.target.value)}
              placeholder="My Lambda / My GitLab Project"
              required
            />
          </div>
          <div className="form-group">
            <label>Type</label>
            <select value={type} onChange={e => { setType(e.target.value); setConfig({}) }}>
              {SOURCE_TYPES.map(t => (
                <option key={t.value} value={t.value}>{t.label}</option>
              ))}
            </select>
          </div>
          {FIELDS[type]?.map(field => (
            <div className="form-group" key={field.key}>
              <label>{field.label}</label>
              <input
                type={field.type || 'text'}
                value={config[field.key] || ''}
                onChange={e => setConfig(prev => ({ ...prev, [field.key]: e.target.value }))}
                placeholder={field.placeholder}
                required
              />
            </div>
          ))}
          {error && <p className="error-msg">{error}</p>}
          <div className="modal-footer">
            <button type="button" className="btn-secondary" onClick={requestClose}>Cancel</button>
            <button type="submit" className="btn-primary" disabled={loading}>
              {loading ? 'Adding...' : 'Add Source'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
