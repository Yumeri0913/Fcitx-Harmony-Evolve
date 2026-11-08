import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { readBytes, writeBytes } from '../common/Files';
import {
  decode, DEFAULT_FILE_NAME, fromTsv, parse, toGooglePinyinBytes, toTsv
} from '../common/GooglePinyinUserDict';
import {
  ImportResult, importResultPath, pendingImportPath, pendingSkippedPath, fileMtime, readText,
  userWordsSnapshotPath, writeText
} from '../common/Settings';
import { fcitxLocale } from '../common/Locale';
import fcitx from 'libentry.so';
import { AddonsPage } from './settings/AddonsPage';
import { ConfigPage, ConfigPageParam } from './settings/ConfigPage';
import { InputMethodsPage } from './settings/InputMethodsPage';
import { BackupPage } from './settings/BackupPage';
import { ClipboardSyncPage } from './settings/ClipboardSyncPage';
import { KeyboardPage } from './settings/KeyboardPage';
import { PinyinDictPage } from './settings/PinyinDictPage';
import { QuickPhrasePage } from './settings/QuickPhrasePage';
import { TextFilePage, TextFilePageParam, textFileParam } from './settings/TextFilePage';

@Entry
@Component
struct Index {
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext
  // Shared with the input method, see Settings.ets.
  private filesDir: string = this.context.distributedFilesDir
  @Provide('settingsStack') stack: NavPathStack = new NavPathStack()
  @State dictStatus: string = ''

  aboutToAppear() {
    // A fcitx of its own for config descriptions; config files are shared with the keyboard.
    fcitx.initSettings(this.context.bundleCodeDir, this.context.resourceDir, this.context.filesDir,
      this.context.distributedFilesDir, fcitxLocale())
  }

  onPageShow() {
    this.updateDictStatus()
  }

  private open(name: string, param?: ConfigPageParam) {
    this.stack.pushPathByName(name, param ?? null)
  }

  private openTextFile(kind: string) {
    this.stack.pushPathByName('textFile', textFileParam(kind))
  }

  @Builder
  pageMap(name: string, param: Object) {
    if (name === 'config') {
      ConfigPage({ param: param as ConfigPageParam })
    } else if (name === 'addons') {
      AddonsPage()
    } else if (name === 'inputMethods') {
      InputMethodsPage()
    } else if (name === 'keyboard') {
      KeyboardPage()
    } else if (name === 'pinyinDict') {
      PinyinDictPage()
    } else if (name === 'quickPhrase') {
      QuickPhrasePage()
    } else if (name === 'textFile') {
      TextFilePage({ param: param as TextFilePageParam })
    } else if (name === 'backup') {
      BackupPage()
    } else if (name === 'clipboardSync') {
      ClipboardSyncPage()
    }
  }

  @Builder
  linkRow(label: string, detail: string, onClick: () => void) {
    Row() {
      Column() {
        Text(label).fontSize(16)
        if (detail) {
          Text(detail).fontSize(13).fontColor($r('sys.color.font_secondary'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›').fontSize(22).fontColor($r('sys.color.font_secondary'))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(onClick)
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

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(14)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
      .padding({ left: 16, top: 16, bottom: 8 })
  }

  build() {
    Navigation(this.stack) {
    Scroll() {
      Column() {
        Text('Fcitx5')
          .fontSize(24)
          .fontWeight(700)
          .width('100%')
          .padding({ left: 16, top: 24 })
        Text('在“设置 › 系统 › 输入法”中启用并切换到 Fcitx5。')
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 8 })

        this.sectionTitle('输入')
        this.linkRow('输入法', '启用、排序和设置输入法', (): void => this.open('inputMethods'))
        this.linkRow('拼音', '联想、模糊音、英文候选等', (): void => this.open('config', { uri: 'im/pinyin', title: '拼音' }))
        this.linkRow('全局选项', '快捷键、行为', (): void => this.open('config', { uri: 'global', title: '全局选项' }))
        this.linkRow('附加组件', '标点、快速输入、云拼音等', (): void => this.open('addons'))

        this.sectionTitle('词库')
        this.linkRow('拼音词库', '导入搜狗、libime 词库，清除学到的词', (): void => this.open('pinyinDict'))
        this.linkRow('自定义短语', '用缩写输入固定内容', (): void => this.openTextFile('customPhrase'))
        this.linkRow('快速输入', '长按逗号键使用的短语列表', (): void => this.open('quickPhrase'))
        this.linkRow('标点', '中文标点映射', (): void => this.openTextFile('punctuation'))

        this.sectionTitle('键盘')
        this.linkRow('主题与键盘', '主题、高度、按键间距、振动、按键音', (): void => this.open('keyboard'))
        this.linkRow('剪贴板同步', '与局域网内的电脑同步剪贴板', (): void => this.open('clipboardSync'))
        this.linkRow('备份与恢复', '导出设置和词库，或恢复安卓版的备份', (): void => this.open('backup'))

        this.sectionTitle('谷歌拼音用户词库')
        Text('在谷歌拼音中导出用户字典（user-dictionary.txt），再在这里导入。' +
          '导入的词与 Fcitx5 学到的词放在一起，会随日常输入继续调整顺序。')
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding({ left: 16, right: 16 })
        Row({ space: 12 }) {
          Button('导入').layoutWeight(1).onClick(() => {
            this.importGooglePinyin()
          })
          Button('导出').layoutWeight(1).onClick(() => {
            this.exportGooglePinyin()
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12 })
        if (this.dictStatus) {
          Text(this.dictStatus)
            .fontSize(14)
            .width('100%')
            .padding({ left: 16, right: 16, top: 12 })
        }
      }
      .width('100%')
      .padding({ bottom: 32 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    }
    .navDestination(this.pageMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .backgroundColor($r('sys.color.background_primary'))
  }
}
