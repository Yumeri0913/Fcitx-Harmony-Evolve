// LAN clipboard sync settings, like the pairing entry in fcitx5-android's (InsightKey fork)
// clipboard settings. The servers run in the input method; pairing broadcasts this phone
// from here until a computer connects.
import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { connection, socket } from '@kit.NetworkKit';
import {
  clipboardSyncAccessPath, clipboardSyncId, KeyboardSettings, loadSettings, readText, saveSettings
} from '../../common/Settings';

const HTTP_PORT = 51423
const UDP_PORT = 39393
const PAIRING_TIME = 120 * 1000

interface DiscoverAck {
  type: string
  app: string
  deviceId: string
  deviceName: string
  httpPort: number
  udpPort: number
  platform: string
  timestamp: number
}

@Component
export struct ClipboardSyncPage {
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext
  private sharedDir: string = this.context.distributedFilesDir
  @State settings: KeyboardSettings = loadSettings(this.sharedDir)
  @State address: string = ''
  @State pairing: boolean = false
  @State status: string = ''
  private timer: number = -1
  private udp: socket.UDPSocket | null = null

  aboutToAppear() {
    this.address = this.localAddress()
  }

  aboutToDisappear() {
    this.stopPairing()
  }

  private localAddress(): string {
    try {
      const net = connection.getDefaultNetSync()
      const properties = connection.getConnectionPropertiesSync(net)
      for (const link of properties.linkAddresses) {
        if (link.address.address.includes('.')) {
          return link.address.address
        }
      }
    } catch (e) {
      console.error(`Failed to get address: ${e}`)
    }
    return ''
  }

  private setEnabled(enabled: boolean) {
    this.settings.clipboardSync = enabled
    try {
      saveSettings(this.sharedDir, this.settings)
    } catch (e) {
      this.status = `保存失败：${e}`
    }
    if (!enabled) {
      this.stopPairing()
    }
  }

  private async startPairing() {
    const started = Date.now()
    const ack: DiscoverAck = {
      type: 'discover_ack',
      app: 'insightkey_clipboard',
      deviceId: clipboardSyncId(this.sharedDir),
      deviceName: deviceInfo.marketName || deviceInfo.productModel,
      httpPort: HTTP_PORT,
      udpPort: UDP_PORT,
      platform: 'harmony',
      timestamp: started,
    }
    try {
      const udp = socket.constructUDPSocketInstance()
      await udp.bind({ address: '0.0.0.0', port: 0, family: 1 })
      await udp.setExtraOptions({ broadcast: true })
      this.udp = udp
    } catch (e) {
      this.status = `无法广播：${JSON.stringify(e)}`
      return
    }
    this.pairing = true
    this.status = '正在广播本机，请在电脑端的剪贴板同步程序中选择这台手机。'
    this.timer = setInterval(() => {
      const accessed = Number.parseInt(readText(clipboardSyncAccessPath(this.sharedDir)) ?? '0')
      if (accessed >= started) {
        this.stopPairing()
        this.status = '电脑已连接。'
        return
      }
      if (Date.now() - started > PAIRING_TIME) {
        this.stopPairing()
        this.status = '配对超时。请确认键盘弹出过一次，手机和电脑在同一网络。'
        return
      }
      ack.timestamp = Date.now()
      this.udp?.send({ data: JSON.stringify(ack), address: { address: '255.255.255.255', port: UDP_PORT, family: 1 } })
        .catch((e: Error) => console.error(`Broadcast failed: ${e.message}`))
    }, 1000)
  }

  private stopPairing() {
    if (this.timer >= 0) {
      clearInterval(this.timer)
      this.timer = -1
    }
    this.udp?.close()
    this.udp = null
    this.pairing = false
  }

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        Text('与同一局域网内运行剪贴板同步程序的电脑交换剪贴板内容，协议与 Fcitx5 安卓版（InsightKey）相同。' +
          '开启后，键盘会在局域网内提供剪贴板历史，请只在可信的网络中使用。')
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
        Row() {
          Text('剪贴板同步').fontSize(16).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.settings.clipboardSync })
            .onChange((isOn: boolean) => this.setEnabled(isOn))
        }
        .width('100%')
        if (this.settings.clipboardSync) {
          Text(this.address ? `本机地址：${this.address}:${HTTP_PORT}` : '未连接局域网')
            .fontSize(15)
            .width('100%')
          Text('开启后弹出一次键盘即开始服务。')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
          Button(this.pairing ? '停止配对' : '开始配对').width('100%').onClick(() => {
            if (this.pairing) {
              this.stopPairing()
              this.status = ''
            } else {
              this.startPairing()
            }
          })
        }
        if (this.status) {
          Text(this.status).fontSize(14).width('100%')
        }
      }
      .padding(16)
      .width('100%')
    }
    .title('剪贴板同步')
  }
}
