// LAN clipboard sync, the protocol of fcitx5-android (InsightKey fork) remote/:
// - HTTP on TCP 51423: GET /clipboard?limit=N lists history entries as
//   {"count":n,"items":[{"id","content","timestamp"}]}; POST /clipboard with
//   {"content"|"text","timestamp","sensitive"} puts text on the clipboard and in the history.
// - UDP 39393: answers {"type":"discover","app":"insightkey_clipboard"} with discover_ack.
// Runs in the input method process, which keeps the clipboard history.
import { socket } from '@kit.NetworkKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { util } from '@kit.ArkTS'
import { ClipboardEntry, ClipboardStore } from './ClipboardStore'

export const HTTP_PORT = 51423
export const UDP_PORT = 39393
export const APP_ID = 'insightkey_clipboard'

interface IncomingPayload {
  content?: string
  text?: string
}

interface DiscoverPacket {
  type?: string
  app?: string
  replyPort?: number
}

interface DiscoverAck {
  type: string
  app: string
  deviceId: string
  deviceName: string
  httpPort: number
  udpPort: number
  version: number
  timestamp: number
}

interface ItemJson {
  id: number
  content: string
  timestamp: number
}

interface ListJson {
  count: number
  items: ItemJson[]
}

const encoder = new util.TextEncoder()
const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true })

function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const result = new Uint8Array(a.length + b.length)
  result.set(a)
  result.set(b, a.length)
  return result
}

function findHeaderEnd(bytes: Uint8Array): number {
  for (let i = 0; i + 3 < bytes.length; i++) {
    if (bytes[i] === 13 && bytes[i + 1] === 10 && bytes[i + 2] === 13 && bytes[i + 3] === 10) {
      return i
    }
  }
  return -1
}

function response(code: number, body: string, contentType: string = 'text/plain; charset=utf-8'): ArrayBuffer {
  const statuses: Record<string, string> = {
    '200': '200 OK',
    '204': '204 No Content',
    '400': '400 Bad Request',
    '404': '404 Not Found',
    '405': '405 Method Not Allowed',
  }
  const payload = encoder.encodeInto(body)
  const header = `HTTP/1.1 ${statuses[`${code}`] ?? `${code} Error`}\r\n` +
    `Content-Type: ${contentType}\r\n` +
    `Content-Length: ${payload.length}\r\n` +
    'Connection: close\r\n' +
    'Access-Control-Allow-Origin: *\r\n' +
    'Access-Control-Allow-Methods: GET,POST,OPTIONS\r\n' +
    'Access-Control-Allow-Headers: Content-Type\r\n\r\n'
  return concat(encoder.encodeInto(header), payload).buffer as ArrayBuffer
}

export class ClipboardSync {
  private server: socket.TCPSocketServer | null = null
  private udp: socket.UDPSocket | null = null
  private store: ClipboardStore
  private deviceId: string
  private deviceName: string
  // Called when a client gets or posts entries, e.g. to refresh the panel.
  private onChange: () => void
  private onAccess: () => void

  constructor(store: ClipboardStore, deviceId: string, deviceName: string, onChange: () => void,
    onAccess: () => void) {
    this.store = store
    this.deviceId = deviceId
    this.deviceName = deviceName
    this.onChange = onChange
    this.onAccess = onAccess
  }

  get running(): boolean {
    return this.server !== null
  }

  ack(): string {
    const ack: DiscoverAck = {
      type: 'discover_ack',
      app: APP_ID,
      deviceId: this.deviceId,
      deviceName: this.deviceName,
      httpPort: HTTP_PORT,
      udpPort: UDP_PORT,
      version: 1,
      timestamp: Date.now(),
    }
    return JSON.stringify(ack)
  }

  async start() {
    if (this.server) {
      return
    }
    const server = socket.constructTCPSocketServerInstance()
    this.server = server
    server.on('connect', (client: socket.TCPSocketConnection) => this.serve(client))
    try {
      await server.listen({ address: '0.0.0.0', port: HTTP_PORT, family: 1 })
    } catch (e) {
      console.error(`Clipboard sync HTTP failed: ${JSON.stringify(e)}`)
    }
    const udp = socket.constructUDPSocketInstance()
    this.udp = udp
    udp.on('message', (info: socket.SocketMessageInfo) => this.discover(info))
    try {
      await udp.bind({ address: '0.0.0.0', port: UDP_PORT, family: 1 })
    } catch (e) {
      console.error(`Clipboard sync discovery failed: ${JSON.stringify(e)}`)
    }
  }

  stop() {
    this.server?.off('connect')
    this.server = null
    this.udp?.close()
    this.udp = null
  }

  private discover(info: socket.SocketMessageInfo) {
    try {
      const packet = JSON.parse(decoder.decodeToString(new Uint8Array(info.message))) as DiscoverPacket
      if (packet.type !== 'discover' || packet.app !== APP_ID) {
        return
      }
      const port = packet.replyPort && packet.replyPort > 0 && packet.replyPort < 65536 ?
        packet.replyPort : info.remoteInfo.port
      this.udp?.send({ data: this.ack(), address: { address: info.remoteInfo.address, port: port, family: 1 } })
    } catch (e) {
      // Not a discovery packet.
    }
  }

  private serve(client: socket.TCPSocketConnection) {
    let buffer = new Uint8Array(0)
    let done = false
    client.on('message', (info: socket.SocketMessageInfo) => {
      if (done) {
        return
      }
      buffer = concat(buffer, new Uint8Array(info.message))
      const headerEnd = findHeaderEnd(buffer)
      if (headerEnd < 0) {
        return
      }
      const header = decoder.decodeToString(buffer.subarray(0, headerEnd))
      const lines = header.split('\r\n')
      const match = /^(\S+)\s+(\S+)/.exec(lines[0])
      let length = 0
      for (const line of lines.slice(1)) {
        const index = line.indexOf(':')
        if (index > 0 && line.substring(0, index).trim().toLowerCase() === 'content-length') {
          length = Number.parseInt(line.substring(index + 1).trim()) || 0
        }
      }
      if (buffer.length < headerEnd + 4 + length) {
        return
      }
      done = true
      const body = decoder.decodeToString(buffer.subarray(headerEnd + 4, headerEnd + 4 + length))
      const reply = match ? this.handle(match[1].toUpperCase(), match[2], body) : response(400, 'Bad Request')
      client.send({ data: reply }).finally(() => client.close())
    })
  }

  private handle(method: string, path: string, body: string): ArrayBuffer {
    const route = path.split('?')[0]
    if (method === 'OPTIONS') {
      return response(204, '')
    }
    if (route !== '/clipboard' && route !== '/') {
      return response(404, 'Not Found')
    }
    if (method === 'GET') {
      this.onAccess()
      const match = /[?&]limit=(\d+)/.exec(path)
      const limit = Math.min(200, Math.max(1, match ? Number.parseInt(match[1]) : 20))
      const items = this.store.list().slice(0, limit).map((e: ClipboardEntry): ItemJson => ({
        id: e.id,
        content: e.text,
        timestamp: e.time,
      }))
      const list: ListJson = { count: items.length, items: items }
      return response(200, JSON.stringify(list), 'application/json; charset=utf-8')
    }
    if (method === 'POST') {
      this.onAccess()
      let text = body.trim()
      try {
        const payload = JSON.parse(text) as IncomingPayload
        text = (payload.content || payload.text || '').trim()
      } catch (e) {
        // Plain text body.
      }
      if (text) {
        this.store.add(text)
        try {
          pasteboard.getSystemPasteboard().setDataSync(
            pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text))
        } catch (e) {
          console.error(`Failed to set clipboard: ${e}`)
        }
        this.onChange()
      }
      return response(200, '{"ok":true}', 'application/json; charset=utf-8')
    }
    return response(405, 'Method Not Allowed')
  }
}
