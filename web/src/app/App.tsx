import { useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  Activity,
  Boxes,
  Clock3,
  Cpu,
  Database,
  Download,
  HardDrive,
  MemoryStick,
  Network,
  RefreshCcw,
  Server,
  TerminalSquare,
  Upload,
} from 'lucide-react'
import { getDebugInfo, getPeers, getSources, getTraffic } from '../api/peers'
import type { DebugInfo, Peer, Source, TrafficRange } from '../api/types'
import { formatBytes, formatRelativeHandshake, getPeerStatus, shortKey } from '../lib/format'
import { TrafficChart } from '../features/traffic/TrafficChart'

const ranges: Array<{ value: TrafficRange; label: string }> = [
  { value: '6h', label: '6H' },
  { value: '24h', label: '24H' },
  { value: '168h', label: '7D' },
  { value: '720h', label: '30D' },
]

const emptyPeers: Peer[] = []
const emptySources: Source[] = []

type Tab = 'traffic' | 'debug'

export function App() {
  const [tab, setTab] = useState<Tab>('traffic')
  const [selectedSourceID, setSelectedSourceID] = useState('')
  const [selectedKey, setSelectedKey] = useState('')
  const [range, setRange] = useState<TrafficRange>('6h')

  const sourcesQuery = useQuery({
    queryKey: ['sources'],
    queryFn: getSources,
    refetchInterval: 30_000,
  })

  const sources = sourcesQuery.data ?? emptySources
  const effectiveSourceID = selectedSourceID || sources[0]?.id || ''
  const selectedSource = sources.find((source) => source.id === effectiveSourceID)

  const peersQuery = useQuery({
    queryKey: ['peers', effectiveSourceID],
    queryFn: () => getPeers(effectiveSourceID),
    enabled: Boolean(effectiveSourceID),
    refetchInterval: 3_000,
  })

  const peers = peersQuery.data ?? emptyPeers
  const effectiveSelectedKey = selectedKey || peers[0]?.public_key || ''

  const selectedPeer = useMemo(
    () => peers.find((peer) => peer.public_key === effectiveSelectedKey),
    [peers, effectiveSelectedKey],
  )

  const trafficQuery = useQuery({
    queryKey: ['traffic', effectiveSourceID, effectiveSelectedKey, range],
    queryFn: () => getTraffic(effectiveSourceID, effectiveSelectedKey, range),
    enabled: Boolean(effectiveSourceID && effectiveSelectedKey),
    refetchInterval: 30_000,
  })

  const debugQuery = useQuery({
    queryKey: ['debug'],
    queryFn: getDebugInfo,
    enabled: tab === 'debug',
    refetchInterval: 15_000,
  })

  const onlineCount = peers.filter((peer) => getPeerStatus(peer.last_handshake) === 'online').length
  const totalRx = peers.reduce((sum, peer) => sum + peer.rx_bytes, 0)
  const totalTx = peers.reduce((sum, peer) => sum + peer.tx_bytes, 0)

  return (
    <div className="shell">
      <header className="topbar">
        <div>
          <div className="eyebrow">Self-hosted AmneziaVPN</div>
          <h1>Amnezia Panel</h1>
        </div>
        <div className="top-actions">
          <div className="tabs" role="tablist" aria-label="Panel sections">
            <button className={tab === 'traffic' ? 'active' : ''} type="button" onClick={() => setTab('traffic')}>
              Traffic
            </button>
            <button className={tab === 'debug' ? 'active' : ''} type="button" onClick={() => setTab('debug')}>
              Debug
            </button>
          </div>
          <button className="icon-button" type="button" onClick={() => refreshAll(peersQuery.refetch, debugQuery.refetch)} title="Refresh">
            <RefreshCcw size={18} />
          </button>
        </div>
      </header>

      <main className="dashboard">
        <SourceSwitcher
          sources={sources}
          selectedID={effectiveSourceID}
          isLoading={sourcesQuery.isLoading}
          error={sourcesQuery.error}
          onSelect={(sourceID) => {
            setSelectedSourceID(sourceID)
            setSelectedKey('')
          }}
        />

        {tab === 'traffic' ? (
          <>
            <section className="summary-grid" aria-label="Overview">
              <SummaryCard icon={<Server size={18} />} label="Peers" value={String(peers.length)} meta={`${onlineCount} online`} />
              <SummaryCard icon={<Download size={18} />} label="Total RX" value={formatBytes(totalRx)} meta={selectedSource?.label ?? 'selected source'} />
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
          </>
        ) : (
          <DebugPanel data={debugQuery.data} isLoading={debugQuery.isLoading} error={debugQuery.error} />
        )}
      </main>
    </div>
  )
}

function refreshAll(refetchPeers: () => unknown, refetchDebug: () => unknown) {
  refetchPeers()
  refetchDebug()
}

function SourceSwitcher({
  sources,
  selectedID,
  isLoading,
  error,
  onSelect,
}: {
  sources: Source[]
  selectedID: string
  isLoading: boolean
  error: Error | null
  onSelect: (sourceID: string) => void
}) {
  return (
    <section className="source-strip">
      <div>
        <div className="panel-title">Protocol</div>
        <div className="panel-subtitle">
          {isLoading ? 'Discovering Amnezia containers' : error ? error.message : `${sources.length} source${sources.length === 1 ? '' : 's'} discovered`}
        </div>
      </div>
      <div className="source-buttons" role="group" aria-label="VPN source">
        {sources.map((source) => (
          <button
            key={source.id}
            type="button"
            className={source.id === selectedID ? 'active' : ''}
            onClick={() => onSelect(source.id)}
          >
            <span>{source.label}</span>
            <small>{source.container || source.command}</small>
          </button>
        ))}
      </div>
    </section>
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
        {isLoading && <StateMessage title="Loading peers" detail="Waiting for protocol dump" />}
        {error && <StateMessage title="Could not load peers" detail={error.message} />}
        {!isLoading && !error && peers.length === 0 && <StateMessage title="No peers" detail="No clients returned by selected protocol" />}

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

function DebugPanel({ data, isLoading, error }: { data?: DebugInfo; isLoading: boolean; error: Error | null }) {
  if (isLoading) {
    return <StateMessage title="Loading debug info" detail="Collecting host and container diagnostics" />
  }

  if (error) {
    return <StateMessage title="Could not load debug info" detail={error.message} />
  }

  if (!data) {
    return <StateMessage title="No debug info" detail="Diagnostics endpoint returned no data" />
  }

  const memTotal = data.memory_kb.MemTotal ? data.memory_kb.MemTotal * 1024 : 0
  const memAvailable = data.memory_kb.MemAvailable ? data.memory_kb.MemAvailable * 1024 : 0
  const memUsed = Math.max(0, memTotal - memAvailable)

  return (
    <section className="debug-grid">
      <DebugCard title="System" icon={<TerminalSquare size={18} />}>
        <InfoRow label="Hostname" value={data.system.hostname} />
        <InfoRow label="Kernel" value={data.system.kernel || 'Unavailable'} />
        <InfoRow label="Load avg" value={data.system.load_avg || 'Unavailable'} />
        <InfoRow label="Uptime" value={data.system.uptime || 'Unavailable'} />
      </DebugCard>

      <DebugCard title="Runtime" icon={<Cpu size={18} />}>
        <InfoRow label="Go" value={data.runtime.go_version} />
        <InfoRow label="Target" value={`${data.runtime.goos}/${data.runtime.goarch}`} />
        <InfoRow label="CPU" value={String(data.runtime.num_cpu)} />
        <InfoRow label="Goroutines" value={String(data.runtime.goroutines)} />
      </DebugCard>

      <DebugCard title="Memory" icon={<MemoryStick size={18} />}>
        <InfoRow label="Total" value={formatBytes(memTotal)} />
        <InfoRow label="Used" value={formatBytes(memUsed)} />
        <InfoRow label="Available" value={formatBytes(memAvailable)} />
      </DebugCard>

      <DebugCard title="Disk" icon={<HardDrive size={18} />}>
        <InfoRow label="Path" value={data.disk.path} />
        <InfoRow label="Total" value={formatBytes(data.disk.total)} />
        <InfoRow label="Available" value={formatBytes(data.disk.available)} />
        <InfoRow label="Used" value={`${data.disk.used_pct.toFixed(1)}%`} />
      </DebugCard>

      <DebugCard title="Containers" icon={<Boxes size={18} />} wide>
        <div className="table">
          {data.containers.length === 0 && <InfoRow label="Amnezia" value="No target containers found" />}
          {data.containers.map((container) => (
            <div className="table-row" key={container.name}>
              <span>{container.name}</span>
              <span>{container.status || 'Unknown'}</span>
              <span>{container.image}</span>
            </div>
          ))}
        </div>
      </DebugCard>

      <DebugCard title="Network" icon={<Network size={18} />} wide>
        <div className="table">
          {data.network.map((item) => (
            <div className="table-row" key={item.interface}>
              <span>{item.interface}</span>
              <span>RX {formatBytes(item.rx_bytes)}</span>
              <span>TX {formatBytes(item.tx_bytes)}</span>
            </div>
          ))}
        </div>
      </DebugCard>

      <DebugCard title="Database" icon={<Database size={18} />}>
        <InfoRow label="Generated" value={new Date(data.generated_at).toLocaleString()} />
        <InfoRow label="Samples" value="peer_samples" />
      </DebugCard>
    </section>
  )
}

function DebugCard({ title, icon, wide, children }: { title: string; icon: ReactNode; wide?: boolean; children: ReactNode }) {
  return (
    <section className={`debug-card ${wide ? 'wide' : ''}`}>
      <div className="debug-title">
        <span>{icon}</span>
        <strong>{title}</strong>
      </div>
      {children}
    </section>
  )
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="info-row">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
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
