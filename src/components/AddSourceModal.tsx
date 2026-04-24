import { useState } from 'react'
import { useModalClose } from '../lib/useModalClose'
import type { Source, SourceConfig, SourceType } from '../types'

const SOURCE_TYPES: Array<{ value: SourceType, label: string }> = [
  { value: 'lambda', label: 'AWS Lambda' },
  { value: 'gitlab_cicd', label: 'GitLab CI/CD' },
]

const FIELDS: Record<SourceType, Array<{ key: string, label: string, placeholder: string, type?: string }>> = {
  lambda: [
    { key: 'function_name', label: 'Function Name', placeholder: 'your-function-name' },
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

interface AddSourceModalProps {
  onClose: () => void
  onAdd: (source: { name: string, type: Source['type'], config: SourceConfig }) => Promise<void>
  projectName?: string
}

function getErrorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error)
}

export default function AddSourceModal({ onClose, onAdd, projectName }: AddSourceModalProps) {
  const [name, setName] = useState('')
  const [type, setType] = useState<SourceType>('lambda')
  const [config, setConfig] = useState<SourceConfig>({})
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const { closing, requestClose } = useModalClose(onClose)

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setError(null)
    setLoading(true)

    try {
      await onAdd({ name, type, config })
      requestClose()
    } catch (error) {
      setError(getErrorMessage(error))
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className={`modal-backdrop ${closing ? 'closing' : ''}`}>
      <div className="modal" onClick={event => event.stopPropagation()}>
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
              onChange={event => setName(event.target.value)}
              placeholder="My Lambda / My GitLab Project"
              required
            />
          </div>
          <div className="form-group">
            <label>Type</label>
            <select
              style={{ height: '32px' }}
              value={type}
              onChange={event => {
                setType(event.target.value as SourceType)
                setConfig({})
              }}
            >
              {SOURCE_TYPES.map(sourceType => (
                <option key={sourceType.value} value={sourceType.value}>{sourceType.label}</option>
              ))}
            </select>
          </div>
          {FIELDS[type].map(field => (
            <div className="form-group" key={field.key}>
              <label>{field.label}</label>
              <input
                type={field.type || 'text'}
                value={config[field.key] || ''}
                onChange={event => setConfig(previous => ({ ...previous, [field.key]: event.target.value }))}
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
