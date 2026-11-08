// Sogou cell dictionary (.scel) to libime text dictionary ("word pin'yin 0" lines), in
// place of fcitx5-android's scel2org5 binary, which an app can't run on HarmonyOS.
//
// Layout: UTF-16LE strings; the pinyin table at 0x1540 (4 byte header, then index, length
// and syllable entries), words from 0x2628: a homophone count, the pinyin index list, then
// each word with its extra data.

const PINYIN_TABLE = 0x1540
const WORDS = 0x2628

function utf16(bytes: Uint8Array, start: number, length: number): string {
  let text = ''
  for (let i = start; i + 1 < start + length; i += 2) {
    text += String.fromCharCode(bytes[i] | (bytes[i + 1] << 8))
  }
  return text
}

export interface ScelResult {
  // libime text dictionary.
  text: string
  words: number
}

export function scelToText(bytes: Uint8Array): ScelResult {
  if (bytes.length < WORDS) {
    throw new Error('Not a Sogou cell dictionary')
  }
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
  const pinyin = new Map<number, string>()
  let pos = PINYIN_TABLE + 4
  while (pos + 4 <= WORDS) {
    const index = view.getUint16(pos, true)
    const length = view.getUint16(pos + 2, true)
    pos += 4
    if (length === 0 || pos + length > WORDS) {
      break
    }
    pinyin.set(index, utf16(bytes, pos, length))
    pos += length
  }

  const lines: string[] = []
  pos = WORDS
  while (pos + 4 <= bytes.length) {
    const homophones = view.getUint16(pos, true)
    const pinyinBytes = view.getUint16(pos + 2, true)
    pos += 4
    const syllables: string[] = []
    for (let i = 0; i + 1 < pinyinBytes; i += 2) {
      syllables.push(pinyin.get(view.getUint16(pos + i, true)) ?? '')
    }
    pos += pinyinBytes
    for (let h = 0; h < homophones && pos + 2 <= bytes.length; h++) {
      const wordBytes = view.getUint16(pos, true)
      pos += 2
      const word = utf16(bytes, pos, wordBytes)
      pos += wordBytes
      if (pos + 2 > bytes.length) {
        break
      }
      const extraBytes = view.getUint16(pos, true)
      pos += 2 + extraBytes
      if (word && syllables.length > 0 && syllables.every((s: string) => /^[a-z]+$/.test(s))) {
        lines.push(`${word} ${syllables.join('\'')} 0`)
      }
    }
  }
  return { text: lines.join('\n') + '\n', words: lines.length }
}
