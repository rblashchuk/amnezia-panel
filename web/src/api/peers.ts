import { api } from './client'
import type {
  DebugInfo,
  Peer,
  RenameClientRequest,
  RenameClientResponse,
  Source,
  TrafficRequest,
  TrafficResponse,
  UpdateCheckResponse,
} from './types'

export function getSources() {
  return api.get<Source[]>('/api/sources')
}

export function getPeers(sourceID: string) {
  const params = new URLSearchParams({ source_id: sourceID })
  return api.get<Peer[]>(`/api/peers?${params}`)
}

export function getTraffic(sourceID: string, publicKey: string, request: TrafficRequest) {
  const params = new URLSearchParams({
    source_id: sourceID,
  })
  if (publicKey) params.set('public_key', publicKey)
  if (request.range) params.set('range', request.range)
  if (request.from) params.set('from', request.from)
  if (request.to) params.set('to', request.to)

  return api.get<TrafficResponse>(`/api/traffic?${params}`)
}

export function getTrafficTotal(sourceID: string, request: TrafficRequest) {
  return getTraffic(sourceID, '', request)
}

export function getDebugInfo() {
  return api.get<DebugInfo>('/api/debug')
}

export function checkUpdates() {
  return api.post<UpdateCheckResponse>('/api/update/check')
}

export function renameClient(request: RenameClientRequest) {
  return api.post<RenameClientResponse>('/api/admin/clients/rename', request)
}
