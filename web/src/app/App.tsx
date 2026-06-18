import { useEffect, useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Activity,
  Boxes,
  CalendarClock,
  Check,
  Clock3,
  Cpu,
  Database,
  Download,
  HardDrive,
  MemoryStick,
  Network,
  Pencil,
  RefreshCcw,
  Server,
  TerminalSquare,
  Upload,
  X,
} from 'lucide-react'
import { checkUpdates, getDebugInfo, getPeers, getSources, getTraffic, getTrafficTotal, renameClient } from '../api/peers'
import type { DebugInfo, Peer, Source, TrafficRequest, TrafficRange, UpdateCheckResponse } from '../api/types'
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
type RangeSelection =
  | { type: 'preset'; value: TrafficRange; label: string }
  | { type: 'chart'; from: string; to: string; label: string }
  | { type: 'custom'; from: string; to: string; label: string }

type RangeEditor = 'closed' | 'custom'

export function App() {
  const queryClient = useQueryClient()
  const [tab, setTab] = useState<Tab>('traffic')
  const [selectedSourceID, setSelectedSourceID] = useState('')
  const [selectedKey, setSelectedKey] = useState('')
  const [rangeSelection, setRangeSelection] = useState<RangeSelection>({ type: 'preset', value: '6h', label: '6H' })
  const [lastPresetRange, setLastPresetRange] = useState<Extract<RangeSelection, { type: 'preset' }>>({ type: 'preset', value: '6h', label: '6H' })
  const [rangeEditor, setRangeEditor] = useState<RangeEditor>('closed')
  const [customDraft, setCustomDraft] = useState(() => defaultCustomRange())
  const [clearBrushSignal, setClearBrushSignal] = useState(0)
  const customSelection = useMemo(() => parseCustomRange(customDraft), [customDraft])

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

  const trafficRequest = useMemo<TrafficRequest>(() => {
    if (rangeSelection.type === 'preset') {
      return { range: rangeSelection.value }
    }

    return {
      from: rangeSelection.from,
      to: rangeSelection.to,
    }
  }, [rangeSelection])

  const trafficQuery = useQuery({
    queryKey: ['traffic', effectiveSourceID, effectiveSelectedKey, trafficRequest],
    queryFn: () => getTraffic(effectiveSourceID, effectiveSelectedKey, trafficRequest),
    enabled: Boolean(effectiveSourceID && effectiveSelectedKey),
    refetchInterval: 30_000,
  })

  const totalTrafficQuery = useQuery({
    queryKey: ['traffic-total', effectiveSourceID, trafficRequest],
    queryFn: () => getTrafficTotal(effectiveSourceID, trafficRequest),
    enabled: Boolean(effectiveSourceID),
    refetchInterval: 30_000,
  })

  const debugQuery = useQuery({
    queryKey: ['debug'],
    queryFn: getDebugInfo,
    enabled: tab === 'debug',
    refetchInterval: 15_000,
  })

  const updateQuery = useQuery({
    queryKey: ['update-check'],
    queryFn: checkUpdates,
    refetchInterval: 60 * 60 * 1000,
    staleTime: 60 * 60 * 1000,
    refetchOnWindowFocus: false,
    retry: false,
  })

  const renameMutation = useMutation({
    mutationFn: renameClient,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['peers'] })
    },
  })

  useEffect(() => {
    if (tab === 'debug') {
      updateQuery.refetch()
    }
  }, [tab])

  const onlineCount = peers.filter((peer) => getPeerStatus(peer.last_handshake) === 'online').length
  const rangeRx = totalTrafficQuery.data?.rx_bytes
  const rangeTx = totalTrafficQuery.data?.tx_bytes
  const hasUpdate = Boolean(updateQuery.data?.available)
  const clearChartSelection = () => {
    setRangeEditor('closed')
    setRangeSelection(lastPresetRange)
    setClearBrushSignal((value) => value + 1)
  }

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
              {hasUpdate && <span className="tab-badge" aria-label="Update available" />}
            </button>
          </div>
          <button
            className="icon-button"
            type="button"
            onClick={() => refreshAll(peersQuery.refetch, trafficQuery.refetch, totalTrafficQuery.refetch, debugQuery.refetch)}
            title="Refresh"
          >
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
              <SummaryCard icon={<Download size={18} />} label="Total RX" value={formatBytes(rangeRx)} meta={rangeSelection.label} />
              <SummaryCard icon={<Upload size={18} />} label="Total TX" value={formatBytes(rangeTx)} meta={rangeSelection.label} />
              <SummaryCard icon={<Activity size={18} />} label="Collector" value={peersQuery.isError ? 'Error' : 'Active'} meta="3s refresh" />
            </section>

            <section className="workspace">
              <PeerList
                peers={peers}
                source={selectedSource}
                selectedKey={effectiveSelectedKey}
                isLoading={peersQuery.isLoading}
                error={peersQuery.error}
                isRenaming={renameMutation.isPending}
                renameError={renameMutation.error}
                onSelect={setSelectedKey}
                onRename={(peer, name) => {
                  if (!selectedSource?.container) return
                  renameMutation.mutate({
                    protocol: selectedSource.protocol,
                    container: selectedSource.container,
                    client_id: peer.public_key,
                    name,
                  })
                }}
              />

              <section className="traffic-panel">
                <div className="panel-header">
                  <div>
                    <div className="panel-title">Traffic history</div>
                    <div className="panel-subtitle">{selectedPeer ? peerDisplayName(selectedPeer) : 'Select a peer'}</div>
                  </div>
                  <div className="segmented" role="group" aria-label="Traffic range">
                    {ranges.map((item) => (
                      <button
                        key={item.value}
                        type="button"
                        className={rangeSelection.type === 'preset' && item.value === rangeSelection.value ? 'active' : ''}
                        onClick={() => {
                          const preset = { type: 'preset' as const, value: item.value, label: item.label }
                          setRangeEditor('closed')
                          setLastPresetRange(preset)
                          setRangeSelection(preset)
                        }}
                      >
                        {item.label}
                      </button>
                    ))}
                    <button
                      type="button"
                      className={rangeEditor === 'custom' || rangeSelection.type === 'custom' ? 'active' : ''}
                      onClick={() => setRangeEditor((current) => (current === 'custom' ? 'closed' : 'custom'))}
                    >
                      Custom
                    </button>
                  </div>
                </div>

                <div className="range-status">
                  <span>{rangeSelection.type === 'chart' ? 'Chart selection' : rangeSelection.type === 'custom' ? 'Custom range' : 'Preset range'}</span>
                  <div className="range-status-current">
                    <strong>{rangeSelection.label}</strong>
                    {rangeSelection.type === 'chart' ? (
                      <button className="clear-range-button" type="button" onClick={clearChartSelection}>
                        <X size={14} />
                        Clear range
                      </button>
                    ) : null}
                  </div>
                </div>

                {rangeEditor === 'custom' ? (
                  <form
                    className="custom-range"
                    onSubmit={(event) => {
                      event.preventDefault()
                      if (!customSelection) return
                      setRangeSelection(customSelection)
                      setRangeEditor('closed')
                    }}
                  >
                    <label>
                      <span>From</span>
                      <input
                        type="text"
                        placeholder="-24h or 2026-06-18 10:00"
                        value={customDraft.from}
                        onChange={(event) => setCustomDraft((current) => ({ ...current, from: event.target.value }))}
                      />
                    </label>
                    <label>
                      <span>To</span>
                      <input
                        type="text"
                        placeholder="now, -1h, or 2026-06-18 18:00"
                        value={customDraft.to}
                        onChange={(event) => setCustomDraft((current) => ({ ...current, to: event.target.value }))}
                      />
                    </label>
                    <button className="apply-range" type="submit" disabled={!customSelection}>
                      <CalendarClock size={15} />
                      Apply
                    </button>
                    <div className="custom-range-help">Supports now, -30m, -12h, -5d, -2w, and absolute date/time.</div>
                  </form>
                ) : null}

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
                  clearSignal={clearBrushSignal}
                  onRangeSelect={(from, to) => {
                    setRangeEditor('closed')
                    setRangeSelection({
                      type: 'chart',
                      from,
                      to,
                      label: formatRangeLabel(from, to),
                    })
                  }}
                  onSelectionClear={clearChartSelection}
                />
              </section>
            </section>
          </>
        ) : (
          <DebugPanel
            data={debugQuery.data}
            isLoading={debugQuery.isLoading}
            error={debugQuery.error}
            updateData={updateQuery.data}
            isUpdateLoading={updateQuery.isFetching}
            updateError={updateQuery.error}
            onUpdateCheck={() => updateQuery.refetch()}
          />
        )}
      </main>
    </div>
  )
}

function refreshAll(refetchPeers: () => unknown, refetchTraffic: () => unknown, refetchTotalTraffic: () => unknown, refetchDebug: () => unknown) {
  refetchPeers()
  refetchTraffic()
  refetchTotalTraffic()
  refetchDebug()
}

function formatRangeLabel(from: string, to: string) {
  const formatter = new Intl.DateTimeFormat(undefined, {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
  return `${formatter.format(new Date(from))} - ${formatter.format(new Date(to))}`
}

function defaultCustomRange() {
  return {
    from: '-24h',
    to: 'now',
  }
}

function parseCustomRange(range: { from: string; to: string }): RangeSelection | null {
  const now = new Date()
  const fromDate = parseRangeInput(range.from, now)
  const toDate = parseRangeInput(range.to, now)
  if (!fromDate || !toDate || fromDate.getTime() >= toDate.getTime()) {
    return null
  }

  const from = fromDate.toISOString()
  const to = toDate.toISOString()
  return {
    type: 'custom',
    from,
    to,
    label: formatRangeLabel(from, to),
  }
}

function parseRangeInput(value: string, now: Date) {
  const trimmed = value.trim()
  if (trimmed === '') return null
  if (trimmed.toLowerCase() === 'now') return now

  const relative = trimmed.match(/^(-|\+)?(\d+)(m|h|d|w)$/i)
  if (relative) {
    const sign = relative[1] === '+' ? 1 : -1
    const amount = Number(relative[2])
    const unit = relative[3].toLowerCase()
    const multipliers: Record<string, number> = {
      m: 60 * 1000,
      h: 60 * 60 * 1000,
      d: 24 * 60 * 60 * 1000,
      w: 7 * 24 * 60 * 60 * 1000,
    }
    return new Date(now.getTime() + sign * amount * multipliers[unit])
  }

  const normalized = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}/.test(trimmed) ? trimmed.replace(' ', 'T') : trimmed
  const parsed = new Date(normalized)
  if (Number.isNaN(parsed.getTime())) return null
  return parsed
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
  source,
  selectedKey,
  isLoading,
  error,
  isRenaming,
  renameError,
  onSelect,
  onRename,
}: {
  peers: Peer[]
  source?: Source
  selectedKey: string
  isLoading: boolean
  error: Error | null
  isRenaming: boolean
  renameError: Error | null
  onSelect: (key: string) => void
  onRename: (peer: Peer, name: string) => void
}) {
  const [isEditing, setIsEditing] = useState(false)
  const selectedPeer = peers.find((peer) => peer.public_key === selectedKey)
  const [nameDraft, setNameDraft] = useState('')
  const canRename = Boolean(selectedPeer && source?.container)

  useEffect(() => {
    if (!isEditing) {
      setNameDraft(selectedPeer ? peerDisplayName(selectedPeer) : '')
    }
  }, [isEditing, selectedPeer?.public_key, selectedPeer?.name])

  return (
    <section className="peer-panel">
      <div className="panel-header">
        <div>
          <div className="panel-title">Peers</div>
          <div className="panel-subtitle">{peers.length} configured clients</div>
        </div>
        <button
          className="icon-button"
          type="button"
          title="Rename selected client"
          disabled={!canRename || isRenaming}
          onClick={() => {
            if (!selectedPeer) return
            setNameDraft(peerDisplayName(selectedPeer))
            setIsEditing((current) => !current)
          }}
        >
          <Pencil size={17} />
        </button>
      </div>

      {isEditing && selectedPeer ? (
        <form
          className="rename-form"
          onSubmit={(event) => {
            event.preventDefault()
            const nextName = nameDraft.trim()
            if (!nextName) return
            onRename(selectedPeer, nextName)
            setIsEditing(false)
          }}
        >
          <input
            type="text"
            value={nameDraft}
            onChange={(event) => setNameDraft(event.target.value)}
            disabled={isRenaming}
            autoFocus
          />
          <button className="apply-range" type="submit" disabled={isRenaming || nameDraft.trim() === ''}>
            <Check size={15} />
            Rename
          </button>
          <button className="clear-range-button" type="button" onClick={() => setIsEditing(false)} disabled={isRenaming}>
            <X size={14} />
            Cancel
          </button>
        </form>
      ) : null}

      {renameError ? <div className="inline-error">{renameError.message}</div> : null}

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
                <span className={peer.name ? 'peer-name' : 'peer-key'}>{peerDisplayName(peer)}</span>
                {peer.name && <span className="peer-id">{shortKey(peer.public_key, 34)}</span>}
                <span className="peer-meta">
                  {formatRelativeHandshake(peer.last_handshake)}
                </span>
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

function peerDisplayName(peer: Peer) {
  return peer.name || shortKey(peer.public_key)
}

function DebugPanel({
  data,
  isLoading,
  error,
  updateData,
  isUpdateLoading,
  updateError,
  onUpdateCheck,
}: {
  data?: DebugInfo
  isLoading: boolean
  error: Error | null
  updateData?: UpdateCheckResponse
  isUpdateLoading: boolean
  updateError: Error | null
  onUpdateCheck: () => void
}) {
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
      <DebugCard title="Updates" icon={<RefreshCcw size={18} />} wide>
        <UpdateStatus data={updateData} isLoading={isUpdateLoading} error={updateError} onCheck={onUpdateCheck} />
      </DebugCard>

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

function UpdateStatus({
  data,
  isLoading,
  error,
  onCheck,
}: {
  data?: UpdateCheckResponse
  isLoading: boolean
  error: Error | null
  onCheck: () => void
}) {
  const shouldShowCommand = Boolean(data?.available || data?.requires_command || !data?.can_check)
  const latestID = data?.local_panel.latest_id ? shortImageID(data.local_panel.latest_id) : ''
  const currentID = data?.local_panel.current_id ? shortImageID(data.local_panel.current_id) : ''

  return (
    <div className="update-status">
      <div className="update-status-head">
        <div>
          <div className={`update-badge ${data?.available ? 'available' : data && data.can_check ? 'ok' : 'muted'}`}>
            {isLoading ? 'Checking' : data?.available ? 'Update available' : data?.can_check ? 'Up to date' : 'Manual check'}
          </div>
          <p>{error ? error.message : data?.message || 'Checking for the latest panel image about once per hour.'}</p>
        </div>
        <button className="apply-range" type="button" onClick={onCheck} disabled={isLoading}>
          <RefreshCcw size={15} />
          Check for updates
        </button>
      </div>

      {data ? (
        <div className="update-details">
          <InfoRow label="Image" value={data.local_panel.image} />
          {latestID && <InfoRow label="Latest" value={latestID} />}
          {currentID && <InfoRow label="Current" value={currentID} />}
          <InfoRow label="Checked" value={new Date(data.checked_at).toLocaleString()} />
        </div>
      ) : null}

      {shouldShowCommand && data?.command ? (
        <pre className="command-block">
          <code>{data.command}</code>
        </pre>
      ) : null}
    </div>
  )
}

function shortImageID(value: string) {
  return value.replace(/^sha256:/, '').slice(0, 12)
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
