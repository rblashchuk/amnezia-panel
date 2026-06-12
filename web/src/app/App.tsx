import { useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Activity, Clock3, Download, RefreshCcw, Server, Upload } from 'lucide-react'
import { getPeers, getTraffic } from '../api/peers'
import type { Peer, TrafficRange } from '../api/types'
import { formatBytes, formatRelativeHandshake, getPeerStatus, shortKey } from '../lib/format'
import { TrafficChart } from '../features/traffic/TrafficChart'

const ranges: Array<{ value: TrafficRange; label: string }> = [
  { value: '6h', label: '6H' },
  { value: '24h', label: '24H' },
  { value: '168h', label: '7D' },
  { value: '720h', label: '30D' },
]

const emptyPeers: Peer[] = []

export function App() {
  const [selectedKey, setSelectedKey] = useState('')
  const [range, setRange] = useState<TrafficRange>('6h')

  const peersQuery = useQuery({
    queryKey: ['peers'],
    queryFn: getPeers,
    refetchInterval: 3_000,
  })

  const peers = peersQuery.data ?? emptyPeers
  const effectiveSelectedKey = selectedKey || peers[0]?.public_key || ''

  const selectedPeer = useMemo(
    () => peers.find((peer) => peer.public_key === effectiveSelectedKey),
    [peers, effectiveSelectedKey],
  )

  const trafficQuery = useQuery({
    queryKey: ['traffic', effectiveSelectedKey, range],
    queryFn: () => getTraffic(effectiveSelectedKey, range),
    enabled: Boolean(effectiveSelectedKey),
    refetchInterval: 30_000,
  })

  const onlineCount = peers.filter((peer) => getPeerStatus(peer.last_handshake) === 'online').length
  const totalRx = peers.reduce((sum, peer) => sum + peer.rx_bytes, 0)
  const totalTx = peers.reduce((sum, peer) => sum + peer.tx_bytes, 0)

  return (
    <div className="shell">
      <header className="topbar">
        <div>
          <div className="eyebrow">Self-hosted AmneziaVPN</div>
          <h1>VPN Panel</h1>
        </div>
        <button className="icon-button" type="button" onClick={() => peersQuery.refetch()} title="Refresh peers">
          <RefreshCcw size={18} />
        </button>
      </header>

      <main className="dashboard">
        <section className="summary-grid" aria-label="Overview">
          <SummaryCard icon={<Server size={18} />} label="Peers" value={String(peers.length)} meta={`${onlineCount} online`} />
          <SummaryCard icon={<Download size={18} />} label="Total RX" value={formatBytes(totalRx)} meta="live counters" />
          <SummaryCard icon={<Upload size={18} />} label="Total TX" value={formatBytes(totalTx)} meta="live counters" />
          <SummaryCard icon={<Activity size={18} />} label="Collector" value={peersQuery.isError ? 'Error' : 'Active'} meta="3s refresh" />
        </section>

        <section className="workspace">
          <PeerList
            peers={peers}
            selectedKey={effectiveSelectedKey}
            isLoading={peersQuery.isLoading}
            error={peersQuery.error}
            onSelect={setSelectedKey}
          />

          <section className="traffic-panel">
            <div className="panel-header">
              <div>
                <div className="panel-title">Traffic history</div>
                <div className="panel-subtitle">{selectedPeer ? shortKey(selectedPeer.public_key, 44) : 'Select a peer'}</div>
              </div>
              <div className="segmented" role="group" aria-label="Traffic range">
                {ranges.map((item) => (
                  <button
                    key={item.value}
                    type="button"
                    className={item.value === range ? 'active' : ''}
                    onClick={() => setRange(item.value)}
                  >
                    {item.label}
                  </button>
                ))}
              </div>
            </div>

            <div className="metric-row">
              <Metric label="RX in range" value={formatBytes(trafficQuery.data?.rx_bytes)} icon={<Download size={16} />} />
              <Metric label="TX in range" value={formatBytes(trafficQuery.data?.tx_bytes)} icon={<Upload size={16} />} />
              <Metric
                label="Last handshake"
                value={selectedPeer ? formatRelativeHandshake(selectedPeer.last_handshake) : 'None'}
                icon={<Clock3 size={16} />}
              />
            </div>

            <TrafficChart
              data={trafficQuery.data}
              isLoading={trafficQuery.isLoading}
              error={trafficQuery.error}
            />
          </section>
        </section>
      </main>
    </div>
  )
}

function SummaryCard({ icon, label, value, meta }: { icon: ReactNode; label: string; value: string; meta: string }) {
  return (
    <div className="summary-card">
      <div className="summary-icon">{icon}</div>
      <div>
        <div className="summary-label">{label}</div>
        <div className="summary-value">{value}</div>
        <div className="summary-meta">{meta}</div>
      </div>
    </div>
  )
}

function PeerList({
  peers,
  selectedKey,
  isLoading,
  error,
  onSelect,
}: {
  peers: Peer[]
  selectedKey: string
  isLoading: boolean
  error: Error | null
  onSelect: (key: string) => void
}) {
  return (
    <section className="peer-panel">
      <div className="panel-header">
        <div>
          <div className="panel-title">Peers</div>
          <div className="panel-subtitle">{peers.length} configured clients</div>
        </div>
      </div>

      <div className="peer-list">
        {isLoading && <StateMessage title="Loading peers" detail="Waiting for WireGuard dump" />}
        {error && <StateMessage title="Could not load peers" detail={error.message} />}
        {!isLoading && !error && peers.length === 0 && <StateMessage title="No peers" detail="No clients returned by wg dump" />}

        {peers.map((peer) => {
          const status = getPeerStatus(peer.last_handshake)
          return (
            <button
              key={peer.public_key}
              type="button"
              className={`peer-row ${status} ${peer.public_key === selectedKey ? 'selected' : ''}`}
              onClick={() => onSelect(peer.public_key)}
            >
              <span className="status-dot" />
              <span className="peer-main">
                <span className="peer-key">{shortKey(peer.public_key)}</span>
                <span className="peer-meta">{formatRelativeHandshake(peer.last_handshake)}</span>
              </span>
              <span className="peer-traffic">
                <span>{formatBytes(peer.rx_bytes)}</span>
                <span>{formatBytes(peer.tx_bytes)}</span>
              </span>
            </button>
          )
        })}
      </div>
    </section>
  )
}

function Metric({ icon, label, value }: { icon: ReactNode; label: string; value: string }) {
  return (
    <div className="metric-card">
      <div className="metric-icon">{icon}</div>
      <div>
        <div className="metric-label">{label}</div>
        <div className="metric-value">{value}</div>
      </div>
    </div>
  )
}

function StateMessage({ title, detail }: { title: string; detail: string }) {
  return (
    <div className="state-message">
      <strong>{title}</strong>
      <span>{detail}</span>
    </div>
  )
}
