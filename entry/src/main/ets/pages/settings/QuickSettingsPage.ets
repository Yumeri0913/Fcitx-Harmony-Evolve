// Settings laid out like Google Pinyin 4.x (输入法 / 中文输入法 / 键盘 / 字典), mapped onto fcitx
// options and the keyboard's settings, like fcitx5-android's QuickSettingsFragment (InsightKey
// fork). Items of Google Pinyin without an fcitx counterpart are left out.
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import fcitx from 'libentry.so';
import { FcitxConfig, RawConfig } from '../../common/FcitxConfig';
import {
  KeyboardSettings, loadSettings, pendingPinyinActionsPath, readText, saveSettings, VibrationStrength, writeText
} from '../../common/Settings';
import { textFileParam } from './TextFilePage';

interface Choice {
  name: string
  value: string
}

interface FuzzyPair {
  title: string
  key: string
  // On when fuzzy pinyin gets turned on, like Google Pinyin.
  byDefault: boolean
}

interface InputMethodInfo {
  name: string
}

const QUANPIN = 'quanpin'

const SCHEMES: Choice[] = [
  { name: '全拼', value: QUANPIN },
  { name: '双拼 - 微软', value: 'MS' },
  { name: '双拼 - 紫光', value: 'Ziguang' },
  { name: '双拼 - 拼音加加', value: 'PinyinJiajia' },
  { name: '双拼 - 智能ABC', value: 'ABC' },
  { name: '双拼 - 自然码', value: 'Ziranma' },
  { name: '双拼 - 小鹤双拼', value: 'Xiaohe' },
]

const FUZZY_PAIRS: FuzzyPair[] = [
  { title: 'z = zh', key: 'Z_ZH', byDefault: true },
  { title: 'c = ch', key: 'C_CH', byDefault: true },
  { title: 's = sh', key: 'S_SH', byDefault: true },
  { title: 'l = n', key: 'L_N', byDefault: false },
  { title: 'f = h', key: 'F_H', byDefault: false },
  { title: 'r = l', key: 'L_R', byDefault: false },
  { title: 'an = ang', key: 'AN_ANG', byDefault: true },
  { title: 'en = eng', key: 'EN_ENG', byDefault: true },
  { title: 'in = ing', key: 'IN_ING', byDefault: true },
  { title: 'ian = iang', key: 'IAN_IANG', byDefault: false },
  { title: 'uan = uang', key: 'UAN_UANG', byDefault: false },
]

const HEIGHTS: Choice[] = [
  { name: '低', value: '90' },
  { name: '中等偏低', value: '95' },
  { name: '正常', value: '100' },
  { name: '中等偏高', value: '105' },
  { name: '高', value: '110' },
]

const SENSITIVITIES: Choice[] = [
  { name: '低', value: '3' },
  { name: '中等偏低', value: '1.5' },
  { name: '正常', value: '1' },
  { name: '中等偏高', value: '0.8' },
  { name: '高', value: '0.5' },
]

const STRENGTHS: VibrationStrength[] = ['light', 'medium', 'heavy']
const STRENGTH_NAMES: string[] = ['轻', '中', '强']

@Component
export struct QuickSettingsPage {
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext
  private sharedDir: string = this.context.distributedFilesDir
  @Consume('settingsStack') stack: NavPathStack
  @State settings: KeyboardSettings = loadSettings(this.sharedDir)
  // Bumped to rebuild after fcitx configs change.
  @State version: number = 0
  private pinyinCfg: RawConfig | null = null
  private chttransCfg: RawConfig | null = null
  private enabledIms: string[] = []
  private hasShuangpin: boolean = false

  aboutToAppear() {
    this.pinyinCfg = FcitxConfig.parse(fcitx.getConfig('im/pinyin'))?.cfg ?? null
    this.chttransCfg = FcitxConfig.parse(fcitx.getConfig('addon/chttrans'))?.cfg ?? null
    this.enabledIms = JSON.parse(fcitx.enabledInputMethods()) as string[]
    const available = JSON.parse(fcitx.availableInputMethods()) as InputMethodInfo[]
    this.hasShuangpin = available.some((im: InputMethodInfo) => im.name === 'shuangpin')
  }

  private saveSettings() {
    try {
      saveSettings(this.sharedDir, this.settings)
    } catch (e) {
      console.error(`Failed to save settings: ${e}`)
    }
  }

  private node(cfg: RawConfig | null, path: string): RawConfig | undefined {
    let node: RawConfig | undefined = cfg ?? undefined
    for (const name of path.split('/')) {
      node = node?.find(name)
    }
    return node
  }

  private pinyinBool(path: string): boolean {
    return this.node(this.pinyinCfg, path)?.value === 'True'
  }

  private setNode(cfg: RawConfig, path: string, value: string) {
    let node = cfg
    for (const name of path.split('/')) {
      node = node.getOrCreate(name)
    }
    node.value = value
  }

  private updatePinyin(change: (cfg: RawConfig) => void) {
    if (!this.pinyinCfg) {
      return
    }
    change(this.pinyinCfg)
    fcitx.setConfig('im/pinyin', JSON.stringify(this.pinyinCfg.toJson()))
    this.version++
  }

  private setEnabled(list: string[]) {
    this.enabledIms = list
    fcitx.setEnabledInputMethods(JSON.stringify(list))
    this.version++
  }

  private currentScheme(): string {
    if (this.enabledIms.includes('shuangpin')) {
      return this.node(this.pinyinCfg, 'ShuangpinProfile')?.value ?? 'Ziranma'
    }
    return QUANPIN
  }

  // The English keyboard stays first (the inactive input method), Chinese right after it.
  private applyScheme(scheme: string) {
    const chinese = scheme === QUANPIN ? 'pinyin' : 'shuangpin'
    const list = this.enabledIms.filter((im: string) => im !== 'pinyin' && im !== 'shuangpin')
    const english = list.indexOf('keyboard-us')
    list.splice(english >= 0 ? english + 1 : 0, 0, chinese)
    if (scheme !== QUANPIN) {
      this.updatePinyin((cfg: RawConfig): void => this.setNode(cfg, 'ShuangpinProfile', scheme))
    }
    this.setEnabled(list)
  }

  private traditional(): boolean {
    return (this.chttransCfg?.find('EnabledIM')?.listValues() ?? []).includes('pinyin')
  }

  private setTraditional(on: boolean) {
    if (!this.chttransCfg) {
      return
    }
    const ims = (this.chttransCfg.find('EnabledIM')?.listValues() ?? [])
      .filter((im: string) => im !== 'pinyin' && im !== 'shuangpin')
    if (on) {
      ims.push('pinyin', 'shuangpin')
    }
    this.chttransCfg.getOrCreate('EnabledIM').setListValues(ims)
    fcitx.setConfig('addon/chttrans', JSON.stringify(this.chttransCfg.toJson()))
    this.version++
  }

  private fuzzyEnabled(): boolean {
    return FUZZY_PAIRS.some((pair: FuzzyPair) => this.pinyinBool(`Fuzzy/${pair.key}`))
  }

  private clearUserDict() {
    promptAction.showDialog({
      title: '清除用户字典',
      message: '将删除输入时学到的全部词语和使用记录，此操作无法撤销。',
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
      actions.push('clearalldict')
      writeText(path, JSON.stringify(actions))
      promptAction.showToast({ message: '已安排，下次弹出键盘时清除。' })
    })
  }

  @Builder
  section(title: string) {
    Text(title)
      .fontSize(14)
      .fontColor($r('sys.color.font_emphasize'))
      .width('100%')
      .padding({ left: 16, top: 20, bottom: 4 })
  }

  @Builder
  toggleRow(title: string, summary: string, isOn: boolean, enabled: boolean, onChange: (isOn: boolean) => void) {
    Row() {
      Column() {
        Text(title).fontSize(16)
        if (summary) {
          Text(summary).fontSize(13).fontColor($r('sys.color.font_secondary'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .enabled(enabled)
        .onChange(onChange)
    }
    .width('100%')
    .opacity(enabled ? 1 : 0.4)
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }

  @Builder
  selectRow(title: string, choices: Choice[], value: string, enabled: boolean, onSelect: (value: string) => void) {
    Row() {
      Text(title).fontSize(16).layoutWeight(1)
      Select(choices.map((choice: Choice): SelectOption => ({ value: choice.name })))
        .selected(Math.max(0, choices.findIndex((choice: Choice) => choice.value === value)))
        .value(choices.find((choice: Choice) => choice.value === value)?.name ?? choices[0].name)
        .enabled(enabled)
        .onSelect((index: number): void => onSelect(choices[index].value))
    }
    .width('100%')
    .opacity(enabled ? 1 : 0.4)
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }

  @Builder
  sliderRow(title: string, value: number, min: number, max: number, step: number, unit: string, enabled: boolean,
    onChange: (value: number) => void) {
    Column() {
      Row() {
        Text(title).fontSize(16).layoutWeight(1)
        Text(`${value}${unit}`).fontSize(16)
      }
      .width('100%')
      Slider({ value: value, min: min, max: max, step: step })
        .width('100%')
        .enabled(enabled)
        .onChange((v: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            onChange(Math.round(v / step) * step)
          }
        })
    }
    .width('100%')
    .opacity(enabled ? 1 : 0.4)
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }

  @Builder
  linkRow(title: string, summary: string, onClick: () => void) {
    Row() {
      Column() {
        Text(title).fontSize(16)
        if (summary) {
          Text(summary).fontSize(13).fontColor($r('sys.color.font_secondary'))
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

  build() {
    NavDestination() {
      List() {
        ListItem() {
          Column() {
            this.section('输入法')
            this.toggleRow('双击空格键可插入句号', '', this.settings.doubleSpacePeriod, true, (on: boolean) => {
              this.settings.doubleSpacePeriod = on
              this.saveSettings()
            })
            this.toggleRow('启用滑行光标控制功能', '滑动空格键即可移动光标', this.settings.spaceSwipeMoveCursor, true,
              (on: boolean) => {
                this.settings.spaceSwipeMoveCursor = on
                this.saveSettings()
              })
          }
        }
        ListItem() {
          Column() {
            this.section('中文输入法')
            if (this.hasShuangpin) {
              this.selectRow('拼音方案', SCHEMES, this.version >= 0 ? this.currentScheme() : '', true,
                (value: string): void => this.applyScheme(value))
            }
            if (this.chttransCfg) {
              this.toggleRow('繁体中文', '', this.version >= 0 && this.traditional(), true,
                (on: boolean): void => this.setTraditional(on))
            }
            this.toggleRow('建议英语单词', '在输入拼音时建议热门英语单词',
              this.version >= 0 && this.pinyinBool('SpellEnabled'), true, (on: boolean) => {
                this.updatePinyin((cfg: RawConfig): void => this.setNode(cfg, 'SpellEnabled', on ? 'True' : 'False'))
              })
            this.toggleRow('智能更正', '错别字智能更正',
              this.version >= 0 && this.node(this.pinyinCfg, 'Fuzzy/Correction')?.value === 'QWERTY', true,
              (on: boolean) => {
                this.updatePinyin((cfg: RawConfig): void => this.setNode(cfg, 'Fuzzy/Correction', on ? 'QWERTY' : 'None'))
              })
            this.toggleRow('中文联想', '根据上一个字词提供建议',
              this.version >= 0 && this.pinyinBool('Prediction'), true, (on: boolean) => {
                this.updatePinyin((cfg: RawConfig): void => this.setNode(cfg, 'Prediction', on ? 'True' : 'False'))
              })
            // Off by default: v stays pinyin, so vpn, vip, vivo are typed like any word.
            this.toggleRow('V 键快速输入', '开头的 v 进入快速输入，关闭时 v 照常打拼音',
              this.version >= 0 && this.pinyinBool('VAsQuickphrase'), true, (on: boolean) => {
                this.updatePinyin((cfg: RawConfig): void => this.setNode(cfg, 'VAsQuickphrase', on ? 'True' : 'False'))
              })
            this.toggleRow('模糊拼音', '', this.version >= 0 && this.fuzzyEnabled(), true, (on: boolean) => {
              // Like Google Pinyin, turning it on enables its default pairs.
              this.updatePinyin((cfg: RawConfig): void => {
                for (const pair of FUZZY_PAIRS) {
                  this.setNode(cfg, `Fuzzy/${pair.key}`, on && pair.byDefault ? 'True' : 'False')
                }
              })
            })
            ForEach(FUZZY_PAIRS, (pair: FuzzyPair) => {
              this.toggleRow(pair.title, '', this.version >= 0 && this.pinyinBool(`Fuzzy/${pair.key}`),
                this.version >= 0 && this.fuzzyEnabled(), (on: boolean) => {
                  this.updatePinyin((cfg: RawConfig): void => this.setNode(cfg, `Fuzzy/${pair.key}`, on ? 'True' : 'False'))
                })
            }, (pair: FuzzyPair) => `${pair.key}-${this.version}`)
          }
        }
        ListItem() {
          Column() {
            this.section('键盘')
            this.linkRow('主题背景', '', (): void => this.stack.pushPathByName('keyboard', null))
            this.toggleRow('按键声音', '', this.settings.keySound, true, (on: boolean) => {
              this.settings.keySound = on
              this.saveSettings()
            })
            this.sliderRow('按键音量', this.settings.keySoundVolume, 0, 100, 1, '%', this.settings.keySound,
              (v: number) => {
                this.settings.keySoundVolume = v
                this.saveSettings()
              })
            this.toggleRow('按键时振动', '', this.settings.vibrate, true, (on: boolean) => {
              this.settings.vibrate = on
              this.saveSettings()
            })
            this.selectRow('按键振动强度', STRENGTHS.map((s: VibrationStrength, i: number): Choice => ({
              name: STRENGTH_NAMES[i], value: s
            })), this.settings.vibrationStrength, this.settings.vibrate, (value: string) => {
              this.settings.vibrationStrength = value as VibrationStrength
              this.saveSettings()
            })
            this.toggleRow('按键时弹出显示字符', '', this.settings.popupOnKeyPress, true, (on: boolean) => {
              this.settings.popupOnKeyPress = on
              this.saveSettings()
            })
            this.toggleRow('显示英语键盘', '', this.version >= 0 && this.enabledIms.includes('keyboard-us'), true,
              (on: boolean) => {
                const list = this.enabledIms.filter((im: string) => im !== 'keyboard-us')
                if (on) {
                  list.unshift('keyboard-us')
                }
                this.setEnabled(list)
              })
            this.selectRow('键盘高度', HEIGHTS,
              this.settings.heightMode === 'googlepinyin' ? `${this.settings.heightRatio}` : '100', true,
              (value: string) => {
                this.settings.heightMode = 'googlepinyin'
                this.settings.heightRatio = Number.parseInt(value)
                this.saveSettings()
              })
            this.selectRow('滑动输入的敏感度', SENSITIVITIES, `${this.settings.slideSensitivity}`, true,
              (value: string) => {
                this.settings.slideSensitivity = Number.parseFloat(value)
                this.saveSettings()
              })
            this.sliderRow('长按按键的延迟时间', this.settings.longPressDelay, 100, 700, 10, ' 毫秒', true,
              (v: number) => {
                this.settings.longPressDelay = v
                this.saveSettings()
              })
          }
        }
        ListItem() {
          Column() {
            this.section('字典')
            this.linkRow('导入或导出用户字典', '谷歌拼音用户字典的导入与导出',
              (): void => this.stack.pushPathByName('userDict', null))
            this.linkRow('清除用户字典', '删除输入时学到的全部词语', (): void => this.clearUserDict())
            this.linkRow('编辑自定义短语', '',
              (): void => this.stack.pushPathByName('textFile', textFileParam('customPhrase')))
            Text('未列出的谷歌拼音设置（滑行输入、手写、单手模式、联系人、同步等）在 Fcitx 中没有对应功能。' +
              '更多选项见主设置页。设置在下次弹出键盘时生效。')
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
              .padding(16)
          }
        }
      }
      .width('100%')
      .height('100%')
    }
    .title('谷歌拼音风格设置')
  }
}
