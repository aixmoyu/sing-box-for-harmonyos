export type NodeLatencyQuality = 'untested' | 'fast' | 'normal' | 'slow' | 'very_slow' | 'failed'

/**
 * Classifies measured round-trip latency, not bandwidth or download speed.
 * The thresholds stay explicit so UI colors and sorting never imply a
 * throughput measurement that the app did not perform.
 */
export function classifyNodeLatency(milliseconds: number | undefined): NodeLatencyQuality {
  if (milliseconds === undefined) return 'untested'
  if (milliseconds < 0) return 'failed'
  if (milliseconds <= 100) return 'fast'
  if (milliseconds <= 250) return 'normal'
  if (milliseconds <= 600) return 'slow'
  return 'very_slow'
}

/** Successful measurements sort first by latency, untested nodes retain their
 * profile order next, and failed/timeout nodes remain last. A zero result lets
 * the caller's stable insertion sort preserve the original profile order. */
export function compareNodeLatency(left: number | undefined, right: number | undefined): number {
  const leftQuality: NodeLatencyQuality = classifyNodeLatency(left)
  const rightQuality: NodeLatencyQuality = classifyNodeLatency(right)
  const leftSuccess: boolean = leftQuality !== 'untested' && leftQuality !== 'failed'
  const rightSuccess: boolean = rightQuality !== 'untested' && rightQuality !== 'failed'
  if (leftSuccess && rightSuccess) return (left as number) - (right as number)
  if (leftSuccess) return -1
  if (rightSuccess) return 1
  if (leftQuality === 'untested' && rightQuality === 'failed') return -1
  if (leftQuality === 'failed' && rightQuality === 'untested') return 1
  return 0
}
