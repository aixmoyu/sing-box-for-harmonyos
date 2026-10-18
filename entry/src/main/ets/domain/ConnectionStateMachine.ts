export type ConnectionState = 'idle' | 'preparing' | 'authorizing' | 'connecting' | 'connected' |
  'reconnecting' | 'stopping' | 'error'

export type ConnectionEvent = 'CONNECT' | 'PREPARED' | 'AUTHORIZED' | 'CONNECTED' | 'NETWORK_CHANGED' |
  'STOP' | 'STOPPED' | 'FAILED' | 'RETRY'

interface Transition {
  from: ConnectionState
  event: ConnectionEvent
  to: ConnectionState
}

const TRANSITIONS: Transition[] = [
  { from: 'idle', event: 'CONNECT', to: 'preparing' },
  { from: 'preparing', event: 'PREPARED', to: 'authorizing' },
  { from: 'authorizing', event: 'AUTHORIZED', to: 'connecting' },
  { from: 'connecting', event: 'CONNECTED', to: 'connected' },
  { from: 'connected', event: 'NETWORK_CHANGED', to: 'reconnecting' },
  { from: 'reconnecting', event: 'CONNECTED', to: 'connected' },
  { from: 'preparing', event: 'STOP', to: 'stopping' },
  { from: 'authorizing', event: 'STOP', to: 'stopping' },
  { from: 'connecting', event: 'STOP', to: 'stopping' },
  { from: 'connected', event: 'STOP', to: 'stopping' },
  { from: 'reconnecting', event: 'STOP', to: 'stopping' },
  { from: 'error', event: 'STOP', to: 'stopping' },
  { from: 'stopping', event: 'STOPPED', to: 'idle' },
  { from: 'error', event: 'RETRY', to: 'preparing' }
]

export class ConnectionStateMachine {
  private currentState: ConnectionState = 'idle'
  private failureReason: string = ''

  state(): ConnectionState {
    return this.currentState
  }

  errorReason(): string {
    return this.failureReason
  }

  dispatch(event: ConnectionEvent, reason: string = ''): ConnectionState {
    if (event === 'FAILED' && this.currentState !== 'idle' && this.currentState !== 'stopping') {
      this.currentState = 'error'
      this.failureReason = reason
      return this.currentState
    }
    for (let index: number = 0; index < TRANSITIONS.length; index++) {
      const transition: Transition = TRANSITIONS[index]
      if (transition.from === this.currentState && transition.event === event) {
        this.currentState = transition.to
        if (this.currentState !== 'error') this.failureReason = ''
        return this.currentState
      }
    }
    throw new Error(`非法连接状态变更：${this.currentState} + ${event}`)
  }
}

