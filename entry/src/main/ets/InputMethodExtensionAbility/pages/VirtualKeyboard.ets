import { webview } from '@kit.ArkWeb'
import { pasteboard } from '@kit.BasicServicesKit'
import keyboardController from '../model/KeyboardController'
import { VirtualKeyboardEvent } from '../../../fcitx5-keyboard-web/src/api'

webview.once("webInited", () => {
  console.log("webInited")
})

@Entry
@Component
struct Index {
  controller: webview.WebviewController = new webview.WebviewController()
  port: webview.WebMessagePort | null = null
  @State webReady: boolean = false
  // Over the clipboard panel's header, below the 40 vp toolbar.
  @StorageLink('clipboardPasteVisible') pasteVisible: boolean = false

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Flex().backgroundColor($r('app.color.keyboard_background')).width('100%').height('100%')
        .zIndex(99999).visibility(this.webReady ? Visibility.Hidden : Visibility.Visible)
      Web({ src: $rawfile('index.html'), controller: this.controller }).onPageEnd(() => {
        const ports = this.controller.createWebMessagePorts()
        this.port = ports[1]
        this.port.onMessageEvent(msg => {
          const event = JSON.parse(msg as string) as VirtualKeyboardEvent
          keyboardController.handleVirtualKeyboardEvent(event)
        })
        this.controller.postMessage('__init_port__', [ports[0]], '*')
        keyboardController.setPort(this.port)
        // Needed because webview isn't available on first focus in.
        keyboardController.setEnterKeyType()
        this.webReady = true
      })
      // HarmonyOS lets the keyboard read the system clipboard only through this button.
      if (this.pasteVisible) {
        Row() {
          PasteButton({ icon: PasteIconStyle.LINES, text: PasteDescription.PASTE, buttonType: ButtonType.Capsule })
            .height(32)
            .onClick((event: ClickEvent, result: PasteButtonOnClickResult) => {
              if (result !== PasteButtonOnClickResult.SUCCESS) {
                return
              }
              try {
                const data = pasteboard.getSystemPasteboard().getDataSync()
                keyboardController.pasteFromSystem(data.getPrimaryText() ?? '')
              } catch (e) {
                console.error(`Failed to read clipboard: ${e}`)
              }
            })
        }
        .padding({ left: 8, top: 44 })
      }
    }
  }
}
