// Ensures every variable has a stable client-side id for React keys
// and strips it before sending to the backend.
export function assignIds(vars) {
  return vars.map(v => ({ ...v, _clientId: crypto.randomUUID() }))
}

export function stripIds(vars) {
  return vars.map(({ _clientId, ...rest }) => rest)
}

// Default values for a new GitLab variable
export function newGitlabVariable(overrides = {}) {
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

export function newLambdaVariable(overrides = {}) {
  return {
    _clientId: crypto.randomUUID(),
    key: '',
    value: '',
    ...overrides,
  }
}

// Normalize an array of variables to match the target source type.
// When copying from one source to another, the shape may differ.
export function normalizeForType(vars, targetType) {
  if (targetType === 'gitlab_cicd') {
    return vars.map(v => newGitlabVariable({
      key: v.key,
      value: v.value,
      variable_type: v.variable_type ?? 'env_var',
      environment_scope: v.environment_scope ?? '*',
      protected: v.protected ?? false,
      masked: v.masked ?? false,
      hidden: v.hidden ?? false,
      raw: v.raw ?? false,
      description: v.description ?? null,
    }))
  }
  if (targetType === 'lambda') {
    return vars.map(v => newLambdaVariable({ key: v.key, value: v.value }))
  }
  return assignIds(vars)
}

// Comparable representation for dirty-check (ignore _clientId, ignore order doesn't matter here since we preserve it)
export function normalizedForCompare(vars) {
  return JSON.stringify(stripIds(vars))
}
