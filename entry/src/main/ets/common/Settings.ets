// Keyboard settings and data files exchanged by the main app and the input method.
// The input method extension runs in its own sandbox, so its files dir differs from the
// app's. Both see the bundle's distributedFilesDir, which is passed as sharedDir here.
// Fcitx's own user data stays in the input method's private files dir.
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

function settingsPath(sharedDir: string): string {
  return `${sharedDir}/settings.json`
}

function googlePinyinDir(sharedDir: string): string {
  return `${sharedDir}/googlepinyin`
}

// Words waiting for the input method to merge them into the pinyin engine.
export function pendingImportPath(sharedDir: string): string {
  return `${googlePinyinDir(sharedDir)}/import.tsv`
}

// Lines of the Google Pinyin file skipped by the main app, merged into the result.
export function pendingSkippedPath(sharedDir: string): string {
  return `${googlePinyinDir(sharedDir)}/import-skipped`
}

export function importResultPath(sharedDir: string): string {
  return `${googlePinyinDir(sharedDir)}/import-result.json`
}

// User words written by the input method when the keyboard hides, for export.
export function userWordsSnapshotPath(sharedDir: string): string {
  return `${googlePinyinDir(sharedDir)}/user-words.tsv`
}

export function fileMtime(path: string): number {
  try {
    return fs.statSync(path).mtime
  } catch (e) {
    return 0
  }
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

export function loadSettings(sharedDir: string): KeyboardSettings {
  const text = readText(settingsPath(sharedDir))
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

export function saveSettings(sharedDir: string, settings: KeyboardSettings) {
  writeText(settingsPath(sharedDir), JSON.stringify(settings))
}
