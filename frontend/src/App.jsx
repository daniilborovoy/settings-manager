import { useEffect, useState } from 'react'
import AddSourceModal from './components/AddSourceModal'
import AddProjectModal from './components/AddProjectModal'
import ProjectList from './components/ProjectList'
import VariableEditor from './components/VariableEditor'
import LogsPage from './components/LogsPage'
import * as api from './lib/api'
import { subscribe } from './lib/logger'
import { assignIds, stripIds, normalizeForType, normalizedForCompare } from './lib/variables'

export default function App() {
  const [projects, setProjects] = useState([])
  const [selectedSource, setSelectedSource] = useState(null)
  const [variables, setVariables] = useState([])
  const [originalVariables, setOriginalVariables] = useState([])
  const [addSourceForProject, setAddSourceForProject] = useState(null)
  const [showProjectModal, setShowProjectModal] = useState(false)
  const [loadingVars, setLoadingVars] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)
  const [saveSuccess, setSaveSuccess] = useState(false)
  const [view, setView] = useState('sources')
  const [logErrorCount, setLogErrorCount] = useState(0)

  useEffect(() => {
    fetchProjects()
  }, [])

  useEffect(() => {
    return subscribe(logs => setLogErrorCount(logs.filter(l => !l.ok).length))
  }, [])

  useEffect(() => {
    if (selectedSource) {
      fetchVariables(selectedSource.id)
    } else {
      setVariables([])
      setOriginalVariables([])
      setError(null)
    }
  }, [selectedSource?.id])

  async function fetchProjects() {
    const data = await api.listProjectsWithSources()
    setProjects(data)
    if (selectedSource && !data.some(p => p.sources.some(s => s.id === selectedSource.id))) {
      setSelectedSource(null)
    }
  }

  const allSources = projects.flatMap(p =>
    p.sources.map(s => ({ ...s, projectName: p.name }))
  )

  async function fetchVariables(sourceId) {
    setLoadingVars(true)
    setError(null)
    setSaveSuccess(false)
    try {
      const vars = await api.getVariables(sourceId)
      const withIds = assignIds(vars)
      setVariables(withIds)
      setOriginalVariables(withIds)
    } catch (e) {
      setError(e.message)
      setVariables([])
      setOriginalVariables([])
    } finally {
      setLoadingVars(false)
    }
  }

  async function handleSave() {
    setSaving(true)
    setError(null)
    setSaveSuccess(false)
    try {
      const payload = stripIds(variables)
      await api.saveVariables(selectedSource.id, payload)
      setOriginalVariables(variables)
      setSaveSuccess(true)
      setTimeout(() => setSaveSuccess(false), 3000)
    } catch (e) {
      setError(e.message)
    } finally {
      setSaving(false)
    }
  }

  async function handleAddProject(name) {
    await api.createProject(name)
    await fetchProjects()
  }

  async function handleRenameProject(id, name) {
    try {
      await api.renameProject(id, name)
      await fetchProjects()
    } catch { /* already logged */ }
  }

  async function handleDeleteProject(id) {
    try {
      await api.deleteProject(id)
      await fetchProjects()
    } catch { /* already logged */ }
  }

  async function handleReorderProjects(orderedIds) {
    const previousProjects = projects
    const reorderedProjects = orderedIds
      .map(id => previousProjects.find(project => project.id === id))
      .filter(Boolean)

    if (reorderedProjects.length !== previousProjects.length) return

    setProjects(reorderedProjects)
    try {
      await api.reorderProjects(orderedIds)
    } catch {
      setProjects(previousProjects)
    }
  }

  async function handleAddSource(sourceData) {
    await api.createSource({ projectId: addSourceForProject, ...sourceData })
    await fetchProjects()
  }

  async function handleRenameSource(sourceId, name) {
    try {
      const updated = await api.renameSource(sourceId, name)
      await fetchProjects()
      if (selectedSource?.id === sourceId) setSelectedSource(updated)
    } catch { /* already logged */ }
  }

  async function handleDeleteSource(sourceId) {
    try {
      await api.deleteSource(sourceId)
      if (selectedSource?.id === sourceId) setSelectedSource(null)
      await fetchProjects()
    } catch { /* already logged */ }
  }

  async function handleReorderSources(projectId, orderedIds) {
    const projectIndex = projects.findIndex(project => project.id === projectId)
    if (projectIndex === -1) return

    const previousProjects = projects
    const project = projects[projectIndex]
    const reorderedSources = orderedIds
      .map(id => project.sources.find(source => source.id === id))
      .filter(Boolean)

    if (reorderedSources.length !== project.sources.length) return

    const nextProjects = [...projects]
    nextProjects[projectIndex] = { ...project, sources: reorderedSources }
    setProjects(nextProjects)

    try {
      await api.reorderSources(projectId, orderedIds)
    } catch {
      setProjects(previousProjects)
    }
  }

  async function handleCopyFrom(fromSourceId) {
    try {
      const vars = await api.getVariables(fromSourceId)
      const normalized = normalizeForType(vars, selectedSource.type)
      setVariables(normalized)
    } catch (e) {
      setError(e.message)
    }
  }

  const isDirty = normalizedForCompare(variables) !== normalizedForCompare(originalVariables)
  const addSourceProject = projects.find(p => p.id === addSourceForProject)

  return (
    <div className="app">
      <div className="sidebar">
        <div className="sidebar-header">
          <button
            className="btn-add"
            onClick={() => { setView('sources'); setShowProjectModal(true) }}
          >
            + Add Project
          </button>
        </div>
        <ProjectList
          projects={projects}
          selectedSourceId={view === 'sources' ? selectedSource?.id : null}
          onSelectSource={s => { setView('sources'); setSelectedSource(s) }}
          onRenameProject={handleRenameProject}
          onDeleteProject={handleDeleteProject}
          onReorderProjects={handleReorderProjects}
          onRenameSource={handleRenameSource}
          onDeleteSource={handleDeleteSource}
          onReorderSources={handleReorderSources}
          onAddSource={projectId => { setView('sources'); setAddSourceForProject(projectId) }}
        />
        <div className="sidebar-footer">
          <button
            className={`btn-logs ${view === 'logs' ? 'active' : ''}`}
            onClick={() => setView(v => v === 'logs' ? 'sources' : 'logs')}
          >
            <span>Logs</span>
            {logErrorCount > 0 && (
              <span className="log-error-badge">{logErrorCount}</span>
            )}
          </button>
        </div>
      </div>

      <div className="main">
        <hr style={{
          height: "1px",
          color: '#eee'
        }}/>
        {view === 'logs' ? (
          <LogsPage />
        ) : selectedSource ? (
          <VariableEditor
            source={selectedSource}
            sources={allSources}
            variables={variables}
            onChange={setVariables}
            onSave={handleSave}
            onRefresh={() => fetchVariables(selectedSource.id)}
            onCopyFrom={handleCopyFrom}
            loading={loadingVars}
            saving={saving}
            isDirty={isDirty}
            error={error}
            saveSuccess={saveSuccess}
          />
        ) : (
          <div className="empty-state">
            <p>Select a source to view and edit its variables</p>
          </div>
        )}
      </div>

      {showProjectModal && (
        <AddProjectModal
          onClose={() => setShowProjectModal(false)}
          onAdd={handleAddProject}
        />
      )}

      {addSourceForProject !== null && (
        <AddSourceModal
          projectName={addSourceProject?.name}
          onClose={() => setAddSourceForProject(null)}
          onAdd={handleAddSource}
        />
      )}
    </div>
  )
}
