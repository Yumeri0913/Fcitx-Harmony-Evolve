// Quick phrase lists like fcitx5-android's QuickPhraseListFragment: bundled and user .mb
// files, enable or disable each, edit, and add new ones.
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { exists, listFiles } from '../../common/Files';
import { sharedDataPath, writeText } from '../../common/Settings';
import { TextFilePageParam } from './TextFilePage';

const DIR = 'data/quickphrase.d'
const HINT = '每行一条：“缩写 内容”，例如 “dz 北京市海淀区”。在快速输入模式下输入缩写即可选择内容。'

interface QuickPhraseItem {
  name: string
  enabled: boolean
}

@Component
export struct QuickPhrasePage {
  @Consume('settingsStack') stack: NavPathStack
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext
  private userDir: string = sharedDataPath(this.context.distributedFilesDir, DIR)
  private bundledDir: string = `${this.context.resourceDir}/usr/share/fcitx5/${DIR}`
  @State items: QuickPhraseItem[] = []
  @State newName: string = ''

  aboutToAppear() {
    this.load()
  }

  private load() {
    const user = listFiles(this.userDir)
    const names = new Set<string>()
    for (const f of listFiles(this.bundledDir).concat(user)) {
      if (f.endsWith('.mb')) {
        names.add(f.substring(0, f.length - 3))
      }
    }
    this.items = Array.from(names).sort().map((name: string): QuickPhraseItem => ({
      name: name,
      enabled: !user.includes(`${name}.mb.disable`),
    }))
  }

  private setEnabled(item: QuickPhraseItem, enabled: boolean) {
    const marker = `${this.userDir}/${item.name}.mb.disable`
    try {
      if (enabled) {
        if (exists(marker)) {
          fs.unlinkSync(marker)
        }
      } else {
        writeText(marker, '')
      }
    } catch (e) {
      console.error(`Failed to change ${item.name}: ${e}`)
    }
    this.load()
  }

  private edit(name: string) {
    this.stack.pushPathByName('textFile', {
      title: name,
      relative: `${DIR}/${name}.mb`,
      hint: HINT,
    } as TextFilePageParam)
  }

  build() {
    NavDestination() {
      List() {
        ListItem() {
          Text('长按逗号键选“快速输入”使用。停用的列表不会出现在候选中。')
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
            .padding(16)
        }
        ForEach(this.items, (item: QuickPhraseItem) => {
          ListItem() {
            Row({ space: 8 }) {
              Text(item.name).fontSize(16).layoutWeight(1).onClick(() => this.edit(item.name))
              Text('›').fontSize(22).fontColor($r('sys.color.font_secondary')).onClick(() => this.edit(item.name))
              Toggle({ type: ToggleType.Switch, isOn: item.enabled })
                .onChange((isOn: boolean) => this.setEnabled(item, isOn))
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          }
        }, (item: QuickPhraseItem) => `${item.name}-${item.enabled}`)
        ListItem() {
          Row({ space: 12 }) {
            TextInput({ placeholder: '新列表名称', text: this.newName })
              .layoutWeight(1)
              .onChange((value: string) => {
                this.newName = value
              })
            Button('新建').onClick(() => {
              const name = this.newName.trim().replace(/[\/\\]/g, '')
              if (name) {
                this.newName = ''
                this.edit(name)
              }
            })
          }
          .padding(16)
        }
      }
      .height('100%')
    }
    .title('快速输入')
    .onShown(() => this.load())
  }
}
