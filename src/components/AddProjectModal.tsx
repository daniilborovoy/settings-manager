import { useState } from 'react'
import { useModalClose } from '../lib/useModalClose'

interface AddProjectModalProps {
  onClose: () => void
  onAdd: (name: string) => Promise<void>
}

function getErrorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error)
}

export default function AddProjectModal({ onClose, onAdd }: AddProjectModalProps) {
  const [name, setName] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const { closing, requestClose } = useModalClose(onClose)

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!name.trim()) return

    setError(null)
    setLoading(true)

    try {
      await onAdd(name.trim())
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
          <h2>New Project</h2>
          <button className="btn-close" onClick={requestClose}>×</button>
        </div>
        <form onSubmit={handleSubmit}>
          <div className="form-group">
            <label>Name</label>
            <input
              type="text"
              autoFocus
              value={name}
              onChange={event => setName(event.target.value)}
              placeholder="Backend, Mobile, ..."
              required
            />
          </div>
          {error && <p className="error-msg">{error}</p>}
          <div className="modal-footer">
            <button type="button" className="btn-secondary" onClick={requestClose}>Cancel</button>
            <button type="submit" className="btn-primary" disabled={loading || !name.trim()}>
              {loading ? 'Creating...' : 'Create Project'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
