// Enabled input methods like fcitx5-android's InputMethodListFragment: reorder, remove,
// add from the available ones, and configure.
import fcitx from 'libentry.so';
import { ConfigPageParam } from './ConfigPage';

interface InputMethodInfo {
  uniqueName: string
  name: string
  nativeName: string
  languageCode: string
  label: string
  addon: string
  configurable: boolean
}

function displayName(im: InputMethodInfo): string {
  return im.nativeName || im.name || im.uniqueName
}

@Component
export struct InputMethodsPage {
  @Consume('settingsStack') stack: NavPathStack
  @State enabledNames: string[] = []
  @State adding: boolean = false
  private available: Map<string, InputMethodInfo> = new Map()

  aboutToAppear() {
    for (const im of JSON.parse(fcitx.availableInputMethods()) as InputMethodInfo[]) {
      this.available.set(im.uniqueName, im)
    }
    this.enabledNames = JSON.parse(fcitx.enabledInputMethods()) as string[]
  }

  private save(names: string[]) {
    fcitx.setEnabledInputMethods(JSON.stringify(names))
    this.enabledNames = names
  }

  private move(index: number, offset: number) {
    const names = this.enabledNames.slice()
    const target = index + offset
    if (target < 0 || target >= names.length) {
      return
    }
    const name = names[index]
    names[index] = names[target]
    names[target] = name
    this.save(names)
  }

  // Chinese input methods first, then the keyboard layouts.
  private candidates(): InputMethodInfo[] {
    const result: InputMethodInfo[] = []
    this.available.forEach((im: InputMethodInfo) => {
      if (!this.enabledNames.includes(im.uniqueName)) {
        result.push(im)
      }
    })
    return result.sort((a: InputMethodInfo, b: InputMethodInfo) => {
      const ak = a.uniqueName.startsWith('keyboard-') ? 1 : 0
      const bk = b.uniqueName.startsWith('keyboard-') ? 1 : 0
      return ak !== bk ? ak - bk : displayName(a).localeCompare(displayName(b))
    })
  }

  @Builder
  enabledList() {
    List() {
      ListItem() {
        Text('地球键和中/英键在第一个输入法和当前输入法之间切换；长按空格可选择任意已启用的输入法。')
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .padding(16)
      }
      ForEach(this.enabledNames, (name: string, index: number) => {
        ListItem() {
          Row({ space: 8 }) {
            Column() {
              Text(this.available.has(name) ? displayName(this.available.get(name)!) : name).fontSize(16)
              Text(name).fontSize(13).fontColor($r('sys.color.font_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .onClick(() => {
              const im = this.available.get(name)
              if (im && im.configurable) {
                this.stack.pushPathByName('config', { uri: `im/${name}`, title: displayName(im) } as ConfigPageParam)
              }
            })
            Button('↑').type(ButtonType.Circle).width(36).height(36).enabled(index > 0)
              .onClick(() => this.move(index, -1))
            Button('↓').type(ButtonType.Circle).width(36).height(36).enabled(index < this.enabledNames.length - 1)
              .onClick(() => this.move(index, 1))
            Button('×').type(ButtonType.Circle).width(36).height(36).enabled(this.enabledNames.length > 1)
              .onClick(() => this.save(this.enabledNames.filter((n: string) => n !== name)))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        }
      }, (name: string, index: number) => `${name}-${index}`)
      ListItem() {
        Button('添加输入法').width('90%').margin(16).onClick(() => {
          this.adding = true
        })
      }
    }
    .height('100%')
  }

  @Builder
  addList() {
    List() {
      ForEach(this.candidates(), (im: InputMethodInfo) => {
        ListItem() {
          Column() {
            Text(displayName(im)).fontSize(16)
            Text(im.uniqueName).fontSize(13).fontColor($r('sys.color.font_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .onClick(() => {
            this.save(this.enabledNames.concat([im.uniqueName]))
            this.adding = false
          })
        }
      }, (im: InputMethodInfo) => im.uniqueName)
    }
    .height('100%')
  }

  build() {
    NavDestination() {
      if (this.adding) {
        this.addList()
      } else {
        this.enabledList()
      }
    }
    .title(this.adding ? '添加输入法' : '输入法')
    .onBackPressed(() => {
      if (this.adding) {
        this.adding = false
        return true
      }
      return false
    })
  }
}
