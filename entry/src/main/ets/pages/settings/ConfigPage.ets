// A fcitx config rendered from its description, like fcitx5-android's PreferenceScreenFactory.
import fcitx from 'libentry.so';
import { FcitxConfig, OptionDesc, OptionType, RawConfig } from '../../common/FcitxConfig';
import { TextFilePageParam, textFileParam } from './TextFilePage';

export interface ConfigPageParam {
  uri: string
  title: string
}

const ROW_PADDING: Padding = { left: 16, right: 16, top: 10, bottom: 10 }

// "fcitx://config/addon/pinyin" -> "addon/pinyin"
export function configUri(external: string): string | null {
  const prefix = 'fcitx://config/'
  return external.startsWith(prefix) ? external.substring(prefix.length) : null
}

class ExternalPage {
  name: string
  param: TextFilePageParam | null

  constructor(name: string, param: TextFilePageParam | null) {
    this.name = name
    this.param = param
  }
}

// Pages for External options, like fcitx5-android's ConfigExternal.ETy.
function externalPage(option: string): ExternalPage | null {
  switch (option) {
    case 'DictManager':
      return new ExternalPage('pinyinDict', null)
    case 'CustomPhrase':
      return new ExternalPage('textFile', textFileParam('customPhrase'))
    case 'Punctuation':
      return new ExternalPage('textFile', textFileParam('punctuation'))
    case 'QuickPhrase':
    case 'Editor':
      return new ExternalPage('quickPhrase', null)
    default:
      return null
  }
}

// One list row: an option with the config node holding its value, or a group header.
class ConfigRow {
  key: string
  option: OptionDesc
  node: RawConfig
  header: boolean

  constructor(key: string, option: OptionDesc, node: RawConfig, header: boolean) {
    this.key = key
    this.option = option
    this.node = node
    this.header = header
  }
}

// Custom types (e.g. fuzzy pinyin) become a header followed by their options.
function flatten(options: OptionDesc[], node: RawConfig, prefix: string, rows: ConfigRow[]): ConfigRow[] {
  for (const option of options) {
    const key = `${prefix}/${option.name}`
    if (option.type === OptionType.Custom) {
      rows.push(new ConfigRow(key, option, node, true))
      flatten(option.children, node.getOrCreate(option.name), key, rows)
    } else if (option.type !== OptionType.Unknown) {
      rows.push(new ConfigRow(key, option, node, false))
    }
  }
  return rows
}

function value(row: ConfigRow): string {
  return row.node.find(row.option.name)?.value ?? row.option.defaultValue
}

function list(row: ConfigRow): string[] {
  const item = row.node.find(row.option.name)
  return item ? item.listValues() : row.option.defaultList
}

function enumLabel(option: OptionDesc, index: number): string {
  return option.enumsI18n[index] || option.enums[index]
}

function hasSlider(option: OptionDesc): boolean {
  return option.intMin !== undefined && option.intMax !== undefined && option.intMax - option.intMin <= 200
}

@Component
export struct ConfigPage {
  @Consume('settingsStack') stack: NavPathStack
  param: ConfigPageParam = { uri: '', title: '' }
  @State version: number = 0
  @State rows: ConfigRow[] = []
  private config: FcitxConfig | null = null

  aboutToAppear() {
    this.config = FcitxConfig.parse(fcitx.getConfig(this.param.uri))
    if (this.config) {
      this.rows = flatten(this.config.options, this.config.cfg, '', [])
    }
  }

  private save() {
    if (!this.config) {
      return
    }
    fcitx.setConfig(this.param.uri, JSON.stringify(this.config.cfg.toJson()))
    this.version++
  }

  private set(row: ConfigRow, newValue: string) {
    row.node.getOrCreate(row.option.name).value = newValue
    this.save()
  }

  private setList(row: ConfigRow, values: string[]) {
    row.node.getOrCreate(row.option.name).setListValues(values)
    this.save()
  }

  @Builder
  label(option: OptionDesc) {
    Column() {
      Text(option.description).fontSize(16)
      if (option.tooltip) {
        Text(option.tooltip).fontSize(13).fontColor($r('sys.color.font_secondary'))
      }
    }
    .alignItems(HorizontalAlign.Start)
  }

  // Next to a control: takes the remaining width.
  @Builder
  rowLabel(option: OptionDesc) {
    Column() {
      this.label(option)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  @Builder
  boolRow(row: ConfigRow) {
    Row() {
      this.rowLabel(row.option)
      Toggle({ type: ToggleType.Switch, isOn: value(row) === 'True' })
        .onChange((isOn: boolean) => this.set(row, isOn ? 'True' : 'False'))
    }
    .width('100%')
    .padding(ROW_PADDING)
  }

  @Builder
  enumRow(row: ConfigRow) {
    Row() {
      this.rowLabel(row.option)
      Select(row.option.enums.map((_: string, i: number): SelectOption => ({ value: enumLabel(row.option, i) })))
        .selected(Math.max(0, row.option.enums.indexOf(value(row))))
        .value(enumLabel(row.option, Math.max(0, row.option.enums.indexOf(value(row)))))
        .onSelect((index: number) => this.set(row, row.option.enums[index]))
    }
    .width('100%')
    .padding(ROW_PADDING)
  }

  @Builder
  intRow(row: ConfigRow) {
    Column() {
      Row() {
        this.rowLabel(row.option)
        if (hasSlider(row.option)) {
          Text(value(row)).fontSize(16)
        } else {
          TextInput({ text: value(row) })
            .type(InputType.Number)
            .width(100)
            .onSubmit((_: EnterKeyType, event: SubmitEvent) => this.set(row, event.text))
        }
      }
      .width('100%')
      if (hasSlider(row.option)) {
        Slider({
          value: Number.parseInt(value(row)) || 0,
          min: row.option.intMin,
          max: row.option.intMax,
          step: 1,
        })
          .width('100%')
          .onChange((v: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.set(row, `${Math.round(v)}`)
            }
          })
      }
    }
    .width('100%')
    .padding(ROW_PADDING)
  }

  @Builder
  textRow(row: ConfigRow) {
    Column({ space: 6 }) {
      this.label(row.option)
      TextInput({ text: value(row) })
        .onSubmit((_: EnterKeyType, event: SubmitEvent) => this.set(row, event.text))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(ROW_PADDING)
  }

  @Builder
  listRow(row: ConfigRow) {
    Column({ space: 6 }) {
      this.label(row.option)
      Text('每行一项，编辑完成后点空白处保存').fontSize(13).fontColor($r('sys.color.font_secondary'))
      TextArea({ text: list(row).join('\n') })
        .onChange((text: string) => {
          row.node.getOrCreate(row.option.name)
            .setListValues(text.split('\n').map((s: string) => s.trim()).filter((s: string) => s.length > 0))
        })
        .onBlur(() => this.save())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(ROW_PADDING)
  }

  @Builder
  enumListRow(row: ConfigRow) {
    Column() {
      this.label(row.option)
      ForEach(row.option.enums, (entry: string, index: number) => {
        Row() {
          Text(enumLabel(row.option, index)).fontSize(15).layoutWeight(1)
          Toggle({ type: ToggleType.Checkbox, isOn: list(row).includes(entry) })
            .onChange((isOn: boolean) => {
              const values = list(row).filter((v: string) => v !== entry)
              if (isOn) {
                values.push(entry)
              }
              this.setList(row, values)
            })
        }
        .width('100%')
        .padding({ top: 4, bottom: 4 })
      }, (entry: string) => `${entry}-${this.version}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(ROW_PADDING)
  }

  @Builder
  externalRow(row: ConfigRow) {
    Row() {
      this.rowLabel(row.option)
      Text(externalPage(row.option.name) || configUri(row.option.externalUri) ? '›' : '暂不支持')
        .fontSize(externalPage(row.option.name) || configUri(row.option.externalUri) ? 22 : 14)
        .fontColor($r('sys.color.font_secondary'))
    }
    .width('100%')
    .padding(ROW_PADDING)
    .onClick(() => {
      const page = externalPage(row.option.name)
      if (page) {
        this.stack.pushPathByName(page.name, page.param)
        return
      }
      const uri = configUri(row.option.externalUri)
      if (uri) {
        this.stack.pushPathByName('config', { uri: uri, title: row.option.description } as ConfigPageParam)
      }
    })
  }

  @Builder
  headerRow(row: ConfigRow) {
    Text(row.option.description)
      .fontSize(14)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 4 })
  }

  build() {
    NavDestination() {
      if (this.rows.length > 0) {
        List() {
          ForEach(this.rows, (row: ConfigRow) => {
            ListItem() {
              if (row.header) {
                this.headerRow(row)
              } else if (row.option.type === OptionType.Bool) {
                this.boolRow(row)
              } else if (row.option.type === OptionType.Enum) {
                this.enumRow(row)
              } else if (row.option.type === OptionType.Int) {
                this.intRow(row)
              } else if (row.option.type === OptionType.String || row.option.type === OptionType.Key) {
                this.textRow(row)
              } else if (row.option.type === OptionType.List) {
                this.listRow(row)
              } else if (row.option.type === OptionType.EnumList) {
                this.enumListRow(row)
              } else if (row.option.type === OptionType.External) {
                this.externalRow(row)
              }
            }
          }, (row: ConfigRow) => `${row.key}-${this.version}`)
        }
        .height('100%')
      } else {
        Text('没有可设置的选项').padding(16)
      }
    }
    .title(this.param.title)
  }
}
