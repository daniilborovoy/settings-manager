import { useEffect, useRef, useState } from 'react'

const TYPE_LABELS = {
  lambda: 'λ Lambda',
  gitlab_cicd: '⎇ GitLab CI/CD',
}

const TYPE_COLORS = {
  lambda: '#ff9900',
  gitlab_cicd: '#fc6d26',
}

export default function ProjectList({
  projects,
  selectedSourceId,
  onSelectSource,
  onRenameProject,
  onDeleteProject,
  onRenameSource,
  onDeleteSource,
  onAddSource,
}) {
  const [expanded, setExpanded] = useState(() => new Set(projects.map(p => p.id)))
  const [editing, setEditing] = useState(null) // { kind: 'project'|'source', id, value }
  const inputRef = useRef(null)

  useEffect(() => {
    if (editing) inputRef.current?.select()
  }, [editing])

  // Auto-expand newly added projects
  useEffect(() => {
    setExpanded(prev => {
      const next = new Set(prev)
      projects.forEach(p => next.add(p.id))
      return next
    })
  }, [projects.length])

  function toggle(id) {
    setExpanded(prev => {
      const next = new Set(prev)
      next.has(id) ? next.delete(id) : next.add(id)
      return next
    })
  }

  function startEdit(kind, id, value) {
    setEditing({ kind, id, value })
  }

  function commitEdit() {
    if (!editing) return
    const trimmed = editing.value.trim()
    if (trimmed) {
      if (editing.kind === 'project') onRenameProject(editing.id, trimmed)
      else onRenameSource(editing.id, trimmed)
    }
    setEditing(null)
  }

  if (projects.length === 0) {
    return (
      <div className="project-list">
        <p className="source-empty">
          No projects yet.<br />
          Click "+ Add Project" to get started.
        </p>
      </div>
    )
  }

  return (
    <div className="project-list">
      {projects.map(project => {
        const isOpen = expanded.has(project.id)
        const isEditingProject = editing?.kind === 'project' && editing.id === project.id
        return (
          <div key={project.id} className="project-group">
            <div
              className={`project-header ${isOpen ? 'open' : ''}`}
              onClick={() => !isEditingProject && toggle(project.id)}
            >
              <span className={`project-chevron ${isOpen ? 'open' : ''}`}>▸</span>
              {isEditingProject ? (
                <input
                  ref={inputRef}
                  className="source-name-input"
                  value={editing.value}
                  onChange={e => setEditing({ ...editing, value: e.target.value })}
                  onBlur={commitEdit}
                  onKeyDown={e => {
                    if (e.key === 'Enter') commitEdit()
                    if (e.key === 'Escape') setEditing(null)
                  }}
                  onClick={e => e.stopPropagation()}
                />
              ) : (
                <span
                  className="project-name"
                  onDoubleClick={e => {
                    e.stopPropagation()
                    startEdit('project', project.id, project.name)
                  }}
                  title="Double-click to rename"
                >
                  {project.name}
                </span>
              )}
              <span className="project-count">{project.sources.length}</span>
              <button
                className="btn-delete-source btn-delete-project"
                onClick={e => {
                  e.stopPropagation()
                  if (confirm(`Delete project "${project.name}" and all its sources?`)) {
                    onDeleteProject(project.id)
                  }
                }}
                title="Delete project"
              >
                ×
              </button>
            </div>

            {isOpen && (
              <div className="project-body">
                {project.sources.map(source => {
                  const isEditingSource = editing?.kind === 'source' && editing.id === source.id
                  return (
                    <div
                      key={source.id}
                      className={`source-item ${selectedSourceId === source.id ? 'active' : ''}`}
                      onClick={() => !isEditingSource && onSelectSource(source)}
                    >
                      <div className="source-info">
                        <span className="source-badge" style={{ color: TYPE_COLORS[source.type] }}>
                          {TYPE_LABELS[source.type] || source.type}
                        </span>
                        {isEditingSource ? (
                          <input
                            ref={inputRef}
                            className="source-name-input"
                            value={editing.value}
                            onChange={e => setEditing({ ...editing, value: e.target.value })}
                            onBlur={commitEdit}
                            onKeyDown={e => {
                              if (e.key === 'Enter') commitEdit()
                              if (e.key === 'Escape') setEditing(null)
                            }}
                            onClick={e => e.stopPropagation()}
                          />
                        ) : (
                          <span
                            className="source-name"
                            onDoubleClick={e => {
                              e.stopPropagation()
                              startEdit('source', source.id, source.name)
                            }}
                            title="Double-click to rename"
                          >
                            {source.name}
                          </span>
                        )}
                      </div>
                      <button
                        className="btn-delete-source"
                        onClick={e => {
                          e.stopPropagation()
                          if (confirm(`Delete source "${source.name}"?`)) onDeleteSource(source.id)
                        }}
                        title="Delete source"
                      >
                        ×
                      </button>
                    </div>
                  )
                })}
                <button
                  className="btn-add-source-inline"
                  onClick={() => onAddSource(project.id)}
                >
                  + Add Source
                </button>
              </div>
            )}
          </div>
        )
      })}
    </div>
  )
}
