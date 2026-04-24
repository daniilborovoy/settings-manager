import { invoke } from '@tauri-apps/api/core'
import { addLog } from './logger'
import type { Project, Source, SourceConfig, Variable } from '../types'

type InvokeArgs = Record<string, unknown>

interface CreateSourceInput {
  projectId: number
  name: string
  type: Source['type']
  config: SourceConfig
}

function getErrorMessage(error: unknown) {
  return typeof error === 'string' ? error : error instanceof Error ? error.message : String(error)
}

async function call<T>(command: string, args: InvokeArgs = {}): Promise<T> {
  const start = Date.now()

  try {
    const result = await invoke<T>(command, args)
    addLog({ command, args, ok: true, duration: Date.now() - start, result })
    return result
  } catch (error) {
    const message = getErrorMessage(error)
    addLog({ command, args, ok: false, duration: Date.now() - start, error: message })
    throw new Error(message)
  }
}

export const listProjectsWithSources = () => call<Project[]>('list_projects_with_sources')
export const createProject = (name: string) => call<number>('create_project', { name })
export const renameProject = (id: number, name: string) => call<void>('rename_project', { id, name })
export const deleteProject = (id: number) => call<void>('delete_project', { id })
export const reorderProjects = (orderedIds: number[]) => call<void>('reorder_projects', { orderedIds })

export const createSource = ({ projectId, name, type, config }: CreateSourceInput) =>
  call<number>('create_source', { projectId, name, type, config })
export const renameSource = (id: number, name: string) => call<Source>('rename_source', { id, name })
export const deleteSource = (id: number) => call<void>('delete_source', { id })
export const reorderSources = (projectId: number, orderedIds: number[]) =>
  call<void>('reorder_sources', { projectId, orderedIds })
export const getVariables = (id: number) => call<Variable[]>('get_variables', { id })
export const saveVariables = (id: number, variables: Variable[]) => call<void>('save_variables', { id, variables })
