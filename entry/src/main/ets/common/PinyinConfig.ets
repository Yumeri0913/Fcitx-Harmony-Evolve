// Pinyin engine options in fcitx's conf/pinyin.conf, edited by the main app and
// reloaded by the input method when the keyboard shows.
import { fileIo as fs } from '@kit.CoreFileKit'
import { readText, writeText } from './Settings'

// Same as XDG_CONFIG_HOME set by the native side.
export function pinyinConfigPath(filesDir: string): string {
  return `${filesDir}/config/fcitx5/conf/pinyin.conf`
}

// Modification time, to tell whether the main app changed the file.
export function pinyinConfigMtime(filesDir: string): number {
  try {
    return fs.statSync(pinyinConfigPath(filesDir)).mtime
  } catch (e) {
    return 0
  }
}

export interface BoolOption {
  // Path in the ini file, e.g. "Prediction" or "Fuzzy/Z_ZH".
  path: string
  label: string
  // fcitx default when the file doesn't set it.
  defaultValue: boolean
}

export const GENERAL_OPTIONS: BoolOption[] = [
  { path: 'Prediction', label: '联想（预测下一个词）', defaultValue: true },
  { path: 'SpellEnabled', label: '英文候选（中英混输）', defaultValue: true },
  { path: 'CloudPinyinEnabled', label: '云拼音', defaultValue: false },
  { path: 'ChaiziEnabled', label: '拆字（u 模式）', defaultValue: true },
  { path: 'ExtBEnabled', label: '生僻字（扩展 B 区及以后）', defaultValue: true },
]

// Google Pinyin's fuzzy pinyin pairs come first.
export const FUZZY_OPTIONS: BoolOption[] = [
  { path: 'Fuzzy/Z_ZH', label: 'z ↔ zh', defaultValue: false },
  { path: 'Fuzzy/C_CH', label: 'c ↔ ch', defaultValue: false },
  { path: 'Fuzzy/S_SH', label: 's ↔ sh', defaultValue: false },
  { path: 'Fuzzy/AN_ANG', label: 'an ↔ ang', defaultValue: false },
  { path: 'Fuzzy/EN_ENG', label: 'en ↔ eng', defaultValue: false },
  { path: 'Fuzzy/IN_ING', label: 'in ↔ ing', defaultValue: false },
  { path: 'Fuzzy/L_N', label: 'l ↔ n', defaultValue: false },
  { path: 'Fuzzy/F_H', label: 'f ↔ h', defaultValue: false },
  { path: 'Fuzzy/L_R', label: 'l ↔ r', defaultValue: false },
  { path: 'Fuzzy/IAN_IANG', label: 'ian ↔ iang', defaultValue: false },
  { path: 'Fuzzy/UAN_UANG', label: 'uan ↔ uang', defaultValue: false },
  { path: 'Fuzzy/U_OU', label: 'u ↔ ou', defaultValue: false },
  { path: 'Fuzzy/V_U', label: 'u ↔ v', defaultValue: false },
]

// What Google Pinyin checks when its fuzzy pinyin switch is turned on.
export const GOOGLE_PINYIN_FUZZY: string[] = [
  'Fuzzy/Z_ZH', 'Fuzzy/C_CH', 'Fuzzy/S_SH', 'Fuzzy/AN_ANG', 'Fuzzy/EN_ENG', 'Fuzzy/IN_ING',
]

class Section {
  name: string
  // Raw lines, kept to preserve comments and options this app doesn't know.
  lines: string[] = []

  constructor(name: string) {
    this.name = name
  }
}

// Minimal reader/writer of fcitx ini files: "Key=Value" lines under "[Section]" headers.
export class PinyinConfig {
  private sections: Section[] = []

  static load(filesDir: string): PinyinConfig {
    const config = new PinyinConfig()
    config.sections.push(new Section(''))
    const text = readText(pinyinConfigPath(filesDir)) ?? ''
    for (const raw of text.split('\n')) {
      const line = raw.replace(/\r$/, '')
      const header = /^\s*\[(.*)\]\s*$/.exec(line)
      if (header) {
        config.sections.push(new Section(header[1]))
      } else {
        config.sections[config.sections.length - 1].lines.push(line)
      }
    }
    return config
  }

  private split(path: string): string[] {
    const index = path.lastIndexOf('/')
    return index < 0 ? ['', path] : [path.substring(0, index), path.substring(index + 1)]
  }

  private findLine(section: Section, key: string): number {
    return section.lines.findIndex((line: string) => {
      const index = line.indexOf('=')
      return index > 0 && line.substring(0, index).trim() === key
    })
  }

  getBool(option: BoolOption): boolean {
    const parts = this.split(option.path)
    const section = this.sections.find((s: Section) => s.name === parts[0])
    if (!section) {
      return option.defaultValue
    }
    const index = this.findLine(section, parts[1])
    if (index < 0) {
      return option.defaultValue
    }
    const line = section.lines[index]
    return line.substring(line.indexOf('=') + 1).trim() === 'True'
  }

  setBool(path: string, value: boolean) {
    const parts = this.split(path)
    let section = this.sections.find((s: Section) => s.name === parts[0])
    if (!section) {
      section = new Section(parts[0])
      this.sections.push(section)
    }
    const line = `${parts[1]}=${value ? 'True' : 'False'}`
    const index = this.findLine(section, parts[1])
    if (index < 0) {
      // Before trailing blank lines, which separate sections.
      let insertAt = section.lines.length
      while (insertAt > 0 && section.lines[insertAt - 1].trim() === '') {
        insertAt--
      }
      section.lines.splice(insertAt, 0, line)
    } else {
      section.lines[index] = line
    }
  }

  // Write options the file doesn't set yet, so it matches what the app shows.
  // Prediction differs from the fcitx default.
  fillDefaults(options: BoolOption[]) {
    for (const option of options) {
      const parts = this.split(option.path)
      const section = this.sections.find((s: Section) => s.name === parts[0])
      if (!section || this.findLine(section, parts[1]) < 0) {
        this.setBool(option.path, option.defaultValue)
      }
    }
  }

  save(filesDir: string) {
    const out: string[] = []
    for (const section of this.sections) {
      if (section.name !== '') {
        if (out.length > 0 && out[out.length - 1].trim() !== '') {
          out.push('')
        }
        out.push(`[${section.name}]`)
      }
      out.push(...section.lines)
    }
    let text = out.join('\n')
    if (!text.endsWith('\n')) {
      text += '\n'
    }
    writeText(pinyinConfigPath(filesDir), text)
  }
}
