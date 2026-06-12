export type Peer = {
  public_key: string
  rx_bytes: number
  tx_bytes: number
  last_handshake: string
}

export type TrafficPoint = {
  collected_at: string
  rx_bytes: number
  tx_bytes: number
}

export type TrafficResponse = {
  public_key: string
  range_seconds: number
  bucket_seconds: number
  rx_bytes: number
  tx_bytes: number
  points: TrafficPoint[]
}

export type TrafficRange = '6h' | '24h' | '168h' | '720h'
