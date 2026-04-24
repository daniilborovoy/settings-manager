import { invoke } from '@tauri-apps/api/core'
import { addLog } from './logger'

async function call(command, args = {}) {
  const start = Date.now()
  try {
    const result = await invoke(command, args)
    addLog({ command, args, ok: true, duration: Date.now() - start, result })
    return result
  } catch (err) {
    const message = typeof err === 'string' ? err : err?.message || String(err)
    addLog({ command, args, ok: false, duration: Date.now() - start, error: message })
    throw new Error(message)
  }
}

// Projects
export const listProjectsWithSources = () => call('list_projects_with_sources')
export const createProject = (name) => call('create_project', { name })
export const renameProject = (id, name) => call('rename_project', { id, name })
export const deleteProject = (id) => call('delete_project', { id })
export const reorderProjects = (orderedIds) => call('reorder_projects', { orderedIds })

// Sources
export const createSource = ({ projectId, name, type, config }) =>
  call('create_source', { projectId, name, type, config })
export const renameSource = (id, name) => call('rename_source', { id, name })
export const deleteSource = (id) => call('delete_source', { id })
export const reorderSources = (projectId, orderedIds) =>
  call('reorder_sources', { projectId, orderedIds })
export const getVariables = (id) => call('get_variables', { id })
export const saveVariables = (id, variables) => call('save_variables', { id, variables })
