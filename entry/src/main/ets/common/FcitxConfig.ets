// fcitx configs as returned by the native getConfig: {cfg, desc} RawConfig trees.
// The descriptor parsing follows fcitx5-android's ConfigDescriptor.kt.

export interface RawConfigJson {
  name: string
  value: string
  subItems: RawConfigJson[]
}

export class RawConfig {
  name: string
  value: string
  subItems: RawConfig[] = []

  constructor(name: string, value: string = '') {
    this.name = name
    this.value = value
  }

  static fromJson(json: RawConfigJson): RawConfig {
    const config = new RawConfig(json.name, json.value)
    config.subItems = json.subItems.map((item: RawConfigJson) => RawConfig.fromJson(item))
    return config
  }

  toJson(): RawConfigJson {
    return {
      name: this.name,
      value: this.value,
      subItems: this.subItems.map((item: RawConfig) => item.toJson()),
    }
  }

  find(name: string): RawConfig | undefined {
    return this.subItems.find((item: RawConfig) => item.name === name)
  }

  getOrCreate(name: string): RawConfig {
    let item = this.find(name)
    if (!item) {
      item = new RawConfig(name)
      this.subItems.push(item)
    }
    return item
  }

  // Lists are stored as items named 0, 1, 2...
  listValues(): string[] {
    return this.subItems.map((item: RawConfig) => item.value)
  }

  setListValues(values: string[]) {
    this.subItems = values.map((value: string, index: number) => new RawConfig(`${index}`, value))
  }
}

export enum OptionType {
  Bool,
  Int,
  String,
  Key,
  Enum,
  External,
  Custom,
  List,
  EnumList,
  Unknown,
}

export class OptionDesc {
  name: string = ''
  type: OptionType = OptionType.Unknown
  // For List: the element type, for Custom: the custom type name.
  subtype: OptionType = OptionType.Unknown
  typeName: string = ''
  description: string = ''
  tooltip: string = ''
  defaultValue: string = ''
  defaultList: string[] = []
  intMin: number | undefined = undefined
  intMax: number | undefined = undefined
  enums: string[] = []
  enumsI18n: string[] = []
  externalUri: string = ''
  // Options of a Custom type.
  children: OptionDesc[] = []
}

function parseType(raw: string): OptionType {
  switch (raw) {
    case 'Integer':
      return OptionType.Int
    case 'String':
      return OptionType.String
    case 'Boolean':
      return OptionType.Bool
    case 'Key':
      return OptionType.Key
    case 'Enum':
      return OptionType.Enum
    case 'External':
      return OptionType.External
    default:
      if (raw.startsWith('List|')) {
        return OptionType.List
      }
      if (raw.includes('$')) {
        return OptionType.Custom
      }
      return OptionType.Unknown
  }
}

function parseOption(raw: RawConfig): OptionDesc {
  const option = new OptionDesc()
  option.name = raw.name
  const typeRaw = raw.find('Type')?.value ?? ''
  option.typeName = typeRaw
  option.type = typeRaw === 'String' && raw.find('IsEnum')?.value === 'True' ? OptionType.Enum : parseType(typeRaw)
  option.description = raw.find('Description')?.value ?? raw.name
  option.tooltip = raw.find('Tooltip')?.value ?? ''
  const defaultValue = raw.find('DefaultValue')
  option.defaultValue = defaultValue?.value ?? ''
  option.defaultList = defaultValue?.listValues() ?? []
  const intMin = raw.find('IntMin')?.value
  const intMax = raw.find('IntMax')?.value
  option.intMin = intMin === undefined ? undefined : Number.parseInt(intMin)
  option.intMax = intMax === undefined ? undefined : Number.parseInt(intMax)
  option.enums = raw.find('Enum')?.listValues() ?? []
  option.enumsI18n = raw.find('EnumI18n')?.listValues() ?? []
  option.externalUri = raw.find('External')?.value ?? ''
  if (option.type === OptionType.List) {
    option.subtype = parseType(typeRaw.substring(5))
    if (option.subtype === OptionType.Enum) {
      option.type = OptionType.EnumList
    }
  }
  return option
}

// desc: the first item is the top level type, others are custom types it refers to.
export function parseDescription(desc: RawConfig): OptionDesc[] {
  if (desc.subItems.length === 0) {
    return []
  }
  const customTypes = new Map<string, OptionDesc[]>()
  for (const customType of desc.subItems.slice(1)) {
    customTypes.set(customType.name, customType.subItems.map(parseOption))
  }
  const resolve = (options: OptionDesc[], depth: number): OptionDesc[] => {
    for (const option of options) {
      if (option.type === OptionType.Custom && depth < 4) {
        option.children = resolve(customTypes.get(option.typeName) ?? [], depth + 1)
      }
    }
    return options
  }
  return resolve(desc.subItems[0].subItems.map(parseOption), 0)
}

export class FcitxConfig {
  cfg: RawConfig
  options: OptionDesc[]

  constructor(cfg: RawConfig, options: OptionDesc[]) {
    this.cfg = cfg
    this.options = options
  }

  // json from the native getConfig; null if not configurable.
  static parse(json: string): FcitxConfig | null {
    if (!json) {
      return null
    }
    const top = RawConfig.fromJson(JSON.parse(json) as RawConfigJson)
    const cfg = top.find('cfg') ?? new RawConfig('cfg')
    const desc = top.find('desc') ?? new RawConfig('desc')
    return new FcitxConfig(cfg, parseDescription(desc))
  }
}
