import { InputMethodExtensionAbility } from "@kit.IMEKit";
import type Want from "@ohos.app.ability.Want";
import keyboardController from "./model/KeyboardController";
import fcitx from 'libentry.so';
import { fcitxLocale } from '../common/Locale';

export default class FcitxInputMethodService extends InputMethodExtensionAbility {
  onCreate(want: Want): void {
    keyboardController.onCreate(this.context)
    const bundle = this.context.bundleCodeDir
    const resfile = this.context.resourceDir
    // The settings page edits config in the dir shared with the main app.
    fcitx.init(bundle, resfile, this.context.filesDir, this.context.distributedFilesDir, fcitxLocale())
  }

  onDestroy(): void {
    keyboardController.onDestroy()
  }
}
