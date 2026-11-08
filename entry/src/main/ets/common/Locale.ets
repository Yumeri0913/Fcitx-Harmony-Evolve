import { i18n } from '@kit.LocalizationKit'

// The system locale in the form fcitx translations use, e.g. zh-Hans-HK -> zh_CN.
// fcitx has zh_CN and zh_TW catalogs, so Chinese goes by script rather than region.
export function fcitxLocale(): string {
  const locale = new Intl.Locale(i18n.System.getSystemLocale())
  if (locale.language === 'zh') {
    const traditional = locale.script === 'Hant' ||
      (!locale.script && (locale.region === 'TW' || locale.region === 'HK' || locale.region === 'MO'))
    return traditional ? 'zh_TW' : 'zh_CN'
  }
  return locale.region ? `${locale.language}_${locale.region}` : locale.language
}
