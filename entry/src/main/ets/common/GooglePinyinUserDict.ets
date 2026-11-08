// Reader/writer for the user dictionary text file produced by Google Pinyin for Android
// (Settings -> Dictionary -> Export user dictionary, GooglePinyinInput/user-dictionary.txt).
// Ported from fcitx5-android (InsightKey fork) GooglePinyinUserDict.kt.
//
// Google Pinyin export format:
// - UTF-16LE with BOM, \n line endings
// - first line "# User dictionary for Google Pinyin Input"
// - one entry per line: word<TAB>count<TAB>pin yin[<TAB>tx=N]
// - English entries mark their tokens with a language marker, e.g. hello\t3\t\0 hello
//
// Google Pinyin's importer is lenient: BOM decides the charset (GBK without BOM), lines
// starting with # or ; are comments, fields are separated by TAB (or a single space when
// the line has no TAB), and the order of the first three fields does not matter.
import { util } from '@kit.ArkTS'

export const HEADER = '# User dictionary for Google Pinyin Input'
export const DEFAULT_FILE_NAME = 'user-dictionary.txt'

export class Entry {
  word: string
  syllables: string[]
  count: number

  constructor(word: string, syllables: string[], count: number) {
    this.word = word
    this.syllables = syllables
    this.count = count
  }

  get libimePinyin(): string {
    return this.syllables.join('\'')
  }

  get googlePinyin(): string {
    return this.syllables.join(' ')
  }
}

export interface ParseResult {
  entries: Entry[]
  // Non-comment lines that could not be converted (English words, invalid pinyin...)
  skipped: number
}

// Full pinyin syllables accepted by libime without fuzzy flags.
const VALID_SYLLABLES: Set<string> = new Set<string>((
  'a ai an ang ao ba bai ban bang bao bei ben beng bi bian biang biao bie bin bing bo bong bu ' +
    'ca cai can cang cao ce cen ceng cha chai chan chang chao che chen cheng chi chong chou chu ' +
    'chua chuai chuan chuang chui chun chuo ci cong cou cu cuan cui cun cuo da dai dan dang dao ' +
    'de dei den deng di dia dian diao die din ding diu dong dou du duan dui dun duo e ei en eng ' +
    'er fa fan fang fei fen feng fiao fo fou fu ga gai gan gang gao ge gei gen geng gong gou gu ' +
    'gua guai guan guang gui gun guo ha hai han hang hao he hei hen heng hong hou hu hua huai ' +
    'huan huang hui hun huo ji jia jian jiang jiao jie jin jing jiong jiu ju juan jue jun ka kai ' +
    'kan kang kao ke kei ken keng kong kou ku kua kuai kuan kuang kui kun kuo la lai lan lang lao ' +
    'le lei leng li lia lian liang liao lie lin ling liu lo long lou lu luan lun luo lv lve m ma ' +
    'mai man mang mao me mei men meng mi mian miao mie min ming miu mo mou mu n na nai nan nang ' +
    'nao ne nei nen neng ng ni nia nian niang niao nie nin ning niu nong nou nu nuan nun nuo nv ' +
    'nve o ou pa pai pan pang pao pei pen peng pi pian piao pie pin ping po pou pu qi qia qian ' +
    'qiang qiao qie qin qing qiong qiu qu quan que qun r ran rang rao re ren reng ri rong rou ru ' +
    'rua ruan rui run ruo sa sai san sang sao se sen seng sha shai shan shang shao she shei shen ' +
    'sheng shi shou shu shua shuai shuan shuang shui shun shuo si song sou su suan sui sun suo ta ' +
    'tai tan tang tao te tei teng ti tian tiao tie ting tong tou tu tuan tui tun tuo wa wai wan ' +
    'wang wei wen weng wo wong wu xi xia xian xiang xiao xie xin xing xiong xiu xu xuan xue xun ' +
    'ya yan yang yao ye yi yin ying yo yong you yu yuan yue yun za zai zan zang zao ze zei zen ' +
    'zeng zha zhai zhan zhang zhao zhe zhei zhen zheng zhi zhong zhou zhu zhua zhuai zhuan zhuang ' +
    'zhui zhun zhuo zi zong zou zu zuan zui zun zuo'
).split(' '))

const pinyinRegex = /^'?[a-zü]+(?:[ '|][a-zü]+)*'?$/
const countRegex = /^[0-9]+,?$/
const englishRegex = /^[A-Za-z]+(?:[-'][A-Za-z]+)*$/
const languageMarkerRegex = /\\[0-9]+/
const syllableSeparator = /[ '|]+/
const hanRegex = /^[\p{Script=Han}〇]$/u

function startsWith(bytes: Uint8Array, prefix: number[]): boolean {
  if (bytes.length < prefix.length) {
    return false
  }
  for (let i = 0; i < prefix.length; i++) {
    if (bytes[i] !== prefix[i]) {
      return false
    }
  }
  return true
}

function decodeAs(encoding: string, bytes: Uint8Array, fatal: boolean): string {
  const decoder = util.TextDecoder.create(encoding, { fatal: fatal, ignoreBOM: true })
  return decoder.decodeToString(bytes)
}

// Decode bytes the same way Google Pinyin does: by BOM, falling back to UTF-8 if the content
// is valid UTF-8, otherwise GBK (Google Pinyin's own default for files without BOM).
export function decode(bytes: Uint8Array): string {
  if (startsWith(bytes, [0xFF, 0xFE])) {
    return decodeAs('utf-16le', bytes.subarray(2), false)
  }
  if (startsWith(bytes, [0xFE, 0xFF])) {
    return decodeAs('utf-16be', bytes.subarray(2), false)
  }
  if (startsWith(bytes, [0xEF, 0xBB, 0xBF])) {
    return decodeAs('utf-8', bytes.subarray(3), false)
  }
  try {
    return decodeAs('utf-8', bytes, true)
  } catch (e) {
    return decodeAs('gb18030', bytes, false)
  }
}

function codePoints(s: string): string[] {
  return Array.from(s)
}

function isHan(c: string): boolean {
  return hanRegex.test(c)
}

function containsHan(s: string): boolean {
  return codePoints(s).some(isHan)
}

function hanLength(s: string): number {
  const chars = codePoints(s)
  return chars.every(isHan) ? chars.length : -1
}

// Normalize one syllable to libime spelling (ü -> v, lue/nue -> lve/nve).
export function normalizeSyllable(s: string): string {
  const v = s.toLowerCase().replace(/ü/g, 'v')
  if (v === 'lue') {
    return 'lve'
  }
  if (v === 'nue') {
    return 'nve'
  }
  return v
}

function splitFields(line: string): string[] {
  return line.includes('\t') ? line.split('\t') : line.split(' ')
}

function trimChars(s: string, chars: string): string {
  let start = 0
  let end = s.length
  while (start < end && chars.includes(s[start])) {
    start++
  }
  while (end > start && chars.includes(s[end - 1])) {
    end--
  }
  return s.substring(start, end)
}

function parseLine(line: string): Entry | null {
  const fields = splitFields(line).slice(0, 3)
  let word: string | null = null
  let pinyin: string | null = null
  let count: number | null = null
  let other: string | null = null
  for (const f of fields) {
    const field = f.trim()
    if (field.length === 0) {
      continue
    }
    if (languageMarkerRegex.test(field)) {
      // Language markers like "\0" mean English (or mixed) tokens: not for pinyin.
      return null
    } else if (containsHan(field)) {
      word = field
    } else if (pinyinRegex.test(field) && pinyin === null) {
      pinyin = field
    } else if (countRegex.test(field)) {
      const n = Number.parseInt(trimChars(field, ','))
      count = Number.isNaN(n) ? 1 : Math.max(1, n)
    } else if (englishRegex.test(field)) {
      return null
    } else {
      other = field
    }
  }
  const w = word ?? other
  if (w === null || pinyin === null) {
    return null
  }
  const syllables = trimChars(pinyin, '\'').split(syllableSeparator)
    .filter((s: string) => s.length > 0)
    .map(normalizeSyllable)
  if (syllables.length === 0 || syllables.some((s: string) => !VALID_SYLLABLES.has(s))) {
    return null
  }
  if (hanLength(w) !== syllables.length) {
    return null
  }
  return new Entry(w, syllables, count ?? 1)
}

// Parse a Google Pinyin user dictionary (already decoded).
export function parse(text: string): ParseResult {
  const merged = new Map<string, Entry>()
  let skipped = 0
  for (const raw of text.split('\n')) {
    const line = trimChars(raw, '﻿\r\n')
    if (line.trim().length === 0 || line.startsWith('#') || line.startsWith(';')) {
      continue
    }
    const entry = parseLine(line)
    if (entry === null) {
      skipped++
      continue
    }
    const key = `${entry.word}\t${entry.libimePinyin}`
    const old = merged.get(key)
    if (old === undefined) {
      merged.set(key, entry)
    } else {
      old.count = Math.max(old.count, entry.count)
    }
  }
  return { entries: Array.from(merged.values()), skipped: skipped }
}

// Lines of "word\tpin'yin\tcount", as the native side expects.
export function toTsv(entries: Entry[]): string {
  return entries.map((e: Entry) => `${e.word}\t${e.libimePinyin}\t${e.count}\n`).join('')
}

export function fromTsv(tsv: string): Entry[] {
  const entries: Entry[] = []
  for (const line of tsv.split('\n')) {
    const fields = line.split('\t')
    if (fields.length < 3 || fields[0].length === 0) {
      continue
    }
    const n = Number.parseInt(fields[2])
    entries.push(new Entry(fields[0], fields[1].split('\''), Number.isNaN(n) ? 1 : Math.max(1, n)))
  }
  return entries
}

// Serialize entries to Google Pinyin user dictionary bytes (UTF-16LE with BOM).
export function toGooglePinyinBytes(entries: Entry[]): Uint8Array {
  let text = `${HEADER}\n`
  for (const e of entries) {
    text += `${e.word}\t${Math.max(1, e.count)}\t${e.googlePinyin}\n`
  }
  const bytes = new Uint8Array(2 + text.length * 2)
  bytes[0] = 0xFF
  bytes[1] = 0xFE
  for (let i = 0; i < text.length; i++) {
    const unit = text.charCodeAt(i)
    bytes[2 + i * 2] = unit & 0xFF
    bytes[3 + i * 2] = unit >> 8
  }
  return bytes
}
