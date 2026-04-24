import type { LogEntry } from '../types'

type LogListener = (entries: LogEntry[]) => void
type LogInput = Omit<LogEntry, 'id' | 'time'>

const entries: LogEntry[] = []
const listeners = new Set<LogListener>()

export function addLog(entry: LogInput) {
  entries.unshift({ id: crypto.randomUUID(), time: Date.now(), ...entry })
  if (entries.length > 300) entries.pop()
  listeners.forEach(listener => listener([...entries]))
}

export function clearLogs() {
  entries.length = 0
  listeners.forEach(listener => listener([]))
}

export function subscribe(listener: LogListener) {
  listeners.add(listener)
  listener([...entries])
  return () => {
    listeners.delete(listener)
  }
}
