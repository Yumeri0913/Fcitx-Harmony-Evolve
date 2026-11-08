import { InputMethodExtensionAbility } from "@kit.IMEKit";
import type Want from "@ohos.app.ability.Want";
import keyboardController from "./model/KeyboardController";
import fcitx from 'libentry.so';
import { i18n } from '@kit.LocalizationKit';

export default class FcitxInputMethodService extends InputMethodExtensionAbility {
  onCreate(want: Want): void {
    keyboardController.onCreate(this.context)
    const bundle = this.context.bundleCodeDir
    const resfile = this.context.resourceDir
    // zh-Hans-CN -> zh_CN, the form fcitx translations use.
    const locale = new Intl.Locale(i18n.System.getSystemLocale())
    const fcitxLocale = locale.region ? `${locale.language}_${locale.region}` : locale.language
    fcitx.init(bundle, resfile, this.context.filesDir, fcitxLocale)
  }

  onDestroy(): void {
    keyboardController.onDestroy()
  }
}
