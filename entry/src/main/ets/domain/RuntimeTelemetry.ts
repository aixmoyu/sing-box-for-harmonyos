export interface TrafficSample {
  session: string
  at: number
  upload: number
  download: number
}

export interface TrafficRates { upload: number; download: number }

// IPC may deliver the same native sample more than once. Only a newer sample
// can change the displayed rates; duplicate reads must not manufacture zeroes.
export function trafficRates(previous: TrafficSample | null, current: TrafficSample): TrafficRates | null {
  if (previous && current.session === previous.session && current.at <= previous.at) return null
  if (!previous || current.session !== previous.session || current.upload < previous.upload ||
    current.download < previous.download) return { upload: 0, download: 0 }
  const seconds: number = (current.at - previous.at) / 1000
  return { upload: (current.upload - previous.upload) / seconds,
    download: (current.download - previous.download) / seconds }
}

export function delayColor(delay: number): string {
  if (delay <= 0) return '#DADCE2'
  return delay < 800 ? '#3A8270' : delay < 1500 ? '#B08236' : '#BA4C4C'
}
