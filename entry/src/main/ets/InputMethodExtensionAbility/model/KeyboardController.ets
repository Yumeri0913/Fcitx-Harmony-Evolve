import { webview } from '@kit.ArkWeb';
import type { InputMethodExtensionContext } from '@kit.IMEKit';
import { inputMethodEngine } from '@kit.IMEKit';
import { display } from '@kit.ArkUI';
import { KeyCode } from '@kit.InputKit';
import { vibrator } from '@kit.SensorServiceKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { KeySound } from './KeySound';
import { ClipboardSync } from './ClipboardSync';
import { deviceInfo } from '@kit.BasicServicesKit';
import {
  ClipboardEntry as WebClipboardEntry, SystemEvent, VirtualKeyboardEvent
} from '../../../fcitx5-keyboard-web/src/api';
import { ClipboardEntry, ClipboardStore } from './ClipboardStore';
import fcitx, { InputContextState } from 'libentry.so';
import { FcitxEvent } from './FcitxEvent';
import { ensureDir } from '../../common/Files';
import { convertCode } from './keycode';
import { onTextChange, redo, resetStacks, undo } from './TextOperation';
import {
  ImportResult, KeyboardSettings, loadSettings, importResultPath, pendingImportPath, pendingPinyinActionsPath,
  pendingSkippedPath, pendingTypedPath, pendingEnglishPath, englishSnapshotPath,
  readText, removeFile, userDataCopyPath, userWordsSnapshotPath, writeText, clipboardSyncId, clipboardSyncAccessPath
} from '../../common/Settings';

// Writing the user words snapshot reads all of history, so not on every hide.
const SNAPSHOT_INTERVAL = 60 * 1000

// Google Pinyin 4.x keyboard_body_height in vp (from its 4.5.2 dimens.xml): the key area
// below its 40 vp candidate bar, by smallest screen width bucket. Same as fcitx5-android
// (InsightKey fork) KeyboardHeightMode and the fcitx5-ios uipanel.
const BAR_HEIGHT = 40

function googlePinyinBodyHeight(smallestScreenWidth: number, landscape: boolean): number {
  if (landscape) {
    if (smallestScreenWidth >= 768) {
      return 328
    }
    if (smallestScreenWidth >= 600) {
      return 241
    }
    if (smallestScreenWidth >= 400) {
      return 176
    }
    return 162
  }
  if (smallestScreenWidth >= 600) {
    return 287
  }
  if (smallestScreenWidth >= 400) {
    return 242
  }
  return 209
}

const hapticEffects: Record<string, vibrator.HapticFeedback> = {
  'light': vibrator.HapticFeedback.EFFECT_SOFT,
  'medium': vibrator.HapticFeedback.EFFECT_HARD,
  'heavy': vibrator.HapticFeedback.EFFECT_SHARP,
}

// Fallback for devices without haptic presets.
const hapticDurations: Record<string, number> = {
  'light': 10,
  'medium': 20,
  'heavy': 30,
}

// A synchronous call to the editor that takes this long means it answers slowly or never.
const SLOW_EDITOR_MS = 1000
// Editors whose synchronous calls timed out, by bundle name, for the life of the process.
const slowEditors = new Set<string>()

// Errors from the editor (it lost focus, or timed out) must not kill the keyboard.
function guard(name: string, action: () => void): void {
  try {
    action()
  } catch (e) {
    console.error(`${name} failed: ${e}`)
  }
}

const ability: inputMethodEngine.InputMethodAbility = inputMethodEngine.getInputMethodAbility();
const keyboardDelegate = inputMethodEngine.getKeyboardDelegate() // Physical keyboard

export class KeyboardController {
  private ctx: InputMethodExtensionContext | undefined = undefined;
  private panel: inputMethodEngine.Panel | undefined = undefined;
  private attribute: inputMethodEngine.EditorAttribute | null = null
  private port: webview.WebMessagePort | null = null
  private textInputClient: inputMethodEngine.InputClient | undefined = undefined;
  private keyboardController: inputMethodEngine.KeyboardController | undefined = undefined;
  private initialized = false
  private initRetries = 0
  // Android apps in 卓易通 answer synchronous calls through the container's broker, which
  // times out after 3 s and throws. Text goes in with asynchronous calls there.
  private asyncEditor = false
  // Virtual keyboard states
  private hasCandidates = false
  private hasPreeditOrAux = false
  // Textarea states
  private preedit = ''
  private preeditIndex = 0 // Bad initial value that must be reset on focus.
  private textWithPreedit = ''
  private selectionStart = 0
  private selectionEnd = 0
  private selecting = false
  private backspaceSelectionCount = 0
  private pendingEvents: SystemEvent[] = []
  // Shared with the main app, see Settings.ets.
  private sharedDir = ''
  // For the status area's input method options.
  private currentInputMethod = ''
  private settings: KeyboardSettings | null = null
  private hapticPresetSupported = true
  private lastSnapshotTime = 0
  private clipboard = new ClipboardStore()
  private keySound = new KeySound()
  private clipboardSync: ClipboardSync | null = null
  private panelHeight = 0
  private filesDir = ''

  constructor() {
  }

  public onCreate(context: InputMethodExtensionContext): void {
    console.debug("onCreate")
    fcitx.setCallback((data: string) => {
      this.processAsyncData(data)
    })
    this.ctx = context;
    this.sharedDir = context.distributedFilesDir
    this.clipboard.load(context.filesDir)
    this.filesDir = context.filesDir
    this.loadSettings()
    this.initWindow();
    this.registerListener();
  }

  public onDestroy(): void {
    console.debug("onDestroy")
    this.unRegisterListener();
    if (this.panel) {
      ability.destroyPanel(this.panel);
    }
    if (this.ctx) {
      this.ctx.destroy();
    }
  }

  public setPort(port: webview.WebMessagePort) {
    this.port = port
    for (const event of this.pendingEvents) {
      this.sendEvent(event)
    }
    this.pendingEvents = []
  }

  private sendEvent(event: SystemEvent) {
    if (this.port) {
      this.port?.postMessageEvent(JSON.stringify(event))
    } else {
      this.pendingEvents.push(event)
    }
  }

  private processAsyncData(data: string) {
    guard('processAsyncData', () => this.handleAsyncData(data))
  }

  private handleAsyncData(data: string): void {
    console.debug(`processing data: ${data}`)
    const event = JSON.parse(data) as SystemEvent | FcitxEvent
    switch (event.type) {
      case 'COMMIT':
        if (event.data) {
          this.commitString(event.data)
        }
        break
      case 'CLIENT_PREEDIT':
        this.updatePreviewText(event.data.preedit, event.data.cursorPos)
        break
      case 'CLEAR':
        this.hasCandidates = false
        this.hasPreeditOrAux = false
        this.sendEvent(event)
        break
      case 'CANDIDATES':
        this.hasCandidates = true
        this.sendEvent(event)
        break
      case 'PREEDIT':
        this.hasPreeditOrAux = event.data.auxUp !== '' || event.data.preedit !== ''
        this.sendEvent(event)
        break
      case 'INPUT_METHODS':
        this.currentInputMethod = event.data.currentInputMethod
        this.sendEvent(event)
        break
      default:
        this.sendEvent(event)
        break
    }
  }

  private enterKeyLabelMapping: Map<number, string> = new Map([
    [inputMethodEngine.ENTER_KEY_TYPE_UNSPECIFIED, ''],
    [inputMethodEngine.ENTER_KEY_TYPE_GO, 'go'],
    [inputMethodEngine.ENTER_KEY_TYPE_SEARCH, 'search'],
    [inputMethodEngine.ENTER_KEY_TYPE_SEND, 'send'],
    [inputMethodEngine.ENTER_KEY_TYPE_NEXT, 'next'],
    [inputMethodEngine.ENTER_KEY_TYPE_DONE, 'done'],
    [inputMethodEngine.ENTER_KEY_TYPE_PREVIOUS, 'previous'],
    [inputMethodEngine.ENTER_KEY_TYPE_NEWLINE, 'newline'],
  ])

  public setEnterKeyType() {
    const type = this.attribute?.enterKeyType ?? 0
    const label: string = this.enterKeyLabelMapping[type]
    this.sendEvent({ type: 'ENTER_KEY_TYPE', data: label })
  }

  public setUndo(enabled: boolean) {
    this.sendEvent({ type: 'UNDO', data: enabled })
  }

  public setRedo(enabled: boolean) {
    this.sendEvent({ type: 'REDO', data: enabled })
  }

  private getTextBefore() {
    if (!this.textInputClient) {
      return ''
    }
    return this.textInputClient.getForwardSync(this.textInputClient.getTextIndexAtCursorSync())
  }

  private getTextAfter() {
    if (!this.textInputClient) {
      return ''
    }
    let step = 1024
    while (true) {
      const text = this.textInputClient.getBackwardSync(step)
      if (text.length < step) {
        return text
      }
      step *= 2
    }
  }

  private commitString(text: string): void {
    if (this.preedit === text) {
      // System won't emit textChange, and the textChange for preedit was blocked.
      // So we call onTextChange manually.
      onTextChange(this.textWithPreedit)
    }
    this.updatePreviewText('')
    this.insertText(text)
    this.preedit = ''
    if (!this.asyncEditor) {
      this.preeditIndex = this.textInputClient?.getTextIndexAtCursorSync() ?? -1
    }
  }

  private updatePreviewText(text: string, cursorPos: number = 0) {
    let start = this.preeditIndex
    let end = start + this.preedit.length
    if (this.preedit || text) {
      try {
        this.textInputClient?.setPreviewTextSync(text, { start, end })
      } catch (e) {
        // There is selection.
        this.deleteForward(1)
        start = this.textInputClient!.getTextIndexAtCursorSync()
        end = start
        this.textInputClient?.setPreviewTextSync(text, { start, end })
      }
      for (let i = 0; i < text.length - cursorPos; ++i) {
        this.textInputClient?.moveCursorSync(inputMethodEngine.Direction.CURSOR_LEFT)
      }
      if (!text) {
        this.textInputClient?.finishTextPreviewSync()
      }
    }
    this.preedit = text
  }

  private processResult(res: InputContextState): boolean {
    if (!res.accepted) {
      return false
    }
    if (res.commit) {
      this.commitString(res.commit)
    }
    this.updatePreviewText(res.preedit, res.cursorPos)
    return true
  }

  private move(direction: inputMethodEngine.Direction) {
    if (this.selecting) {
      this.textInputClient?.selectByMovementSync({ direction })
    } else {
      this.textInputClient?.moveCursorSync(direction)
    }
  }

  private moveWithinLine(destination: 'home' | 'end') {
    const before = this.getTextBefore()
    if (destination === 'home') {
      const index = before.lastIndexOf('\n') + 1 // works for first line as well
      if (this.selecting) {
        this.textInputClient?.selectByRangeSync({ start: index, end: this.textInputClient.getTextIndexAtCursorSync() })
      } else {
        for (let i = before.length; i > index; --i) {
          this.textInputClient?.moveCursorSync(inputMethodEngine.Direction.CURSOR_LEFT)
        }
      }
    } else {
      const after = this.getTextAfter()
      let offset = after.indexOf('\n')
      if (offset === -1) { // last line
        offset = after.length
      }
      if (this.selecting) {
        this.textInputClient?.selectByRangeSync({
          start: this.selectionStart,
          end: this.textInputClient.getTextIndexAtCursorSync() + offset
        })
      } else {
        for (let i = 0; i < offset; ++i) {
          this.textInputClient?.moveCursorSync(inputMethodEngine.Direction.CURSOR_RIGHT)
        }
      }
    }
  }

  private setCursor(index: number) {
    if (index) {
      // 2 steps so that 📍 won't be shown.
      this.textInputClient?.selectByRangeSync({ start: index - 1, end: index - 1 })
      this.textInputClient?.moveCursorSync(inputMethodEngine.Direction.CURSOR_RIGHT)
    } else {
      this.textInputClient?.selectByRangeSync({ start: 0, end: 0 })
      this.textInputClient?.moveCursorSync(inputMethodEngine.Direction.CURSOR_LEFT)
    }
  }

  private handleBackspaceSlide(direction: 'LEFT' | 'RIGHT' | 'RELEASE') {
    if (this.preedit || this.hasCandidates || this.hasPreeditOrAux) {
      if (direction === 'RELEASE') {
        this.processResult(fcitx.reset())
      }
      return
    }
    if (!this.textInputClient) { // Only to make ArkTS happy.
      return
    }
    switch (direction) {
      case 'LEFT':
        if (this.backspaceSelectionCount < this.selectionStart) {
          ++this.backspaceSelectionCount
          this.textInputClient.selectByMovementSync({ direction: inputMethodEngine.Direction.CURSOR_LEFT })
        }
        break
      case 'RIGHT':
        if (this.backspaceSelectionCount > 0) {
          --this.backspaceSelectionCount
          this.textInputClient.selectByMovementSync({ direction: inputMethodEngine.Direction.CURSOR_RIGHT })
        }
        break
      case 'RELEASE':
        if (this.backspaceSelectionCount) {
          this.deleteForward(1)
          this.backspaceSelectionCount = 0
        }
        break
    }
  }

  // Google Pinyin: two quick spaces after a letter, digit or Chinese character become a period,
  // "。" in Chinese input methods and ". " otherwise, like fcitx5-android (InsightKey fork).
  private lastSpaceTime = 0

  private maybeDoubleSpacePeriod(): boolean {
    const now = Date.now()
    const previous = this.lastSpaceTime
    this.lastSpaceTime = now
    if (!this.settings?.doubleSpacePeriod || this.hasPreeditOrAux || now - previous > 300 || this.asyncEditor) {
      return false
    }
    const before = this.textInputClient?.getForwardSync(2) ?? ''
    if (before.length !== 2 || before[1] !== ' ' || !/[\p{L}\p{N}]/u.test(before[0])) {
      return false
    }
    this.lastSpaceTime = 0
    this.textInputClient?.deleteForwardSync(1)
    this.insertText(this.currentInputMethod.startsWith('keyboard-') ? '. ' : '。')
    return true
  }

  // alternatives: see processKey in libentry.
  public handleKey(key: string, keyCode?: number, alternatives?: string): void {
    if (key === ' ' && this.maybeDoubleSpacePeriod()) {
      return
    }
    if (key !== ' ') {
      this.lastSpaceTime = 0
    }
    const res = fcitx.processKey(key ? key.charCodeAt(0) : 0, keyCode ?? 0, false, alternatives ?? '')
    if (!this.processResult(res)) {
      switch (keyCode) { // Check code first as enter has to be handled differently, which has key \r.
        case KeyCode.KEYCODE_DEL:
          return this.deleteForward(1)
        case KeyCode.KEYCODE_DPAD_DOWN:
          return this.move(inputMethodEngine.Direction.CURSOR_DOWN)
        case KeyCode.KEYCODE_DPAD_LEFT:
          return this.move(inputMethodEngine.Direction.CURSOR_LEFT)
        case KeyCode.KEYCODE_DPAD_RIGHT:
          return this.move(inputMethodEngine.Direction.CURSOR_RIGHT)
        case KeyCode.KEYCODE_DPAD_UP:
          return this.move(inputMethodEngine.Direction.CURSOR_UP)
        case KeyCode.KEYCODE_MOVE_END:
          return this.moveWithinLine('end')
        case KeyCode.KEYCODE_ENTER:
          this.textInputClient?.sendKeyFunction(this.attribute?.enterKeyType)
          break
        case KeyCode.KEYCODE_MOVE_HOME:
          return this.moveWithinLine('home')
        default:
          if (key) {
            this.insertText(key)
          }
      }
    }
  }

  public handleVirtualKeyboardEvent(event: VirtualKeyboardEvent): void | Promise<void> {
    switch (event.type) {
      case 'ASK_CANDIDATE_ACTIONS':
        return fcitx.askCandidateActions(event.data)
      case 'BACKSPACE_SLIDE':
        return this.handleBackspaceSlide(event.data)
      case 'CANDIDATE_ACTION':
        return fcitx.activateCandidateAction(event.data.index, event.data.id);
      case 'COLLAPSE':
        return this.panel?.hide()
      case 'COMMIT':
        this.processResult(fcitx.reset())
        return this.insertText(event.data)
      case 'COPY':
        this.recordSelection()
        return this.textInputClient?.sendExtendAction(inputMethodEngine.ExtendAction.COPY)
      case 'CUT':
        this.recordSelection()
        return this.textInputClient?.sendExtendAction(inputMethodEngine.ExtendAction.CUT)
      case 'CLIPBOARD_SHOW':
        AppStorage.setOrCreate('clipboardPasteVisible', true)
        return this.sendClipboard()
      case 'CLIPBOARD_HIDE':
        AppStorage.setOrCreate('clipboardPasteVisible', false)
        return
      case 'CLIPBOARD_PIN':
        this.clipboard.pin(event.data.id, event.data.pinned)
        return this.sendClipboard()
      case 'CLIPBOARD_DELETE':
        this.clipboard.remove(event.data)
        return this.sendClipboard()
      case 'CLIPBOARD_CLEAR':
        this.clipboard.clear()
        return this.sendClipboard()
      case 'RELOAD_CONFIG':
        fcitx.reloadConfigIfChanged(this.sharedDir, true)
        fcitx.syncDataIfChanged(this.sharedDir)
        return
      case 'OPEN_SETTINGS':
        return this.openSettings(event.data)
      case 'QUICKPHRASE':
        return fcitx.triggerQuickPhrase()
      case 'UNICODE':
        return fcitx.triggerUnicode()
      case 'DESELECT':
        this.selecting = false
        this.setCursor(this.textInputClient?.getTextIndexAtCursorSync() ?? 0)
        break
      case 'GLOBE':
        return fcitx.toggle()
      case 'HAPTIC':
        return this.vibrate()
      case 'KEY_DOWN':
        return this.handleKey(event.data.key, convertCode(event.data.code), event.data.alternatives)
      case 'PASTE':
        return this.textInputClient?.sendExtendAction(inputMethodEngine.ExtendAction.PASTE)
      case 'REDO':
        return redo(this.textInputClient!)
      case 'SCROLL':
        return fcitx.scroll(event.data.start, event.data.count)
      case 'SELECT':
        this.selecting = true
        break
      case 'SELECT_ALL':
        this.selecting = true
        this.textInputClient?.sendExtendAction(inputMethodEngine.ExtendAction.SELECT_ALL)
        break
      case 'SELECT_CANDIDATE':
        return fcitx.selectCandidate(event.data)
      case 'SET_INPUT_METHOD':
        return fcitx.setCurrentInputMethod(event.data)
      case 'STATUS_AREA_ACTION':
        return fcitx.activateStatusAreaAction(event.data)
      case 'UNDO':
        return undo(this.textInputClient!)
    }
  }

  // The settings app, on a page for the status area and the toolbar's theme button.
  private openSettings(page: string) {
    this.ctx?.startAbility({
      bundleName: this.ctx.applicationInfo.name,
      abilityName: 'EntryAbility',
      parameters: { page: page, inputMethod: this.currentInputMethod },
    }).catch((e: Error) => console.error(`Failed to open settings: ${e.message}`))
  }

  public insertText(text: string): void {
    const client = this.textInputClient
    if (!client) {
      return
    }
    if (this.asyncEditor) {
      client.insertText(text).catch((e: Error) => console.error(`insertText failed: ${e.message}`))
      return
    }
    this.callEditor('insertText', () => client.insertTextSync(text))
  }

  public deleteForward(length: number): void {
    const client = this.textInputClient
    if (!client) {
      return
    }
    if (this.asyncEditor) {
      client.deleteForward(length).catch((e: Error) => console.error(`deleteForward failed: ${e.message}`))
      return
    }
    this.callEditor('deleteForward', () => client.deleteForwardSync(length))
  }

  // Not retried: a timed out call may still reach the editor later.
  private callEditor(name: string, action: () => void): void {
    const start = Date.now()
    try {
      action()
    } catch (e) {
      console.error(`${name} failed: ${e}`)
      if (Date.now() - start >= SLOW_EDITOR_MS) {
        slowEditors.add(this.attribute?.bundleName ?? '')
        this.asyncEditor = true
      }
    }
  }

  private initWindow(): void {
    if (this.ctx === undefined) {
      return;
    }
    // 1260x2720 on emulator
    let panelInfo: inputMethodEngine.PanelInfo = {
      type: inputMethodEngine.PanelType.SOFT_KEYBOARD,
      flag: inputMethodEngine.PanelFlag.FLG_FIXED
    };
    ability.createPanel(this.ctx, panelInfo).then((inputPanel: inputMethodEngine.Panel) => {
      this.panel = inputPanel;
      this.panel.on('show', () => {
        console.debug('show')
        // Settings may have been changed in the main app.
        this.loadSettings()
        this.resizePanel()
        fcitx.reloadConfigIfChanged(this.sharedDir)
        fcitx.syncDataIfChanged(this.sharedDir)
        this.runPendingPinyinActions()
        this.applyPendingImport()
      })
      this.panel.on('hide', () => {
        console.debug('hide')
        // Need it when dragging right edge to collapse keyboard. The editor may be gone.
        guard('reset', () => this.processResult(fcitx.reset()))
        this.sendEvent({ type: 'HIDE' })
        // Persist learned words now instead of waiting for the periodic save, like
        // fcitx5-android. Config changed by the settings page is reloaded first.
        fcitx.save(this.sharedDir)
        this.writeUserWordsSnapshot(false)
      })
      this.resizePanel()
      this.panel.setUiContent('InputMethodExtensionAbility/pages/VirtualKeyboard')
    })
  }

  private sendClipboard() {
    const entries: WebClipboardEntry[] = this.clipboard.list().map((e: ClipboardEntry): WebClipboardEntry => ({
      id: e.id,
      text: e.text,
      pinned: e.pinned,
    }))
    this.sendEvent({ type: 'CLIPBOARD', data: entries })
  }

  // The selected text, for the clipboard history: HarmonyOS doesn't let the keyboard
  // read what the app copies.
  private recordSelection() {
    if (this.selectionStart === this.selectionEnd) {
      return
    }
    // With a selection, getForward and getBackward return the text around it, not in it,
    // so take it from the editor text tracked by textChange.
    const start = Math.min(this.selectionStart, this.selectionEnd)
    const end = Math.max(this.selectionStart, this.selectionEnd)
    this.clipboard.add(this.textWithPreedit.substring(start, end))
  }

  // Text read by the system paste button: paste it and keep it in the history.
  public pasteFromSystem(text: string) {
    if (!text) {
      return
    }
    this.clipboard.add(text)
    this.processResult(fcitx.reset())
    this.insertText(text)
    this.sendClipboard()
  }

  private loadSettings() {
    const settings = loadSettings(this.sharedDir)
    this.settings = settings
    if (settings.keySound) {
      this.keySound.init(this.filesDir)
    }
    this.updateClipboardSync(settings.clipboardSync)
    this.sendEvent({
      type: 'CONFIG', data: {
        theme: settings.theme,
        keyBorder: settings.keyBorder,
        keyMarginX: settings.keyMarginX,
        keyMarginY: this.isLandscape() ? settings.keyMarginYLandscape : settings.keyMarginY,
        keyRadius: settings.keyRadius,
        popupOnKeyPress: settings.popupOnKeyPress,
        spaceSwipeMoveCursor: settings.spaceSwipeMoveCursor,
        slideSensitivity: settings.slideSensitivity,
        longPressDelay: settings.longPressDelay,
        mmPerPxX: this.mmPerPx(true),
        mmPerPxY: this.mmPerPx(false),
      }
    })
  }

  // Millimeters per web (CSS) pixel, one vp, for the keyboard's touch spatial model.
  private mmPerPx(horizontal: boolean): number {
    try {
      const d = display.getDefaultDisplaySync()
      const dpi = horizontal ? d.xDPI : d.yDPI
      return dpi > 0 ? 25.4 * d.densityPixels / dpi : 0
    } catch (e) {
      return 0
    }
  }

  private updateClipboardSync(enabled: boolean) {
    if (enabled && !this.clipboardSync) {
      try {
        this.clipboardSync = new ClipboardSync(this.clipboard, clipboardSyncId(this.sharedDir),
          deviceInfo.marketName || deviceInfo.productModel, (): void => this.sendClipboard(), (): void => {
            writeText(clipboardSyncAccessPath(this.sharedDir), `${Date.now()}`)
          })
        this.clipboardSync.start()
      } catch (e) {
        console.error(`Failed to start clipboard sync: ${e}`)
      }
    } else if (!enabled && this.clipboardSync) {
      this.clipboardSync.stop()
      this.clipboardSync = null
    }
  }

  private isLandscape(): boolean {
    const defaultDisplay = display.getDefaultDisplaySync()
    return defaultDisplay.width > defaultDisplay.height
  }

  // Google Pinyin's height or a percentage of the screen, like fcitx5-android (InsightKey).
  private resizePanel() {
    if (!this.panel) {
      return
    }
    const defaultDisplay = display.getDefaultDisplaySync()
    const width = defaultDisplay.width
    const height = defaultDisplay.height
    const density = defaultDisplay.densityPixels
    const landscape = width > height
    const settings = this.settings
    let bodyHeight: number
    if (settings && settings.heightMode === 'percent') {
      const percent = landscape ? settings.heightPercentLandscape : settings.heightPercentPortrait
      bodyHeight = height / density * percent / 100
    } else {
      bodyHeight = googlePinyinBodyHeight(Math.min(width, height) / density, landscape) *
        (settings ? settings.heightRatio : 100) / 100
    }
    const panelHeight = Math.round((bodyHeight + BAR_HEIGHT) * density)
    if (panelHeight !== this.panelHeight) {
      this.panelHeight = panelHeight
      this.panel.resize(width, panelHeight)
    }
  }

  // Queued by the settings page, which runs a separate fcitx without the learned words.
  private runPendingPinyinActions() {
    const path = pendingPinyinActionsPath(this.sharedDir)
    const text = readText(path)
    if (text === null) {
      return
    }
    removeFile(path)
    try {
      for (const action of JSON.parse(text) as string[]) {
        fcitx.runPinyinAction(action)
      }
      this.writeUserWordsSnapshot(true)
    } catch (e) {
      console.error(`Invalid pinyin actions: ${e}`)
    }
  }

  // The main app can't read fcitx's user data, so leave a copy for its export.
  private writeUserWordsSnapshot(force: boolean) {
    const now = Date.now()
    if (!force && now - this.lastSnapshotTime < SNAPSHOT_INTERVAL) {
      return
    }
    this.lastSnapshotTime = now
    try {
      writeText(userWordsSnapshotPath(this.sharedDir), fcitx.exportGooglePinyinWords())
      writeText(englishSnapshotPath(this.sharedDir), fcitx.exportLearnedEnglish())
      // Saved just before, for backups in the main app.
      for (const file of ['user.dict', 'user.history']) {
        const from = `${this.filesDir}/data/fcitx5/pinyin/${file}`
        if (fs.accessSync(from)) {
          const to = userDataCopyPath(this.sharedDir, file)
          ensureDir(to.substring(0, to.lastIndexOf('/')))
          fs.copyFileSync(from, to)
        }
      }
    } catch (e) {
      console.error(`Failed to write user words: ${e}`)
    }
  }

  // Google Pinyin vibrates on touch down.
  private vibrate() {
    const settings = this.settings
    if (settings && settings.keySound) {
      this.keySound.play(settings.keySoundVolume / 100)
    }
    if (!settings || !settings.vibrate) {
      return
    }
    const attribute: vibrator.VibrateAttribute = { id: 0, usage: 'touch' }
    if (this.hapticPresetSupported) {
      const effect: vibrator.VibratePreset = {
        type: 'preset',
        effectId: hapticEffects[settings.vibrationStrength],
        count: 1,
      }
      vibrator.startVibration(effect, attribute).catch((e: Error) => {
        console.error(`haptic preset failed: ${e.message}`)
        this.hapticPresetSupported = false
      })
      return
    }
    const effect: vibrator.VibrateTime = { type: 'time', duration: hapticDurations[settings.vibrationStrength] }
    vibrator.startVibration(effect, attribute).catch((e: Error) => {
      console.error(`vibration failed: ${e.message}`)
    })
  }

  // The main app queues Google Pinyin words; merge them into the running pinyin engine.
  private applyPendingImport() {
    try {
      this.mergePendingImport()
    } catch (e) {
      console.error(`Google Pinyin import failed: ${e}`)
    }
  }

  private mergePendingImport() {
    const path = pendingImportPath(this.sharedDir)
    const tsv = readText(path)
    if (tsv === null) {
      return
    }
    removeFile(path)
    const counts = fcitx.importGooglePinyinWords(tsv).split(' ').map((n: string) => Number.parseInt(n))
    if (counts.length !== 3 || counts.some((n: number) => Number.isNaN(n))) {
      console.error('Google Pinyin import failed')
      return
    }
    const skipped = Number.parseInt(readText(pendingSkippedPath(this.sharedDir)) ?? '0')
    removeFile(pendingSkippedPath(this.sharedDir))
    // What was typed for each word, and English words, for the pinyin engine's own tables.
    const typed = readText(pendingTypedPath(this.sharedDir)) ?? ''
    const english = readText(pendingEnglishPath(this.sharedDir)) ?? ''
    removeFile(pendingTypedPath(this.sharedDir))
    removeFile(pendingEnglishPath(this.sharedDir))
    const learned = fcitx.importGooglePinyinLearned(typed, english).split(' ')
      .map((n: string) => Number.parseInt(n))
    const result: ImportResult = {
      added: counts[0],
      existing: counts[1],
      invalid: counts[2],
      skipped: Number.isNaN(skipped) ? 0 : skipped,
      time: Date.now(),
      typed: learned.length === 2 && !Number.isNaN(learned[0]) ? learned[0] : 0,
      english: learned.length === 2 && !Number.isNaN(learned[1]) ? learned[1] : 0,
    }
    writeText(importResultPath(this.sharedDir), JSON.stringify(result))
    this.writeUserWordsSnapshot(true)
  }

  private physicalKeyEventHandler(e: inputMethodEngine.KeyEvent): boolean {
    const isRelease = e.keyAction === 3
    let handled = false
    guard('physical key', () => {
      handled = this.processResult(fcitx.processKey(0, e.keyCode, isRelease, ''))
    })
    return handled
  }

  private initHelper() {
    if (this.initialized) {
      return
    }
    try {
      const before = this.getTextBefore()
      this.preeditIndex = before.length
      // Kept up to date by textChange, which isn't called on focus.
      this.textWithPreedit = before + this.getTextAfter()
      resetStacks(this.textWithPreedit)
      this.initialized = true
    } catch (e) { // getTextIndexAtCursorSync can throw.
      console.error(`${e}`)
      // Not forever: the editor may be gone.
      if (++this.initRetries < 10) {
        setTimeout(() => { this.initHelper() }, 100)
      }
    }
  }

  private registerListener(): void {
    this.registerInputListener();
    keyboardDelegate.on('keyDown', (e) => {
      return this.physicalKeyEventHandler(e)
    })
    keyboardDelegate.on('keyUp', (e) => {
      return this.physicalKeyEventHandler(e)
    })
    // This is not called on focus.
    keyboardDelegate.on('textChange', (text: string) => {
      this.textWithPreedit = text
      // Block text changes with a preedit.
      if (!this.preedit) {
        onTextChange(text)
      }
      // Mainly for clicking x to clear all text including preedit,
      // but harmless for pressing backspace till nothing left.
      if (!text) {
        fcitx.reset()
      }
    })
    // This is called on focus. There is a bug on Harmony's side that makes it unreliable.
    // Reproduce: having 是的, double click 是 to select, drag 📍 on the left to the right,
    // then double click 的 to select. The last step won't update selection to 1,2.
    keyboardDelegate.on('selectionChange', (oldBegin: number, oldEnd: number, newBegin: number, newEnd: number) => {
      console.debug(`selectionChange ${oldBegin} ${oldEnd} ${newBegin} ${newEnd}`)
      this.initHelper()
      this.selectionStart = newBegin
      this.selectionEnd = newEnd
      // Because selectByMovementSync won't call this, doing below won't interrupt selection when start and end overlap.
      this.selecting = this.selectionStart !== this.selectionEnd
      if (!this.preedit) {
        this.preeditIndex = this.selectionStart
      }
      this.sendEvent({ type: this.selecting ? 'SELECT' : 'DESELECT' })
    })
  }

  private registerInputListener(): void {
    ability.on('inputStart', (kbController, textInputClient) => {
      this.initialized = false
      this.initRetries = 0
      this.textInputClient = textInputClient;
      this.keyboardController = kbController;
      guard('inputStart', () => {
        this.attribute = textInputClient.getEditorAttributeSync()
        const bundleName = this.attribute.bundleName ?? ''
        // Editors in 卓易通 come through its broker without a bundle name.
        this.asyncEditor = !bundleName || slowEditors.has(bundleName)
        console.info(`inputStart ${bundleName} preview ${this.attribute.isTextPreviewSupported} async ${this.asyncEditor}`)
        // Preview text is synchronous only.
        fcitx.focusIn(this.attribute.isTextPreviewSupported && !this.asyncEditor)
        this.setEnterKeyType()
      })
    })
    ability.on('inputStop', () => {
      // This is not paired with inputStart. Only called when switching to Celia.
      console.debug('inputStop')
      fcitx.focusOut()
    });
  }

  private unRegisterListener(): void {
    ability.off('inputStart');
    ability.off('inputStop', () => {
    });
    keyboardDelegate.off('keyDown')
    keyboardDelegate.off('keyUp')
    keyboardDelegate.off('textChange')
    this.panel?.off('show')
    this.panel?.off('hide')
  }
}

const keyboardController = new KeyboardController();

export default keyboardController;
