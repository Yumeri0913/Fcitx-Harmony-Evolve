// Keyboard settings and data files shared by the main app and the input method,
// which run in different processes but share the module's files dir.
import { fileIo as fs } from '@kit.CoreFileKit'

export type ThemeMode = 'system' | 'light' | 'dark'
// Google Pinyin's vibration strengths, mapped to system haptic presets.
export type VibrationStrength = 'light' | 'medium' | 'heavy'

export interface KeyboardSettings {
  theme: ThemeMode
  // Google Pinyin 按键边框. Off by default like Google Pinyin and fcitx5-android.
  keyBorder: boolean
  vibrate: boolean
  vibrationStrength: VibrationStrength
}

export const DEFAULT_SETTINGS: KeyboardSettings = {
  theme: 'system',
  keyBorder: false,
  vibrate: true,
  vibrationStrength: 'light',
}

export interface ImportResult {
  added: number
  existing: number
  invalid: number
  // Lines of the Google Pinyin file that were not Chinese words, e.g. English.
  skipped: number
  time: number
}

function settingsPath(filesDir: string): string {
  return `${filesDir}/settings.json`
}

function googlePinyinDir(filesDir: string): string {
  return `${filesDir}/googlepinyin`
}

// Words waiting for the input method to merge them into the pinyin engine.
export function pendingImportPath(filesDir: string): string {
  return `${googlePinyinDir(filesDir)}/import.tsv`
}

// Lines of the Google Pinyin file skipped by the main app, merged into the result.
export function pendingSkippedPath(filesDir: string): string {
  return `${googlePinyinDir(filesDir)}/import-skipped`
}

export function importResultPath(filesDir: string): string {
  return `${googlePinyinDir(filesDir)}/import-result.json`
}

// Same as XDG_DATA_HOME set by the native side.
export function pinyinUserDictPath(filesDir: string): string {
  return `${filesDir}/data/fcitx5/pinyin/user.dict`
}

export function pinyinHistoryPath(filesDir: string): string {
  return `${filesDir}/data/fcitx5/pinyin/user.history`
}

export function readText(path: string): string | null {
  try {
    if (!fs.accessSync(path)) {
      return null
    }
    return fs.readTextSync(path)
  } catch (e) {
    console.error(`Failed to read ${path}: ${e}`)
    return null
  }
}

export function writeText(path: string, text: string) {
  const dir = path.substring(0, path.lastIndexOf('/'))
  if (!fs.accessSync(dir)) {
    fs.mkdirSync(dir, true)
  }
  // Write then rename, so the other process never reads a partial file.
  const tmp = `${path}.tmp`
  const file = fs.openSync(tmp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
  try {
    fs.writeSync(file.fd, text)
  } finally {
    fs.closeSync(file)
  }
  fs.renameSync(tmp, path)
}

export function removeFile(path: string) {
  try {
    if (fs.accessSync(path)) {
      fs.unlinkSync(path)
    }
  } catch (e) {
    console.error(`Failed to remove ${path}: ${e}`)
  }
}

export function loadSettings(filesDir: string): KeyboardSettings {
  const text = readText(settingsPath(filesDir))
  const settings: KeyboardSettings = {
    theme: DEFAULT_SETTINGS.theme,
    keyBorder: DEFAULT_SETTINGS.keyBorder,
    vibrate: DEFAULT_SETTINGS.vibrate,
    vibrationStrength: DEFAULT_SETTINGS.vibrationStrength,
  }
  if (text === null) {
    return settings
  }
  try {
    const saved = JSON.parse(text) as KeyboardSettings
    if (saved.theme === 'system' || saved.theme === 'light' || saved.theme === 'dark') {
      settings.theme = saved.theme
    }
    if (typeof saved.keyBorder === 'boolean') {
      settings.keyBorder = saved.keyBorder
    }
    if (typeof saved.vibrate === 'boolean') {
      settings.vibrate = saved.vibrate
    }
    if (saved.vibrationStrength === 'light' || saved.vibrationStrength === 'medium' ||
      saved.vibrationStrength === 'heavy') {
      settings.vibrationStrength = saved.vibrationStrength
    }
  } catch (e) {
    console.error(`Invalid settings: ${e}`)
  }
  return settings
}

export function saveSettings(filesDir: string, settings: KeyboardSettings) {
  writeText(settingsPath(filesDir), JSON.stringify(settings))
}
