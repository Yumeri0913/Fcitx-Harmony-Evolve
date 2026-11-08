// Theme and keyboard preferences, like fcitx5-android's theme and keyboard settings.
import { common } from '@kit.AbilityKit';
import {
  HeightMode, KeyboardSettings, loadSettings, saveSettings, ThemeMode, VibrationStrength
} from '../../common/Settings';

const THEMES: ThemeMode[] = ['system', 'light', 'dark']
const THEME_NAMES: string[] = ['跟随系统', '浅色', '深色']
const STRENGTHS: VibrationStrength[] = ['light', 'medium', 'heavy']
const STRENGTH_NAMES: string[] = ['轻', '中', '强']
const HEIGHT_MODES: HeightMode[] = ['googlepinyin', 'percent']
const HEIGHT_MODE_NAMES: string[] = ['与谷歌拼音相同', '屏幕高度百分比']

@Component
export struct KeyboardPage {
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext
  private sharedDir: string = this.context.distributedFilesDir
  @State settings: KeyboardSettings = loadSettings(this.sharedDir)

  private save() {
    try {
      saveSettings(this.sharedDir, this.settings)
    } catch (e) {
      console.error(`Failed to save settings: ${e}`)
    }
  }

  @Builder
  section(title: string) {
    Text(title)
      .fontSize(14)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
      .padding({ left: 16, top: 16, bottom: 4 })
  }

  @Builder
  toggleRow(label: string, isOn: boolean, onChange: (isOn: boolean) => void) {
    Row() {
      Text(label).fontSize(16).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: isOn }).onChange(onChange)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }

  @Builder
  selectRow(label: string, names: string[], index: number, onSelect: (index: number) => void) {
    Row() {
      Text(label).fontSize(16).layoutWeight(1)
      Select(names.map((name: string): SelectOption => ({ value: name })))
        .selected(index)
        .value(names[index])
        .onSelect(onSelect)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }

  @Builder
  sliderRow(label: string, value: number, min: number, max: number, unit: string, enabled: boolean,
    onChange: (value: number) => void) {
    Column() {
      Row() {
        Text(label).fontSize(16).layoutWeight(1)
        Text(`${value}${unit}`).fontSize(16)
      }
      .width('100%')
      Slider({ value: value, min: min, max: max, step: 1 })
        .width('100%')
        .enabled(enabled)
        .onChange((v: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            onChange(Math.round(v))
          }
        })
    }
    .width('100%')
    .opacity(enabled ? 1 : 0.4)
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }

  build() {
    NavDestination() {
      List() {
        ListItem() {
          Column() {
            this.section('外观')
            this.selectRow('主题', THEME_NAMES, THEMES.indexOf(this.settings.theme), (index: number) => {
              this.settings.theme = THEMES[index]
              this.save()
            })
            this.toggleRow('按键边框', this.settings.keyBorder, (isOn: boolean) => {
              this.settings.keyBorder = isOn
              this.save()
            })
            this.sliderRow('按键圆角', this.settings.keyRadius, 0, 24, ' vp', true, (v: number) => {
              this.settings.keyRadius = v
              this.save()
            })
            this.sliderRow('按键水平间距', this.settings.keyMarginX, 0, 12, ' vp', true, (v: number) => {
              this.settings.keyMarginX = v
              this.save()
            })
            this.sliderRow('按键垂直间距', this.settings.keyMarginY, 0, 16, ' vp', true, (v: number) => {
              this.settings.keyMarginY = v
              this.save()
            })
          }
        }
        ListItem() {
          Column() {
            this.section('键盘高度')
            this.selectRow('高度', HEIGHT_MODE_NAMES, HEIGHT_MODES.indexOf(this.settings.heightMode),
              (index: number) => {
                this.settings.heightMode = HEIGHT_MODES[index]
                this.save()
              })
            this.sliderRow('竖屏', this.settings.heightPercentPortrait, 15, 60, '%',
              this.settings.heightMode === 'percent', (v: number) => {
                this.settings.heightPercentPortrait = v
                this.save()
              })
            this.sliderRow('横屏', this.settings.heightPercentLandscape, 15, 80, '%',
              this.settings.heightMode === 'percent', (v: number) => {
                this.settings.heightPercentLandscape = v
                this.save()
              })
          }
        }
        ListItem() {
          Column() {
            this.section('按键')
            this.toggleRow('按键时显示预览', this.settings.popupOnKeyPress, (isOn: boolean) => {
              this.settings.popupOnKeyPress = isOn
              this.save()
            })
            this.toggleRow('按键振动', this.settings.vibrate, (isOn: boolean) => {
              this.settings.vibrate = isOn
              this.save()
            })
            this.selectRow('振动强度', STRENGTH_NAMES, STRENGTHS.indexOf(this.settings.vibrationStrength),
              (index: number) => {
                this.settings.vibrationStrength = STRENGTHS[index]
                this.save()
              })
            this.toggleRow('按键音', this.settings.keySound, (isOn: boolean) => {
              this.settings.keySound = isOn
              this.save()
            })
            this.sliderRow('按键音量', this.settings.keySoundVolume, 0, 100, '%', this.settings.keySound,
              (v: number) => {
                this.settings.keySoundVolume = v
                this.save()
              })
            Text('修改后下次弹出键盘时生效。')
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
              .padding(16)
          }
        }
      }
      .height('100%')
    }
    .title('主题与键盘')
  }
}
