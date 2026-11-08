import { webview } from '@kit.ArkWeb'
import { pasteboard } from '@kit.BasicServicesKit'
import keyboardController from '../model/KeyboardController'
import { VirtualKeyboardEvent } from '../../../fcitx5-keyboard-web/src/api'
import BuildProfile from 'BuildProfile'

webview.once("webInited", () => {
  console.log("webInited")
})
if (BuildProfile.DEBUG) {
  webview.WebviewController.setWebDebuggingAccess(true)
}

@Entry
@Component
struct Index {
  controller: webview.WebviewController = new webview.WebviewController()
  port: webview.WebMessagePort | null = null
  @State webReady: boolean = false
  // Over the clipboard panel's title bar.
  @StorageLink('clipboardPasteVisible') pasteVisible: boolean = false

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Flex().backgroundColor($r('app.color.keyboard_background')).width('100%').height('100%')
        .zIndex(99999).visibility(this.webReady ? Visibility.Hidden : Visibility.Visible)
      Web({ src: $rawfile('index.html'), controller: this.controller }).onConsole((event) => {
        console.info(`keyboard-web: ${event.message.getMessage()}`)
        return false
      }).onPageEnd(() => {
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
            .width(84)
            .height(32)
            .fontSize(14)
            .backgroundColor('#4db6ac')
            .fontColor(Color.White)
            .iconColor(Color.White)
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
        .width('100%')
        .justifyContent(FlexAlign.End)
        // Only the button takes touches; the rest of the bar is the web keyboard's.
        .hitTestBehavior(HitTestMode.Transparent)
        // In the clipboard title bar, left of its delete all button.
        .padding({ right: 49, top: 4 })
      }
    }
  }
}
