export type Peer = {
  public_key: string
  name?: string
  creation_date?: string
  allowed_ips?: string
  rx_bytes: number
  tx_bytes: number
  last_handshake: string
}

export type Source = {
  id: string
  protocol: string
  label: string
  container?: string
  command: string
  mode: string
}

export type TrafficPoint = {
  collected_at: string
  rx_bytes: number
  tx_bytes: number
}

export type TrafficResponse = {
  source_id: string
  public_key: string
  range_seconds: number
  bucket_seconds: number
  rx_bytes: number
  tx_bytes: number
  points: TrafficPoint[]
}

export type TrafficRange = string

export type TrafficRequest = {
  range?: TrafficRange
  from?: string
  to?: string
}

export type DebugInfo = {
  generated_at: string
  runtime: {
    go_version: string
    goos: string
    goarch: string
    num_cpu: number
    goroutines: number
  }
  system: {
    hostname: string
    kernel: string
    load_avg: string
    uptime: string
  }
  memory_kb: Record<string, number>
  disk: {
    path: string
    total: number
    free: number
    available: number
    used_pct: number
  }
  network: Array<{
    interface: string
    rx_bytes: number
    tx_bytes: number
  }>
  containers: Array<{
    name: string
    status: string
    image: string
  }>
}

export type UpdateImageState = {
  container: string
  image: string
  current_id: string
  latest_id: string
  available: boolean
  error?: string
}

export type UpdateCheckResponse = {
  checked_at: string
  available: boolean
  can_check: boolean
  message: string
  command: string
  local_panel: UpdateImageState
  collector: UpdateImageState
  requires_command: boolean
}
