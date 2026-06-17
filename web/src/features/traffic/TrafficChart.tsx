import { useEffect, useMemo, useRef } from 'react'
import * as echarts from 'echarts/core'
import { DataZoomComponent, GridComponent, LegendComponent, ToolboxComponent, TooltipComponent } from 'echarts/components'
import { LineChart } from 'echarts/charts'
import { CanvasRenderer } from 'echarts/renderers'
import type { EChartsType } from 'echarts/core'
import type { TrafficResponse } from '../../api/types'
import { formatBytes } from '../../lib/format'

echarts.use([DataZoomComponent, GridComponent, LegendComponent, ToolboxComponent, TooltipComponent, LineChart, CanvasRenderer])

type Props = {
  data?: TrafficResponse
  isLoading: boolean
  error: Error | null
  onRangeSelect: (from: string, to: string) => void
}

export function TrafficChart({ data, isLoading, error, onRangeSelect }: Props) {
	const chartRef = useRef<HTMLDivElement | null>(null)
	const instanceRef = useRef<EChartsType | null>(null)
  const onRangeSelectRef = useRef(onRangeSelect)
  const timestampsRef = useRef<number[]>([])

  const points = useMemo(() => data?.points ?? [], [data?.points])
  const timestamps = useMemo(() => points.map((point) => new Date(point.collected_at).getTime()), [points])

  useEffect(() => {
    onRangeSelectRef.current = onRangeSelect
  }, [onRangeSelect])

  useEffect(() => {
    timestampsRef.current = timestamps
  }, [timestamps])

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
          dataZoom: {
            yAxisIndex: 'none',
            title: {
              zoom: 'Select range',
              back: 'Reset zoom',
            },
          },
          restore: {
            title: 'Reset chart',
          },
        },
      },
      grid: {
        left: 12,
        right: 18,
        top: 42,
        bottom: 62,
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
      dataZoom: [
        {
          type: 'inside',
          xAxisIndex: 0,
          filterMode: 'none',
          minSpan: 1,
        },
        {
          type: 'slider',
          xAxisIndex: 0,
          height: 28,
          bottom: 16,
          filterMode: 'none',
          borderColor: '#2c2d30',
          fillerColor: 'rgba(255, 174, 91, 0.16)',
          handleStyle: { color: '#ffae5b' },
          moveHandleStyle: { color: '#ffc27d' },
          textStyle: { color: '#868b91' },
        },
      ],
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
    const handleDataZoom = (event: unknown) => {
      const range = extractZoomRange(event, timestampsRef.current)
      if (!range) return
      onRangeSelectRef.current(new Date(range.from).toISOString(), new Date(range.to).toISOString())
    }

    instanceRef.current.on('datazoom', handleDataZoom)
    window.addEventListener('resize', resize)

    return () => {
      window.removeEventListener('resize', resize)
      instanceRef.current?.off('datazoom', handleDataZoom)
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

type DataZoomEvent = {
  start?: number
  end?: number
  startValue?: number
  endValue?: number
  batch?: Array<{
    start?: number
    end?: number
    startValue?: number
    endValue?: number
  }>
}

function extractZoomRange(event: unknown, timestamps: number[]) {
  if (timestamps.length < 2) return null

  const payload = event as DataZoomEvent
  const zoom = payload.batch?.[0] ?? payload
  const from = normalizeZoomValue(zoom.startValue, zoom.start, timestamps)
  const to = normalizeZoomValue(zoom.endValue, zoom.end, timestamps)

  if (!Number.isFinite(from) || !Number.isFinite(to) || from >= to) {
    return null
  }

  return { from, to }
}

function normalizeZoomValue(value: number | undefined, percent: number | undefined, timestamps: number[]) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    if (value >= 0 && value < timestamps.length && Number.isInteger(value)) {
      return timestamps[value]
    }
    return value
  }

  if (typeof percent === 'number' && Number.isFinite(percent)) {
    const min = timestamps[0]
    const max = timestamps[timestamps.length - 1]
    return min + ((max - min) * percent) / 100
  }

  return Number.NaN
}

function getStateMessage(isLoading: boolean, error: Error | null, pointCount: number) {
	if (isLoading) return 'Loading traffic history'
	if (error) return `Could not load traffic history: ${error.message}`
	if (pointCount === 0) return 'No traffic history for this range yet'
	return ''
}
