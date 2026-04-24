export type SourceType = 'lambda' | 'gitlab_cicd'

export type SourceConfig = Record<string, string>

export interface Source {
  id: number
  project_id?: number
  name: string
  type: SourceType
  config?: SourceConfig
  projectName?: string
}

export interface Project {
  id: number
  name: string
  sources: Source[]
}

export interface BaseVariable {
  _clientId?: string
  key: string
  value: string
}

export interface GitlabVariable extends BaseVariable {
  variable_type?: 'env_var' | 'file'
  environment_scope?: string
  protected?: boolean
  masked?: boolean
  hidden?: boolean
  raw?: boolean
  description?: string | null
}

export interface LambdaVariable extends BaseVariable {}

export type Variable = GitlabVariable | LambdaVariable

export interface LogEntry {
  id: string
  time: number
  command: string
  args?: Record<string, unknown>
  ok: boolean
  duration: number
  result?: unknown
  error?: string
}

export interface EditingState {
  kind: 'project' | 'source'
  id: number
  value: string
}
