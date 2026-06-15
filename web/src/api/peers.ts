import { api } from './client'
import type { DebugInfo, Peer, Source, TrafficRange, TrafficResponse } from './types'

export function getSources() {
  return api.get<Source[]>('/api/sources')
}

export function getPeers(sourceID: string) {
  const params = new URLSearchParams({ source_id: sourceID })
  return api.get<Peer[]>(`/api/peers?${params}`)
}

export function getTraffic(sourceID: string, publicKey: string, range: TrafficRange) {
  const params = new URLSearchParams({
    source_id: sourceID,
    public_key: publicKey,
    range,
  })

  return api.get<TrafficResponse>(`/api/traffic?${params}`)
}

export function getDebugInfo() {
  return api.get<DebugInfo>('/api/debug')
}
