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
            type: ['lineX', 'clear'],
            title: {
              lineX: 'Select range',
              clear: 'Clear selection',
            },
          },
        },
      },
      brush: {
        toolbox: ['lineX', 'clear'],
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
    const handleBrushEnd = (event: unknown) => {
      const range = extractBrushRange(event)
      if (!range) return
      onRangeSelectRef.current(new Date(range.from).toISOString(), new Date(range.to).toISOString())
    }
    const handleBrushSelected = (event: unknown) => {
      if (isBrushClear(event)) {
        onSelectionClearRef.current()
      }
    }

    instanceRef.current.on('brushEnd', handleBrushEnd)
    instanceRef.current.on('brushSelected', handleBrushSelected)
    window.addEventListener('resize', resize)

    return () => {
      window.removeEventListener('resize', resize)
      instanceRef.current?.off('brushEnd', handleBrushEnd)
      instanceRef.current?.off('brushSelected', handleBrushSelected)
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
    coordRange?: [number | string, number | string]
  }>
  batch?: Array<{
    areas?: Array<{
      coordRange?: [number | string, number | string]
    }>
  }>
}

function isBrushClear(event: unknown) {
  const areas = brushAreas(event)
  return Array.isArray(areas) && areas.length === 0
}

function extractBrushRange(event: unknown) {
  const coordRange = brushAreas(event)?.find((area) => area.coordRange)?.coordRange
  if (!coordRange) return null

  const from = Number(coordRange[0])
  const to = Number(coordRange[1])
  if (!Number.isFinite(from) || !Number.isFinite(to) || from >= to) {
    return null
  }

  return { from, to }
}

function brushAreas(event: unknown) {
  const payload = event as BrushEndEvent
  return payload.areas ?? payload.batch?.[0]?.areas
}

function getStateMessage(isLoading: boolean, error: Error | null, pointCount: number) {
	if (isLoading) return 'Loading traffic history'
	if (error) return `Could not load traffic history: ${error.message}`
	if (pointCount === 0) return 'No traffic history for this range yet'
	return ''
}
