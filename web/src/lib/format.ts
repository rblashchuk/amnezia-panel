export function formatBytes(bytes: number | undefined) {
  if (!bytes) return '0 B'

  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  let value = bytes
  let unit = 0

  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024
    unit += 1
  }

  return `${value.toFixed(1)} ${units[unit]}`
}

export function shortKey(key: string, length = 28) {
  if (key.length <= length) return key
  return `${key.slice(0, length)}...`
}

export function getPeerStatus(lastHandshake: string) {
  if (!lastHandshake) return 'offline'

  const timestamp = new Date(lastHandshake).getTime()
  if (Number.isNaN(timestamp)) return 'offline'

  return Date.now() - timestamp < 60_000 ? 'online' : 'offline'
}

export function formatRelativeHandshake(lastHandshake: string) {
  const timestamp = new Date(lastHandshake).getTime()
  if (!lastHandshake || Number.isNaN(timestamp) || timestamp <= 0) {
    return 'Never'
  }

  const seconds = Math.max(0, Math.round((Date.now() - timestamp) / 1000))
  if (seconds < 60) return `${seconds}s ago`

  const minutes = Math.round(seconds / 60)
  if (minutes < 60) return `${minutes}m ago`

  const hours = Math.round(minutes / 60)
  if (hours < 48) return `${hours}h ago`

  const days = Math.round(hours / 24)
  return `${days}d ago`
}
