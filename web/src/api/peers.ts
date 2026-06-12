import { api } from './client'
import type { Peer, TrafficRange, TrafficResponse } from './types'

export function getPeers() {
  return api.get<Peer[]>('/api/peers')
}

export function getTraffic(publicKey: string, range: TrafficRange) {
  const params = new URLSearchParams({
    public_key: publicKey,
    range,
  })

  return api.get<TrafficResponse>(`/api/traffic?${params}`)
}
