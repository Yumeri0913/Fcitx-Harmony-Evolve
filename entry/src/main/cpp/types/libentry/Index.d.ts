// locale is like zh_CN.
export const init: (bundle: string, resfile: string, files: string, locale: string) => void
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
export const save: () => void
// Merge pinyin options written by the main app at path into fcitx's config and apply them.
export const applyPinyinConfig: (path: string) => void
// Google Pinyin user words, lines of "word\tpin'yin\tcount".
// Returns "added existing invalid", or "" when pinyin is unavailable.
export const importGooglePinyinWords: (tsv: string) => string
// All pinyin user words, same format.
export const exportGooglePinyinWords: () => string
