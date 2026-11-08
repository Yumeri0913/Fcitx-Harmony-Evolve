// files is the private files dir, shared the dir shared by the app and the input method.
// locale is like zh_CN.
export const init: (bundle: string, resfile: string, files: string, shared: string, locale: string) => void
export const setCallback: (callback: (data: string) => void) => void
export const focusIn: (clientPreedit: boolean) => void
export const focusOut: () => void

export interface InputContextState {
  commit: string
  preedit: string
  cursorPos: number
  accepted: boolean
}
export const processKey: (unicode: number, keyCode: number, isRelease: boolean) => InputContextState
export const reset: () => InputContextState
export const toggle: () => void
export const selectCandidate: (index: number) => void
export const askCandidateActions: (index: number) => void
export const activateCandidateAction: (index: number, id: number) => void
export const activateStatusAreaAction: (id: number) => void
export const setCurrentInputMethod: (inputMethod: string) => void
export const scroll: (start: number, count: number) => void
// Saving writes configs from memory, so it first reloads config changed by the settings page.
export const save: (shared: string) => void
export const reloadConfigIfChanged: (shared: string, force?: boolean) => void
// Quick phrase and unicode input, from the comma key menu.
export const triggerQuickPhrase: () => void
export const triggerUnicode: () => void
// Apply data files edited by the settings page in the shared dir.
export const syncDataIfChanged: (shared: string) => void
// Pinyin sub config actions, e.g. clearuserdict, clearalldict.
export const runPinyinAction: (action: string) => void
// Google Pinyin user words, lines of "word\tpin'yin\tcount".
// Returns "added existing invalid", or "" when pinyin is unavailable.
export const importGooglePinyinWords: (tsv: string) => string
// All pinyin user words, same format.
export const exportGooglePinyinWords: () => string

// Settings for the main app, which runs its own fcitx on the shared config dir.
export const initSettings: (bundle: string, resfile: string, files: string, shared: string, locale: string) => void
// uri: "global", "addon/<name>", "addon/<name>/<sub config>" or "im/<name>".
// Returns {cfg, desc} as RawConfig JSON ({name, value, subItems}), or "" if not configurable.
export const getConfig: (uri: string) => string
export const setConfig: (uri: string, value: string) => void
export const getAddons: () => string
export const setAddonState: (name: string, enabled: boolean) => void
export const availableInputMethods: () => string
export const enabledInputMethods: () => string
export const setEnabledInputMethods: (names: string) => void
// libime pinyin dictionary text <-> binary.
export const convertPinyinDict: (src: string, dest: string, toBinary: boolean) => boolean
// Words of saved pinyin user data files (e.g. from a backup), same format as exportGooglePinyinWords.
export const readPinyinUserWords: (dictPath: string, historyPath: string) => string
