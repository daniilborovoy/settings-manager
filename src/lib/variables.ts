import type { GitlabVariable, SourceType, Variable } from '../types'

export function assignIds(vars: Variable[]) {
  return vars.map(variable => ({ ...variable, _clientId: crypto.randomUUID() }))
}

export function stripIds(vars: Variable[]): Variable[] {
  return vars.map(({ _clientId, ...rest }) => rest)
}

export function newGitlabVariable(overrides: Partial<GitlabVariable> = {}): GitlabVariable {
  return {
    _clientId: crypto.randomUUID(),
    key: '',
    value: '',
    variable_type: 'env_var',
    environment_scope: '*',
    protected: false,
    masked: false,
    hidden: false,
    raw: false,
    description: null,
    ...overrides,
  }
}

export function newLambdaVariable(overrides: Partial<Variable> = {}): Variable {
  return {
    _clientId: crypto.randomUUID(),
    key: '',
    value: '',
    ...overrides,
  }
}

export function normalizeForType(vars: Variable[], targetType: SourceType) {
  if (targetType === 'gitlab_cicd') {
    return vars.map(variable => newGitlabVariable({
      key: variable.key,
      value: variable.value,
      variable_type: 'variable_type' in variable ? variable.variable_type ?? 'env_var' : 'env_var',
      environment_scope: 'environment_scope' in variable ? variable.environment_scope ?? '*' : '*',
      protected: 'protected' in variable ? variable.protected ?? false : false,
      masked: 'masked' in variable ? variable.masked ?? false : false,
      hidden: 'hidden' in variable ? variable.hidden ?? false : false,
      raw: 'raw' in variable ? variable.raw ?? false : false,
      description: 'description' in variable ? variable.description ?? null : null,
    }))
  }

  if (targetType === 'lambda') {
    return vars.map(variable => newLambdaVariable({ key: variable.key, value: variable.value }))
  }

  return assignIds(vars)
}

export function normalizedForCompare(vars: Variable[]) {
  return JSON.stringify(stripIds(vars))
}
