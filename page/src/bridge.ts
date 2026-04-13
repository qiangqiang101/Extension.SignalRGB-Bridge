import type { ScriptInfo, ScriptsSnapshotPayload } from './types'
import { setLocale } from './i18n'

interface ExtPageEnv {
  extId: string
  wsUrl: string
  locale?: string
}

declare global {
  interface Window {
    __SKYDIMO_EXT_PAGE__?: Partial<ExtPageEnv>
  }
}

export type ConnectionStatus = 'disconnected' | 'connecting' | 'connected'

export type BridgeEvent =
  | { type: 'scripts_snapshot'; data: ScriptsSnapshotPayload }

type BridgeListener = (event: BridgeEvent) => void
type StatusListener = (status: ConnectionStatus) => void

const PAGE: ExtPageEnv = {
  extId: window.__SKYDIMO_EXT_PAGE__?.extId ?? 'signalrgb_bridge',
  wsUrl: window.__SKYDIMO_EXT_PAGE__?.wsUrl ?? 'ws://127.0.0.1:42070',
}

function normalizeScripts(value: unknown): ScriptInfo[] {
  if (!Array.isArray(value)) return []
  return value.filter((s): s is ScriptInfo => !!s && typeof s === 'object' && typeof s.path === 'string')
}

class ExtensionBridge {
  private ws: WebSocket | null = null
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null
  private listeners = new Set<BridgeListener>()
  private statusListeners = new Set<StatusListener>()
  private rpcId = 1
  private status: ConnectionStatus = 'disconnected'

  getStatus() {
    return this.status
  }

  subscribe(listener: BridgeListener) {
    this.listeners.add(listener)
    return () => this.listeners.delete(listener)
  }

  subscribeStatus(listener: StatusListener) {
    this.statusListeners.add(listener)
    listener(this.status)
    return () => this.statusListeners.delete(listener)
  }

  connect() {
    if (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING)) {
      return
    }

    this.setStatus('connecting')
    this.ws = new WebSocket(PAGE.wsUrl)

    this.ws.onopen = () => {
      this.setStatus('connected')
      this.send('bootstrap')
    }

    this.ws.onmessage = (event) => {
      let payload: Record<string, unknown>
      try {
        payload = JSON.parse(event.data) as Record<string, unknown>
      } catch {
        return
      }

      if (payload.method !== 'event' || typeof payload.params !== 'object' || payload.params === null) {
        return
      }

      const params = payload.params as Record<string, unknown>
      const eventName = typeof params.event === 'string' ? params.event : ''

      if (eventName === 'locale-changed') {
        const locale = typeof (params.data as Record<string, unknown> | undefined)?.locale === 'string'
          ? (params.data as Record<string, unknown>).locale as string
          : null
        if (locale) {
          setLocale(locale)
        }
        return
      }

      if (eventName !== `ext-page-message:${PAGE.extId}`) {
        return
      }

      const data = params.data
      if (!data || typeof data !== 'object') {
        return
      }

      const msg = data as Record<string, unknown>
      if (typeof msg.type !== 'string') {
        return
      }

      if (msg.type === 'scripts_snapshot') {
        const bridgeEvent: BridgeEvent = {
          type: 'scripts_snapshot',
          data: { scripts: normalizeScripts((msg as Record<string, unknown>).scripts) },
        }
        for (const listener of this.listeners) {
          listener(bridgeEvent)
        }
      }
    }

    this.ws.onclose = () => {
      this.ws = null
      this.setStatus('disconnected')
      this.reconnectTimer = setTimeout(() => this.connect(), 3000)
    }

    this.ws.onerror = () => {
      // onclose handles reconnection.
    }
  }

  disconnect() {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }
    if (this.ws) {
      this.ws.close()
      this.ws = null
    }
    this.setStatus('disconnected')
  }

  send(type: string, payload: Record<string, unknown> = {}) {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      return
    }

    const message = {
      jsonrpc: '2.0',
      id: this.rpcId++,
      method: 'ext_page_send',
      params: {
        extId: PAGE.extId,
        data: {
          type,
          ...payload,
        },
      },
    }

    this.ws.send(JSON.stringify(message))
  }

  private setStatus(status: ConnectionStatus) {
    this.status = status
    for (const listener of this.statusListeners) {
      listener(status)
    }
  }
}

export const bridge = new ExtensionBridge()
