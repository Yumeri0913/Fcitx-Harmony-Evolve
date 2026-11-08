// Addon list like fcitx5-android's AddonListFragment: enable or disable, and configure.
import fcitx from 'libentry.so';
import { ConfigPageParam } from './ConfigPage';

interface AddonInfo {
  uniqueName: string
  name: string
  comment: string
  category: number
  configurable: boolean
  defaultEnabled: boolean
  onDemand: boolean
  enabled: boolean
}

// fcitx::AddonCategory
const CATEGORY_NAMES: string[] = ['输入法', '前端', '加载器', '模块', '用户界面']

@Component
export struct AddonsPage {
  @Consume('settingsStack') stack: NavPathStack
  @State addons: AddonInfo[] = []
  @State changed: boolean = false

  aboutToAppear() {
    this.load()
  }

  private load() {
    this.addons = JSON.parse(fcitx.getAddons()) as AddonInfo[]
  }

  build() {
    NavDestination() {
      List() {
        if (this.changed) {
          ListItem() {
            Text('启用或停用附加组件需要重启输入法才生效：切换到其他输入法再切回来。')
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
              .padding(16)
          }
        }
        ForEach(this.addons, (addon: AddonInfo) => {
          ListItem() {
            Row({ space: 12 }) {
              Column() {
                Text(addon.name || addon.uniqueName).fontSize(16)
                Text(`${CATEGORY_NAMES[addon.category] ?? ''}${addon.comment ? ' · ' + addon.comment : ''}`)
                  .fontSize(13)
                  .fontColor($r('sys.color.font_secondary'))
                  .maxLines(2)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .onClick(() => {
                if (addon.configurable) {
                  this.stack.pushPathByName('config', {
                    uri: `addon/${addon.uniqueName}`,
                    title: addon.name || addon.uniqueName,
                  } as ConfigPageParam)
                }
              })
              if (addon.configurable) {
                Text('›').fontSize(22).fontColor($r('sys.color.font_secondary'))
              }
              Toggle({ type: ToggleType.Switch, isOn: addon.enabled })
                .onChange((isOn: boolean) => {
                  fcitx.setAddonState(addon.uniqueName, isOn)
                  this.changed = true
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          }
        }, (addon: AddonInfo) => addon.uniqueName)
      }
      .height('100%')
    }
    .title('附加组件')
  }
}
