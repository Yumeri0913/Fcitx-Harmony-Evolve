// Keyboard settings and data files exchanged by the main app and the input method.
// The input method extension runs in its own sandbox, so its files dir differs from the
// app's. Both see the bundle's distributedFilesDir, which is passed as sharedDir here.
// Fcitx's own user data stays in the input method's private files dir.
import { fileIo as fs } from '@kit.CoreFileKit'

export type ThemeMode = 'system' | 'light' | 'dark'
// Google Pinyin's vibration strengths, mapped to system haptic presets.
export type VibrationStrength = 'light' | 'medium' | 'heavy'

// fcitx5-android (InsightKey fork) KeyboardHeightMode.
export type HeightMode = 'googlepinyin' | 'percent'

export interface KeyboardSettings {
  theme: ThemeMode
  // Google Pinyin 按键边框. Off by default like Google Pinyin and fcitx5-android.
  keyBorder: boolean
  vibrate: boolean
  vibrationStrength: VibrationStrength
  heightMode: HeightMode
  // Percent of the screen height for the keys, in percent mode.
  heightPercentPortrait: number
  heightPercentLandscape: number
  // vp, fcitx5-android's key margins and radius.
  keyMarginX: number
  // Google Pinyin leaves twice this below each key: 10 vp portrait, 4 vp landscape.
  keyMarginY: number
  keyMarginYLandscape: number
  keyRadius: number
  popupOnKeyPress: boolean
  keySound: boolean
  // 0 to 100.
  keySoundVolume: number
  // LAN clipboard sync of fcitx5-android (InsightKey fork). Off by default: it serves the
  // clipboard history to the local network.
  clipboardSync: boolean
  // Google Pinyin's 输入法 and 键盘 settings, see QuickSettingsPage.
  doubleSpacePeriod: boolean
  spaceSwipeMoveCursor: boolean
  // 90 to 110, percent of Google Pinyin's height.
  heightRatio: number
  // Swipe distance multiplier: 3, 1.5, 1, 0.8 or 0.5.
  slideSensitivity: number
  // ms, 100 to 700.
  longPressDelay: number
  // Bumped when defaults change, to migrate saved settings that kept old defaults.
  version?: number
}

const SETTINGS_VERSION = 2

export const DEFAULT_SETTINGS: KeyboardSettings = {
  theme: 'system',
  keyBorder: false,
  vibrate: true,
  vibrationStrength: 'light',
  heightMode: 'googlepinyin',
  heightPercentPortrait: 27,
  heightPercentLandscape: 49,
  keyMarginX: 3,
  keyMarginY: 5,
  keyMarginYLandscape: 2,
  keyRadius: 2,
  popupOnKeyPress: true,
  keySound: false,
  keySoundVolume: 50,
  clipboardSync: false,
  doubleSpacePeriod: true,
  spaceSwipeMoveCursor: true,
  heightRatio: 100,
  slideSensitivity: 1,
  longPressDelay: 300,
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

// Pinyin actions (e.g. clearuserdict) queued by the settings page, a JSON string array.
export function pendingPinyinActionsPath(sharedDir: string): string {
  return `${sharedDir}/requests/pinyin-actions.json`
}

// Mirror of fcitx's user data dir for files the settings page edits, see syncDataIfChanged.
export function sharedDataPath(sharedDir: string, relative: string): string {
  return `${sharedDir}/data/fcitx5/${relative}`
}

// Random id announced by LAN clipboard sync, shared so both processes use the same.
export function clipboardSyncId(sharedDir: string): string {
  const path = `${sharedDir}/clipboard-sync-id`
  let id = readText(path)
  if (!id) {
    id = `harmony-${Math.random().toString(16).substring(2, 10)}${Date.now().toString(16)}`
    writeText(path, id)
  }
  return id
}

// Written by the input method when a LAN client connects, which ends pairing.
export function clipboardSyncAccessPath(sharedDir: string): string {
  return `${sharedDir}/clipboard-sync-access`
}

// Copies of the input method's pinyin user.dict and user.history, for backups.
export function userDataCopyPath(sharedDir: string, file: string): string {
  return `${sharedDir}/userdata/pinyin/${file}`
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

function numberIn(value: number, min: number, max: number, fallback: number): number {
  return typeof value === 'number' && value >= min && value <= max ? value : fallback
}

export function loadSettings(sharedDir: string): KeyboardSettings {
  const text = readText(settingsPath(sharedDir))
  const d = DEFAULT_SETTINGS
  const settings: KeyboardSettings = {
    theme: d.theme,
    keyBorder: d.keyBorder,
    vibrate: d.vibrate,
    vibrationStrength: d.vibrationStrength,
    heightMode: d.heightMode,
    heightPercentPortrait: d.heightPercentPortrait,
    heightPercentLandscape: d.heightPercentLandscape,
    keyMarginX: d.keyMarginX,
    keyMarginY: d.keyMarginY,
    keyMarginYLandscape: d.keyMarginYLandscape,
    keyRadius: d.keyRadius,
    popupOnKeyPress: d.popupOnKeyPress,
    keySound: d.keySound,
    keySoundVolume: d.keySoundVolume,
    clipboardSync: d.clipboardSync,
    doubleSpacePeriod: d.doubleSpacePeriod,
    spaceSwipeMoveCursor: d.spaceSwipeMoveCursor,
    heightRatio: d.heightRatio,
    slideSensitivity: d.slideSensitivity,
    longPressDelay: d.longPressDelay,
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
    if (saved.heightMode === 'googlepinyin' || saved.heightMode === 'percent') {
      settings.heightMode = saved.heightMode
    }
    settings.heightPercentPortrait = numberIn(saved.heightPercentPortrait, 10, 90, d.heightPercentPortrait)
    settings.heightPercentLandscape = numberIn(saved.heightPercentLandscape, 10, 90, d.heightPercentLandscape)
    settings.keyMarginX = numberIn(saved.keyMarginX, 0, 24, d.keyMarginX)
    settings.keyMarginY = numberIn(saved.keyMarginY, 0, 24, d.keyMarginY)
    // 7 was the default before keys were drawn at the top of their cell like Google Pinyin.
    if ((saved.version ?? 1) < 2 && settings.keyMarginY === 7) {
      settings.keyMarginY = d.keyMarginY
    }
    settings.keyMarginYLandscape = numberIn(saved.keyMarginYLandscape, 0, 24, d.keyMarginYLandscape)
    settings.keyRadius = numberIn(saved.keyRadius, 0, 48, d.keyRadius)
    settings.keySoundVolume = numberIn(saved.keySoundVolume, 0, 100, d.keySoundVolume)
    if (typeof saved.popupOnKeyPress === 'boolean') {
      settings.popupOnKeyPress = saved.popupOnKeyPress
    }
    if (typeof saved.keySound === 'boolean') {
      settings.keySound = saved.keySound
    }
    if (typeof saved.clipboardSync === 'boolean') {
      settings.clipboardSync = saved.clipboardSync
    }
    if (typeof saved.doubleSpacePeriod === 'boolean') {
      settings.doubleSpacePeriod = saved.doubleSpacePeriod
    }
    if (typeof saved.spaceSwipeMoveCursor === 'boolean') {
      settings.spaceSwipeMoveCursor = saved.spaceSwipeMoveCursor
    }
    settings.heightRatio = numberIn(saved.heightRatio, 90, 110, d.heightRatio)
    settings.slideSensitivity = numberIn(saved.slideSensitivity, 0.5, 3, d.slideSensitivity)
    settings.longPressDelay = numberIn(saved.longPressDelay, 100, 700, d.longPressDelay)
  } catch (e) {
    console.error(`Invalid settings: ${e}`)
  }
  return settings
}

export function saveSettings(sharedDir: string, settings: KeyboardSettings) {
  settings.version = SETTINGS_VERSION
  writeText(settingsPath(sharedDir), JSON.stringify(settings))
}
