import { useEffect, useMemo, useRef } from 'react'
import * as echarts from 'echarts/core'
import { GridComponent, LegendComponent, TooltipComponent } from 'echarts/components'
import { LineChart } from 'echarts/charts'
import { CanvasRenderer } from 'echarts/renderers'
import type { EChartsType } from 'echarts/core'
import type { TrafficResponse } from '../../api/types'
import { formatBytes } from '../../lib/format'

echarts.use([GridComponent, LegendComponent, TooltipComponent, LineChart, CanvasRenderer])

type Props = {
  data?: TrafficResponse
  isLoading: boolean
  error: Error | null
}

export function TrafficChart({ data, isLoading, error }: Props) {
	const chartRef = useRef<HTMLDivElement | null>(null)
	const instanceRef = useRef<EChartsType | null>(null)

  const points = useMemo(() => data?.points ?? [], [data?.points])

  const option = useMemo(() => {
    const labels = points.map((point) => new Date(point.collected_at).toLocaleString())

	return {
		color: ['#ffae5b', '#d7d8db'],
      tooltip: {
        trigger: 'axis',
        valueFormatter: (value: number) => formatBytes(value),
      },
		legend: {
			top: 0,
			textStyle: { color: '#868b91' },
      },
      grid: {
        left: 12,
        right: 18,
        top: 42,
        bottom: 12,
        containLabel: true,
      },
      xAxis: {
        type: 'category',
        boundaryGap: false,
        data: labels,
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
          data: points.map((point) => point.rx_bytes),
        },
        {
          name: 'TX',
          type: 'line',
          smooth: true,
          showSymbol: false,
          areaStyle: { opacity: 0.1 },
          data: points.map((point) => point.tx_bytes),
        },
      ],
    }
  }, [points])

  useEffect(() => {
    if (!chartRef.current) return

    instanceRef.current = echarts.init(chartRef.current, undefined, { renderer: 'canvas' })

    const resize = () => instanceRef.current?.resize()
    window.addEventListener('resize', resize)

    return () => {
      window.removeEventListener('resize', resize)
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

function getStateMessage(isLoading: boolean, error: Error | null, pointCount: number) {
	if (isLoading) return 'Loading traffic history'
	if (error) return `Could not load traffic history: ${error.message}`
	if (pointCount === 0) return 'No traffic history for this range yet'
	return ''
}
