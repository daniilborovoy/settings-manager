import { useState } from 'react'
import { useModalClose } from '../lib/useModalClose'

interface UpdateTokenModalProps {
  sourceName: string
  onUpdate: (token: string) => Promise<void>
  onClose: () => void
}

function getErrorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error)
}

export default function UpdateTokenModal({ sourceName, onUpdate, onClose }: UpdateTokenModalProps) {
  const [token, setToken] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const { closing, requestClose } = useModalClose(onClose)

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const trimmed = token.trim()
    if (!trimmed) return
    setError(null)
    setLoading(true)

    try {
      await onUpdate(trimmed)
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
          <h2>GitLab token expired</h2>
          <button className="btn-close" onClick={requestClose}>×</button>
        </div>
        <form onSubmit={handleSubmit}>
          <p style={{ color: '#6c6f85', fontSize: 13, marginTop: 0 }}>
            GitLab rejected the token for "{sourceName}" (401 Unauthorized). Enter a new private token to continue.
          </p>
          <div className="form-group">
            <label>New Private Token</label>
            <input
              type="password"
              value={token}
              onChange={event => setToken(event.target.value)}
              placeholder="glpat-••••••••"
              autoFocus
              required
            />
          </div>
          {error && <p className="error-msg">{error}</p>}
          <div className="modal-footer">
            <button type="button" className="btn-secondary" onClick={requestClose}>Cancel</button>
            <button type="submit" className="btn-primary" disabled={loading || !token.trim()}>
              {loading ? 'Updating...' : 'Update Token'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
