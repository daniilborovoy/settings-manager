const entries = []
const listeners = new Set()

export function addLog(entry) {
  entries.unshift({ id: crypto.randomUUID(), time: Date.now(), ...entry })
  if (entries.length > 300) entries.pop()
  listeners.forEach(fn => fn([...entries]))
}

export function clearLogs() {
  entries.length = 0
  listeners.forEach(fn => fn([]))
}

export function subscribe(fn) {
  listeners.add(fn)
  fn([...entries])
  return () => listeners.delete(fn)
}
