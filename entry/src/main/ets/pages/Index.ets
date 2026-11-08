import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import {
  decode, DEFAULT_FILE_NAME, fromTsv, parse, toGooglePinyinBytes, toTsv
} from '../common/GooglePinyinUserDict';
import {
  ImportResult, KeyboardSettings, loadSettings, importResultPath, pendingImportPath, pendingSkippedPath,
  fileMtime, readText, saveSettings, ThemeMode, userWordsSnapshotPath, VibrationStrength, writeText
} from '../common/Settings';
import { fcitxLocale } from '../common/Locale';
import fcitx from 'libentry.so';
import { AddonsPage } from './settings/AddonsPage';
import { ConfigPage, ConfigPageParam } from './settings/ConfigPage';
import { InputMethodsPage } from './settings/InputMethodsPage';

const THEMES: ThemeMode[] = ['system', 'light', 'dark']
const THEME_NAMES: string[] = ['跟随系统', '浅色', '深色']
const STRENGTHS: VibrationStrength[] = ['light', 'medium', 'heavy']
const STRENGTH_NAMES: string[] = ['轻', '中', '强']

function readBytes(uri: string): Uint8Array {
  const file = fs.openSync(uri, fs.OpenMode.READ_ONLY)
  try {
    const size = fs.statSync(file.fd).size
    const buffer = new ArrayBuffer(size)
    let offset = 0
    while (offset < size) {
      const n = fs.readSync(file.fd, buffer, { offset: offset, length: size - offset })
      if (n <= 0) {
        break
      }
      offset += n
    }
    return new Uint8Array(buffer, 0, offset)
  } finally {
    fs.closeSync(file)
  }
}

function writeBytes(uri: string, bytes: Uint8Array) {
  const file = fs.openSync(uri, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
  try {
    fs.writeSync(file.fd, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength))
  } finally {
    fs.closeSync(file)
  }
}

@Entry
@Component
struct Index {
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext
  // Shared with the input method, see Settings.ets.
  private filesDir: string = this.context.distributedFilesDir
  @Provide('settingsStack') stack: NavPathStack = new NavPathStack()
  @State settings: KeyboardSettings = loadSettings(this.filesDir)
  @State dictStatus: string = ''

  aboutToAppear() {
    // A fcitx of its own for config descriptions; config files are shared with the keyboard.
    fcitx.initSettings(this.context.bundleCodeDir, this.context.resourceDir, this.context.filesDir,
      this.context.distributedFilesDir, fcitxLocale())
  }

  onPageShow() {
    this.settings = loadSettings(this.filesDir)
    this.updateDictStatus()
  }

  private open(name: string, param?: ConfigPageParam) {
    this.stack.pushPathByName(name, param ?? null)
  }

  @Builder
  pageMap(name: string, param: Object) {
    if (name === 'config') {
      ConfigPage({ param: param as ConfigPageParam })
    } else if (name === 'addons') {
      AddonsPage()
    } else if (name === 'inputMethods') {
      InputMethodsPage()
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

  private save() {
    try {
      saveSettings(this.filesDir, this.settings)
    } catch (e) {
      console.error(`Failed to save settings: ${e}`)
    }
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

  @Builder
  toggleRow(label: string, isOn: boolean, onChange: (isOn: boolean) => void) {
    Row() {
      Text(label).fontSize(16).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .onChange(onChange)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
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

        this.sectionTitle('外观')
        Row() {
          Text('主题').fontSize(16).layoutWeight(1)
          Select(THEME_NAMES.map((name: string): SelectOption => ({ value: name })))
            .selected(THEMES.indexOf(this.settings.theme))
            .value(THEME_NAMES[THEMES.indexOf(this.settings.theme)])
            .onSelect((index: number) => {
              this.settings.theme = THEMES[index]
              this.save()
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        this.toggleRow('按键边框', this.settings.keyBorder, (isOn: boolean) => {
          this.settings.keyBorder = isOn
          this.save()
        })

        this.sectionTitle('按键')
        this.toggleRow('按键振动', this.settings.vibrate, (isOn: boolean) => {
          this.settings.vibrate = isOn
          this.save()
        })
        Row() {
          Text('振动强度').fontSize(16).layoutWeight(1)
          Select(STRENGTH_NAMES.map((name: string): SelectOption => ({ value: name })))
            .selected(STRENGTHS.indexOf(this.settings.vibrationStrength))
            .value(STRENGTH_NAMES[STRENGTHS.indexOf(this.settings.vibrationStrength)])
            .enabled(this.settings.vibrate)
            .onSelect((index: number) => {
              this.settings.vibrationStrength = STRENGTHS[index]
              this.save()
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })

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
