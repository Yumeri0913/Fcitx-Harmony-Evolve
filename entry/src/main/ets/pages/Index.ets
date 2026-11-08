import { common } from '@kit.AbilityKit';
import { fcitxLocale } from '../common/Locale';
import fcitx from 'libentry.so';
import { AddonsPage } from './settings/AddonsPage';
import { ConfigPage, ConfigPageParam } from './settings/ConfigPage';
import { InputMethodsPage } from './settings/InputMethodsPage';
import { BackupPage } from './settings/BackupPage';
import { ClipboardSyncPage } from './settings/ClipboardSyncPage';
import { KeyboardPage } from './settings/KeyboardPage';
import { PinyinDictPage } from './settings/PinyinDictPage';
import { QuickSettingsPage } from './settings/QuickSettingsPage';
import { UserDictPage } from './settings/UserDictPage';
import { QuickPhrasePage } from './settings/QuickPhrasePage';
import { TextFilePage, TextFilePageParam, textFileParam } from './settings/TextFilePage';

@Entry
@Component
struct Index {
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext
  // Shared with the input method, see Settings.ets.
  private filesDir: string = this.context.distributedFilesDir
  @Provide('settingsStack') stack: NavPathStack = new NavPathStack()
  // A page asked for by the keyboard, see EntryAbility.
  @StorageLink('openPage') @Watch('onOpenPage') openPage: string = ''
  @StorageLink('openInputMethod') openInputMethod: string = ''

  aboutToAppear() {
    // A fcitx of its own for config descriptions; config files are shared with the keyboard.
    fcitx.initSettings(this.context.bundleCodeDir, this.context.resourceDir, this.context.filesDir,
      this.context.distributedFilesDir, fcitxLocale())
    this.onOpenPage()
  }

  onOpenPage() {
    const page = this.openPage
    if (page === '-') {
      return
    }
    // '' is the main page.
    this.stack.clear(false)
    if (page === 'keyboard') {
      this.stack.pushPathByName('keyboard', null, false)
    } else if (page === 'inputMethod' && this.openInputMethod) {
      const title = this.openInputMethod === 'pinyin' ? '拼音' : this.openInputMethod
      this.stack.pushPathByName('config', { uri: `im/${this.openInputMethod}`, title: title } as ConfigPageParam, false)
    }
    this.openPage = '-'
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
    } else if (name === 'userDict') {
      UserDictPage()
    } else if (name === 'quickSettings') {
      QuickSettingsPage()
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

        this.sectionTitle('快捷设置')
        this.linkRow('谷歌拼音风格设置', '按谷歌拼音 4.x 设置的顺序和措辞', (): void => this.open('quickSettings'))

        this.sectionTitle('输入')
        this.linkRow('输入法', '启用、排序和设置输入法', (): void => this.open('inputMethods'))
        this.linkRow('拼音', '联想、模糊音、英文候选等', (): void => this.open('config', { uri: 'im/pinyin', title: '拼音' }))
        this.linkRow('全局选项', '快捷键、行为', (): void => this.open('config', { uri: 'global', title: '全局选项' }))
        this.linkRow('附加组件', '标点、快速输入、云拼音等', (): void => this.open('addons'))

        this.sectionTitle('词库')
        this.linkRow('谷歌拼音用户词库', '导入或导出谷歌拼音的用户字典', (): void => this.open('userDict'))
        this.linkRow('拼音词库', '导入搜狗、libime 词库，清除学到的词', (): void => this.open('pinyinDict'))
        this.linkRow('自定义短语', '用缩写输入固定内容', (): void => this.openTextFile('customPhrase'))
        this.linkRow('快速输入', '长按逗号键使用的短语列表', (): void => this.open('quickPhrase'))
        this.linkRow('标点', '中文标点映射', (): void => this.openTextFile('punctuation'))

        this.sectionTitle('键盘')
        this.linkRow('主题与键盘', '主题、高度、按键间距、振动、按键音', (): void => this.open('keyboard'))
        this.linkRow('剪贴板同步', '与局域网内的电脑同步剪贴板', (): void => this.open('clipboardSync'))
        this.linkRow('备份与恢复', '导出设置和词库，或恢复安卓版的备份', (): void => this.open('backup'))

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
