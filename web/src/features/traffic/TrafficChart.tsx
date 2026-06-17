import { useEffect, useMemo, useRef } from 'react'
import * as echarts from 'echarts/core'
import { BrushComponent, GridComponent, LegendComponent, ToolboxComponent, TooltipComponent } from 'echarts/components'
import { LineChart } from 'echarts/charts'
import { CanvasRenderer } from 'echarts/renderers'
import type { EChartsType } from 'echarts/core'
import type { TrafficResponse } from '../../api/types'
import { formatBytes } from '../../lib/format'

echarts.use([BrushComponent, GridComponent, LegendComponent, ToolboxComponent, TooltipComponent, LineChart, CanvasRenderer])

type Props = {
  data?: TrafficResponse
  isLoading: boolean
  error: Error | null
  onRangeSelect: (from: string, to: string) => void
  onSelectionClear: () => void
}

export function TrafficChart({ data, isLoading, error, onRangeSelect, onSelectionClear }: Props) {
	const chartRef = useRef<HTMLDivElement | null>(null)
	const instanceRef = useRef<EChartsType | null>(null)
  const onRangeSelectRef = useRef(onRangeSelect)
  const onSelectionClearRef = useRef(onSelectionClear)
  const lastAppliedRangeRef = useRef('')

  const points = useMemo(() => data?.points ?? [], [data?.points])

  useEffect(() => {
    onRangeSelectRef.current = onRangeSelect
  }, [onRangeSelect])

  useEffect(() => {
    onSelectionClearRef.current = onSelectionClear
  }, [onSelectionClear])

  const option = useMemo(() => {
    const rxData = points.map((point) => [new Date(point.collected_at).getTime(), point.rx_bytes])
    const txData = points.map((point) => [new Date(point.collected_at).getTime(), point.tx_bytes])

	return {
		color: ['#ffae5b', '#d7d8db'],
      tooltip: {
        trigger: 'axis',
        valueFormatter: (value: number | string) => formatBytes(Number(value)),
      },
		legend: {
			top: 0,
			textStyle: { color: '#868b91' },
      },
      toolbox: {
        right: 14,
        top: 0,
        iconStyle: {
          borderColor: '#868b91',
        },
        emphasis: {
          iconStyle: {
            borderColor: '#ffae5b',
          },
        },
        feature: {
          brush: {
            type: ['lineX'],
            title: {
              lineX: 'Select range',
            },
          },
          clearRange: {
            show: true,
            title: 'Clear selection',
            icon: 'path://M5 5 L19 19 M19 5 L5 19',
            onclick: () => {
              lastAppliedRangeRef.current = ''
              instanceRef.current?.dispatchAction({
                type: 'brush',
                areas: [],
              })
              onSelectionClearRef.current()
            },
          },
        },
      },
      brush: {
        toolbox: ['lineX'],
        xAxisIndex: 0,
        brushMode: 'single',
        transformable: false,
        brushStyle: {
          color: 'rgba(255, 174, 91, 0.14)',
          borderColor: '#ffae5b',
          borderWidth: 1,
        },
      },
      grid: {
        left: 12,
        right: 18,
        top: 42,
        bottom: 12,
        containLabel: true,
      },
      xAxis: {
        type: 'time',
        boundaryGap: false,
			axisLine: { lineStyle: { color: '#2c2d30' } },
			axisLabel: { color: '#868b91', hideOverlap: true },
        axisTick: { show: false },
      },
      yAxis: {
        type: 'value',
        axisLabel: {
				color: '#868b91',
				formatter: (value: number) => formatBytes(value),
			},
			splitLine: { lineStyle: { color: '#2c2d30' } },
      },
      series: [
        {
          name: 'RX',
          type: 'line',
          smooth: true,
          showSymbol: false,
          areaStyle: { opacity: 0.12 },
          data: rxData,
        },
        {
          name: 'TX',
          type: 'line',
          smooth: true,
          showSymbol: false,
          areaStyle: { opacity: 0.1 },
          data: txData,
        },
      ],
    }
  }, [points])

  useEffect(() => {
    if (!chartRef.current) return

    instanceRef.current = echarts.init(chartRef.current, undefined, { renderer: 'canvas' })

    const resize = () => instanceRef.current?.resize()
    const handleBrushEvent = (event: unknown) => {
      const range = extractBrushRange(event)
      if (!range) return

      const rangeKey = `${range.from}:${range.to}`
      if (rangeKey === lastAppliedRangeRef.current) return

      lastAppliedRangeRef.current = rangeKey
      onRangeSelectRef.current(new Date(range.from).toISOString(), new Date(range.to).toISOString())
    }
    const handleBrushEnd = (event: unknown) => {
      handleBrushEvent(event)
    }

    instanceRef.current.on('brushEnd', handleBrushEnd)
    window.addEventListener('resize', resize)

    return () => {
      window.removeEventListener('resize', resize)
      instanceRef.current?.off('brushEnd', handleBrushEnd)
      instanceRef.current?.dispose()
      instanceRef.current = null
    }
  }, [])

	useEffect(() => {
		if (!instanceRef.current) return

		instanceRef.current.setOption(option, true)
		instanceRef.current.resize()
	}, [option, isLoading])

	const stateMessage = getStateMessage(isLoading, error, points.length)

	return (
		<div className="chart-shell">
			<div ref={chartRef} className="traffic-chart" />
			{stateMessage && (
				<div className={`chart-state ${error ? 'danger' : ''}`}>
					{stateMessage}
				</div>
			)}
		</div>
	)
}

type BrushEndEvent = {
  areas?: Array<{
    coordRange?: BrushCoordRange
  }>
  batch?: Array<{
    areas?: Array<{
      coordRange?: BrushCoordRange
    }>
  }>
}

type BrushCoordRange = [number | string, number | string] | [[number | string, number | string]]

function extractBrushRange(event: unknown) {
  const coordRange = normalizeCoordRange(brushAreas(event)?.find((area) => area.coordRange)?.coordRange)
  if (!coordRange) return null

  const from = parseCoordValue(coordRange[0])
  const to = parseCoordValue(coordRange[1])
  if (!Number.isFinite(from) || !Number.isFinite(to) || from >= to) {
    return null
  }

  return { from, to }
}

function brushAreas(event: unknown) {
  const payload = event as BrushEndEvent
  return payload.areas ?? payload.batch?.[0]?.areas
}

function normalizeCoordRange(value?: BrushCoordRange) {
  if (!value) return null
  if (Array.isArray(value[0])) {
    return value[0]
  }
  return value as [number | string, number | string]
}

function parseCoordValue(value: number | string) {
  if (typeof value === 'number') return value

  const numeric = Number(value)
  if (Number.isFinite(numeric)) return numeric

  const timestamp = Date.parse(value)
  if (Number.isFinite(timestamp)) return timestamp

  return Number.NaN
}

function getStateMessage(isLoading: boolean, error: Error | null, pointCount: number) {
	if (isLoading) return 'Loading traffic history'
	if (error) return `Could not load traffic history: ${error.message}`
	if (pointCount === 0) return 'No traffic history for this range yet'
	return ''
}
