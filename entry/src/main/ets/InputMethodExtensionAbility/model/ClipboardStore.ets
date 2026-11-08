// Clipboard history like fcitx5-android's ClipboardManager. HarmonyOS only lets the
// keyboard read the system clipboard through the paste button, so entries come from that
// and from copy or cut in the keyboard's editing panel.
import { readText, writeText } from '../../common/Settings'

export interface ClipboardEntry {
  id: number
  text: string
  pinned: boolean
  time: number
}

// Unpinned entries kept, fcitx5-android's default clipboard_limit.
const LIMIT = 10

export class ClipboardStore {
  private path = ''
  private entries: ClipboardEntry[] = []
  private nextId = 1

  load(filesDir: string) {
    this.path = `${filesDir}/clipboard.json`
    const text = readText(this.path)
    if (text === null) {
      return
    }
    try {
      this.entries = JSON.parse(text) as ClipboardEntry[]
      this.nextId = this.entries.reduce((max: number, e: ClipboardEntry) => Math.max(max, e.id), 0) + 1
    } catch (e) {
      console.error(`Invalid clipboard history: ${e}`)
      this.entries = []
    }
  }

  // Newest first.
  list(): ClipboardEntry[] {
    return this.entries
  }

  add(text: string) {
    if (!text.trim()) {
      return
    }
    const existing = this.entries.find((e: ClipboardEntry) => e.text === text)
    const pinned = existing ? existing.pinned : false
    this.entries = this.entries.filter((e: ClipboardEntry) => e.text !== text)
    this.entries.unshift({ id: this.nextId++, text: text, pinned: pinned, time: Date.now() })
    let unpinned = 0
    this.entries = this.entries.filter((e: ClipboardEntry) => e.pinned || ++unpinned <= LIMIT)
    this.save()
  }

  pin(id: number, pinned: boolean) {
    for (const e of this.entries) {
      if (e.id === id) {
        e.pinned = pinned
      }
    }
    this.save()
  }

  remove(id: number) {
    this.entries = this.entries.filter((e: ClipboardEntry) => e.id !== id)
    this.save()
  }

  // Pinned entries stay, like fcitx5-android's delete all.
  clear() {
    this.entries = this.entries.filter((e: ClipboardEntry) => e.pinned)
    this.save()
  }

  private save() {
    try {
      writeText(this.path, JSON.stringify(this.entries))
    } catch (e) {
      console.error(`Failed to save clipboard history: ${e}`)
    }
  }
}
