import { useEffect, useState } from 'react'
import { subscribe, clearLogs } from '../lib/logger'

function statusClass(log) {
  return log.ok ? 'log-ok' : 'log-err'
}

function formatTime(ts) {
  return new Date(ts).toLocaleTimeString('en-GB', { hour12: false })
}

export default function LogsPage() {
  const [logs, setLogs] = useState([])
  const [expandedId, setExpandedId] = useState(null)

  useEffect(() => subscribe(setLogs), [])

  function toggle(id) {
    setExpandedId(prev => (prev === id ? null : id))
  }

  return (
    <div className="logs-page">
      <div className="logs-header">
        <h2>Logs</h2>
        <div className="logs-header-right">
          <span className="logs-count">{logs.length} call{logs.length !== 1 ? 's' : ''}</span>
          <button className="btn-secondary" onClick={() => { clearLogs(); setExpandedId(null) }}>
            Clear
          </button>
        </div>
      </div>

      {logs.length === 0 ? (
        <div className="logs-empty">No calls yet — interact with the app to see logs here.</div>
      ) : (
        <div className="logs-list">
          {logs.map(log => (
            <div key={log.id} className={`log-entry ${statusClass(log)} ${expandedId === log.id ? 'expanded' : ''}`}>
              <div className="log-summary" onClick={() => toggle(log.id)}>
                <span className="log-method" style={{ color: '#8b5cf6' }}>INVOKE</span>
                <span className={`log-status-badge ${statusClass(log)}`}>
                  {log.ok ? 'OK' : 'ERR'}
                </span>
                <span className="log-url">{log.command}</span>
                <span className="log-meta">
                  <span className="log-duration">{log.duration}ms</span>
                  <span className="log-time">{formatTime(log.time)}</span>
                  <span className="log-chevron">{expandedId === log.id ? '▲' : '▼'}</span>
                </span>
              </div>

              {expandedId === log.id && (
                <div className="log-detail">
                  {log.args && Object.keys(log.args).length > 0 && (
                    <>
                      <div className="log-detail-label">Arguments</div>
                      <pre className="log-pre">{JSON.stringify(log.args, null, 2)}</pre>
                    </>
                  )}
                  {log.error ? (
                    <>
                      <div className="log-detail-label">Error</div>
                      <pre className="log-pre log-pre-error">{log.error}</pre>
                    </>
                  ) : log.result !== undefined ? (
                    <>
                      <div className="log-detail-label">Result</div>
                      <pre className="log-pre">{JSON.stringify(log.result, null, 2)}</pre>
                    </>
                  ) : (
                    <div className="log-detail-empty">No result</div>
                  )}
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
