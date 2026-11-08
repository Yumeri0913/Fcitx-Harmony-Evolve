// Pinyin dictionaries like fcitx5-android's PinyinDictionaryFragment: import .dict, libime
// .txt and Sogou .scel files, enable, disable and delete them, and clear learned words.
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';
import fcitx from 'libentry.so';
import { ensureDir, exists, fileName, listFiles, readBytes, writeBytes } from '../../common/Files';
import { pendingPinyinActionsPath, readText, sharedDataPath, writeText } from '../../common/Settings';
import { scelToText } from '../../common/SougouScel';

interface DictItem {
  file: string
  enabled: boolean
}

@Component
export struct PinyinDictPage {
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext
  private sharedDir: string = this.context.distributedFilesDir
  private dir: string = sharedDataPath(this.sharedDir, 'pinyin/dictionaries')
  @State dicts: DictItem[] = []
  @State status: string = ''

  aboutToAppear() {
    this.load()
  }

  private load() {
    const files = listFiles(this.dir)
    this.dicts = files.filter((f: string) => f.endsWith('.dict')).sort().map((f: string): DictItem => ({
      file: f,
      enabled: !files.includes(`${f}.disable`),
    }))
  }

  private setEnabled(item: DictItem, enabled: boolean) {
    const marker = `${this.dir}/${item.file}.disable`
    try {
      if (enabled) {
        if (exists(marker)) {
          fs.unlinkSync(marker)
        }
      } else {
        writeText(marker, '')
      }
    } catch (e) {
      this.status = `修改失败：${e}`
    }
    this.load()
  }

  private remove(item: DictItem) {
    for (const path of [`${this.dir}/${item.file}`, `${this.dir}/${item.file}.disable`]) {
      try {
        if (exists(path)) {
          fs.unlinkSync(path)
        }
      } catch (e) {
        this.status = `删除失败：${e}`
      }
    }
    this.load()
  }

  private async importDict() {
    try {
      const documentPicker = new picker.DocumentViewPicker(this.context)
      const uris = await documentPicker.select({ maxSelectNumber: 1, fileSuffixFilters: ['.dict', '.txt', '.scel'] })
      if (uris.length === 0) {
        return
      }
      const name = fileName(uris[0])
      const base = name.replace(/\.(dict|txt|scel)$/i, '')
      const bytes = readBytes(uris[0])
      ensureDir(this.dir)
      const dest = `${this.dir}/${base}.dict`
      const lower = name.toLowerCase()
      if (lower.endsWith('.dict')) {
        writeBytes(dest, bytes)
        this.status = `已导入 ${base}.dict。`
      } else {
        // Text first, then libime converts it to its binary format.
        const tmpDir = `${this.context.filesDir}/tmp`
        ensureDir(tmpDir)
        const tmp = `${tmpDir}/import.txt`
        let words = 0
        if (lower.endsWith('.scel')) {
          const result = scelToText(bytes)
          writeText(tmp, result.text)
          words = result.words
        } else {
          writeBytes(tmp, bytes)
        }
        if (!fcitx.convertPinyinDict(tmp, dest, true)) {
          this.status = '转换失败：文本词库每行应为“词 拼音 0”，拼音用 \' 分隔，例如 你好 ni\'hao 0。'
          return
        }
        this.status = words > 0 ? `已从 ${name} 导入 ${words} 个词。` : `已导入 ${base}.dict。`
      }
      this.status += '下次弹出键盘时生效。'
    } catch (e) {
      this.status = `导入失败：${e}`
    }
    this.load()
  }

  private queueAction(action: string, message: string) {
    promptAction.showDialog({
      message: message,
      buttons: [{ text: '取消', color: '#888888' }, { text: '清除', color: '#E84026' }],
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index !== 1) {
        return
      }
      const path = pendingPinyinActionsPath(this.sharedDir)
      let actions: string[] = []
      try {
        actions = JSON.parse(readText(path) ?? '[]') as string[]
      } catch (e) {
        actions = []
      }
      actions.push(action)
      writeText(path, JSON.stringify(actions))
      this.status = '已安排，下次弹出键盘时清除。'
    })
  }

  build() {
    NavDestination() {
      List() {
        ListItem() {
          Text('内置词库总是启用。导入的词库放在这里，可以单独停用。支持 libime 的 .dict 和 .txt、搜狗 .scel。')
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
            .padding(16)
        }
        ForEach(this.dicts, (item: DictItem) => {
          ListItem() {
            Row({ space: 8 }) {
              Text(item.file.replace(/\.dict$/, '')).fontSize(16).layoutWeight(1)
              Button('删除').fontSize(14).height(32).backgroundColor($r('sys.color.comp_background_tertiary'))
                .fontColor($r('sys.color.font_primary'))
                .onClick(() => this.remove(item))
              Toggle({ type: ToggleType.Switch, isOn: item.enabled })
                .onChange((isOn: boolean) => this.setEnabled(item, isOn))
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          }
        }, (item: DictItem) => `${item.file}-${item.enabled}`)
        ListItem() {
          Column({ space: 12 }) {
            Button('导入词库').width('100%').onClick(() => {
              this.importDict()
            })
            Row({ space: 12 }) {
              Button('清除学习的词').layoutWeight(1).backgroundColor($r('sys.color.comp_background_tertiary'))
                .fontColor($r('sys.color.font_primary'))
                .onClick(() => this.queueAction('clearuserdict', '清除拼音学到的词（包括导入的谷歌拼音词）？使用记录保留。'))
              Button('清除全部').layoutWeight(1).backgroundColor($r('sys.color.comp_background_tertiary'))
                .fontColor($r('sys.color.font_primary'))
                .onClick(() => this.queueAction('clearalldict', '清除拼音学到的词和使用记录（包括导入的谷歌拼音词）？'))
            }
            if (this.status) {
              Text(this.status).fontSize(14).width('100%')
            }
          }
          .padding(16)
        }
      }
      .height('100%')
    }
    .title('拼音词库')
  }
}
