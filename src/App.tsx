import { useEffect, useState } from 'react'
import AddSourceModal from './components/AddSourceModal'
import AddProjectModal from './components/AddProjectModal'
import ProjectList from './components/ProjectList'
import VariableEditor from './components/VariableEditor'
import LogsPage from './components/LogsPage'
import * as api from './lib/api'
import { subscribe } from './lib/logger'
import { assignIds, stripIds, normalizeForType, normalizedForCompare } from './lib/variables'
import type { Project, Source, Variable } from './types'

type View = 'sources' | 'logs'

function getErrorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error)
}

export default function App() {
  const [projects, setProjects] = useState<Project[]>([])
  const [selectedSource, setSelectedSource] = useState<Source | null>(null)
  const [variables, setVariables] = useState<Variable[]>([])
  const [originalVariables, setOriginalVariables] = useState<Variable[]>([])
  const [addSourceForProject, setAddSourceForProject] = useState<number | null>(null)
  const [showProjectModal, setShowProjectModal] = useState(false)
  const [loadingVars, setLoadingVars] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [saveSuccess, setSaveSuccess] = useState(false)
  const [view, setView] = useState<View>('sources')
  const [logErrorCount, setLogErrorCount] = useState(0)

  useEffect(() => {
    void fetchProjects()
  }, [])

  useEffect(() => subscribe(logs => setLogErrorCount(logs.filter(log => !log.ok).length)), [])

  useEffect(() => {
    if (selectedSource) {
      void fetchVariables(selectedSource.id)
    } else {
      setVariables([])
      setOriginalVariables([])
      setError(null)
    }
  }, [selectedSource?.id])

  async function fetchProjects() {
    const data = await api.listProjectsWithSources()
    setProjects(data)

    if (selectedSource && !data.some(project => project.sources.some(source => source.id === selectedSource.id))) {
      setSelectedSource(null)
    }
  }

  const allSources = projects.flatMap(project =>
    project.sources.map(source => ({ ...source, projectName: project.name }))
  )

  async function fetchVariables(sourceId: number) {
    setLoadingVars(true)
    setError(null)
    setSaveSuccess(false)

    try {
      const withIds = assignIds(await api.getVariables(sourceId))
      setVariables(withIds)
      setOriginalVariables(withIds)
    } catch (error) {
      setError(getErrorMessage(error))
      setVariables([])
      setOriginalVariables([])
    } finally {
      setLoadingVars(false)
    }
  }

  async function handleSave() {
    if (!selectedSource) return

    setSaving(true)
    setError(null)
    setSaveSuccess(false)

    try {
      await api.saveVariables(selectedSource.id, stripIds(variables))
      setOriginalVariables(variables)
      setSaveSuccess(true)
      window.setTimeout(() => setSaveSuccess(false), 3000)
    } catch (error) {
      setError(getErrorMessage(error))
    } finally {
      setSaving(false)
    }
  }

  async function handleAddProject(name: string) {
    await api.createProject(name)
    await fetchProjects()
  }

  async function handleRenameProject(id: number, name: string) {
    try {
      await api.renameProject(id, name)
      await fetchProjects()
    } catch {}
  }

  async function handleDeleteProject(id: number) {
    try {
      await api.deleteProject(id)
      await fetchProjects()
    } catch {}
  }

  async function handleReorderProjects(orderedIds: number[]) {
    const previousProjects = projects
    const reorderedProjects = orderedIds
      .map(id => previousProjects.find(project => project.id === id))
      .filter((project): project is Project => Boolean(project))

    if (reorderedProjects.length !== previousProjects.length) return

    setProjects(reorderedProjects)
    try {
      await api.reorderProjects(orderedIds)
    } catch {
      setProjects(previousProjects)
    }
  }

  async function handleAddSource(sourceData: { name: string, type: Source['type'], config: Record<string, string> }) {
    if (addSourceForProject === null) return
    await api.createSource({ projectId: addSourceForProject, ...sourceData })
    await fetchProjects()
  }

  async function handleRenameSource(sourceId: number, name: string) {
    try {
      const updated = await api.renameSource(sourceId, name)
      await fetchProjects()
      if (selectedSource?.id === sourceId) setSelectedSource(updated)
    } catch {}
  }

  async function handleDeleteSource(sourceId: number) {
    try {
      await api.deleteSource(sourceId)
      if (selectedSource?.id === sourceId) setSelectedSource(null)
      await fetchProjects()
    } catch {}
  }

  async function handleReorderSources(projectId: number, orderedIds: number[]) {
    const projectIndex = projects.findIndex(project => project.id === projectId)
    if (projectIndex === -1) return

    const previousProjects = projects
    const project = projects[projectIndex]
    const reorderedSources = orderedIds
      .map(id => project.sources.find(source => source.id === id))
      .filter((source): source is Source => Boolean(source))

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

  async function handleCopyFrom(fromSourceId: number) {
    if (!selectedSource) return

    try {
      const normalized = normalizeForType(await api.getVariables(fromSourceId), selectedSource.type)
      setVariables(normalized)
    } catch (error) {
      setError(getErrorMessage(error))
    }
  }

  const isDirty = normalizedForCompare(variables) !== normalizedForCompare(originalVariables)
  const addSourceProject = projects.find(project => project.id === addSourceForProject)

  return (
    <div className="app">
      <div className="sidebar">
        <div className="sidebar-header">
          <button
            className="btn-add"
            onClick={() => {
              setView('sources')
              setShowProjectModal(true)
            }}
          >
            + Add Project
          </button>
        </div>
        <ProjectList
          projects={projects}
          selectedSourceId={view === 'sources' ? selectedSource?.id ?? null : null}
          onSelectSource={source => {
            setView('sources')
            setSelectedSource(source)
          }}
          onRenameProject={handleRenameProject}
          onDeleteProject={handleDeleteProject}
          onReorderProjects={handleReorderProjects}
          onRenameSource={handleRenameSource}
          onDeleteSource={handleDeleteSource}
          onReorderSources={handleReorderSources}
          onAddSource={projectId => {
            setView('sources')
            setAddSourceForProject(projectId)
          }}
        />
        <div className="sidebar-footer">
          <button
            className={`btn-logs ${view === 'logs' ? 'active' : ''}`}
            onClick={() => setView(current => (current === 'logs' ? 'sources' : 'logs'))}
          >
            <span>Logs</span>
            {logErrorCount > 0 && <span className="log-error-badge">{logErrorCount}</span>}
          </button>
        </div>
      </div>

      <div className="main">
        <hr style={{ height: '1px', color: '#eee' }} />
        {view === 'logs' ? (
          <LogsPage />
        ) : selectedSource ? (
          <VariableEditor
            source={selectedSource}
            sources={allSources}
            variables={variables}
            onChange={setVariables}
            onSave={handleSave}
            onRefresh={() => void fetchVariables(selectedSource.id)}
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
