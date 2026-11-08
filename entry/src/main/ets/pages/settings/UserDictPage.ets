// Google Pinyin user dictionary import and export: user-dictionary.txt is merged into the
// pinyin engine's learned words by the input method, like fcitx5-android (InsightKey fork).
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { readBytes, writeBytes } from '../../common/Files';
import {
  decode, DEFAULT_FILE_NAME, fromTsv, parse, toGooglePinyinBytes, toTsv
} from '../../common/GooglePinyinUserDict';
import {
  ImportResult, importResultPath, pendingImportPath, pendingSkippedPath, fileMtime, readText,
  userWordsSnapshotPath, writeText
} from '../../common/Settings';

@Component
export struct UserDictPage {
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext
  // Shared with the input method, see Settings.ets.
  private filesDir: string = this.context.distributedFilesDir
  @State dictStatus: string = ''

  aboutToAppear() {
    this.updateDictStatus()
  }

  private updateDictStatus() {
    if (readText(pendingImportPath(this.filesDir)) !== null) {
      this.dictStatus = '等待导入：下次弹出键盘时合并进拼音用户词库。'
      return
    }
    const text = readText(importResultPath(this.filesDir))
    if (text !== null) {
      const result = JSON.parse(text) as ImportResult
      const time = new Date(result.time).toLocaleString()
      this.dictStatus = `上次导入（${time}）：新增 ${result.added} 个词，已有 ${result.existing} 个，` +
        `跳过 ${result.skipped + result.invalid} 行（英文词或无效拼音）。`
    }
  }

  private async importGooglePinyin() {
    try {
      const documentPicker = new picker.DocumentViewPicker(this.context)
      const uris = await documentPicker.select({ maxSelectNumber: 1, fileSuffixFilters: ['.txt'] })
      if (uris.length === 0) {
        return
      }
      const result = parse(decode(readBytes(uris[0])))
      if (result.entries.length === 0) {
        this.dictStatus = `没有可导入的词，跳过 ${result.skipped} 行。请选择谷歌拼音导出的 ${DEFAULT_FILE_NAME}。`
        return
      }
      // The pinyin engine runs in the input method process, which merges the words.
      writeText(pendingImportPath(this.filesDir), toTsv(result.entries))
      writeText(pendingSkippedPath(this.filesDir), `${result.skipped}`)
      this.dictStatus = `已读取 ${result.entries.length} 个词，跳过 ${result.skipped} 行。` +
        '下次弹出键盘时合并进拼音用户词库。'
    } catch (e) {
      this.dictStatus = `导入失败：${e}`
    }
  }

  private async exportGooglePinyin() {
    try {
      // The input method leaves its user words here when the keyboard hides.
      const snapshot = userWordsSnapshotPath(this.filesDir)
      const tsv = readText(snapshot)
      if (tsv === null) {
        this.dictStatus = '还没有可导出的词。请先用 Fcitx5 打一次字并收起键盘，再回来导出。'
        return
      }
      const entries = fromTsv(tsv)
      if (entries.length === 0) {
        this.dictStatus = '拼音用户词库是空的。'
        return
      }
      const time = new Date(fileMtime(snapshot) * 1000).toLocaleString()
      const documentPicker = new picker.DocumentViewPicker(this.context)
      const uris = await documentPicker.save({ newFileNames: [DEFAULT_FILE_NAME] })
      if (uris.length === 0) {
        return
      }
      writeBytes(uris[0], toGooglePinyinBytes(entries))
      this.dictStatus = `已导出 ${entries.length} 个词（截至 ${time} 收起键盘时），可在谷歌拼音的“导入用户字典”中使用。`
    } catch (e) {
      this.dictStatus = `导出失败：${e}`
    }
  }

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        Text('在谷歌拼音中导出用户字典（user-dictionary.txt），再在这里导入。' +
          '导入的词与 Fcitx5 学到的词放在一起，会随日常输入继续调整顺序。导出的文件可以导入谷歌拼音。')
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
        Row({ space: 12 }) {
          Button('导入').layoutWeight(1).onClick(() => {
            this.importGooglePinyin()
          })
          Button('导出').layoutWeight(1).onClick(() => {
            this.exportGooglePinyin()
          })
        }
        .width('100%')
        if (this.dictStatus) {
          Text(this.dictStatus)
            .fontSize(14)
            .width('100%')
        }
      }
      .padding(16)
      .width('100%')
    }
    .title('谷歌拼音用户词库')
  }
}
