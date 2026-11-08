// Editor for a fcitx data file, e.g. pinyin custom phrases, punctuation or a quick phrase
// list, like fcitx5-android's editors. Edits go to the shared mirror of the data dir; the
// bundled file is the starting point and restoring the default removes the user copy.
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { exists } from '../../common/Files';
import { readText, sharedDataPath, writeText } from '../../common/Settings';

export interface TextFilePageParam {
  title: string
  // Relative to fcitx's data dir, e.g. pinyin/customphrase.
  relative: string
  hint: string
}

// Known files, opened from the main page and from External options of fcitx configs.
export function textFileParam(kind: string): TextFilePageParam {
  if (kind === 'customPhrase') {
    return {
      title: '自定义短语',
      relative: 'pinyin/customphrase',
      hint: '每行一条：“缩写,位置=内容”，例如 “dz,1=北京市海淀区”，输入 dz 时内容排在第 1 位。' +
        '也可以在键盘上长按候选词固定为自定义短语。',
    }
  }
  return {
    title: '标点',
    relative: 'punctuation/punc.mb.zh_CN',
    hint: '每行一条：“按键 中文标点”，可以写两个标点表示成对使用，例如 “\" “ ””。',
  }
}

@Component
export struct TextFilePage {
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext
  param: TextFilePageParam = { title: '', relative: '', hint: '' }
  @State text: string = ''
  @State status: string = ''
  @State custom: boolean = false

  private userPath(): string {
    return sharedDataPath(this.context.distributedFilesDir, this.param.relative)
  }

  private bundledPath(): string {
    return `${this.context.resourceDir}/usr/share/fcitx5/${this.param.relative}`
  }

  aboutToAppear() {
    this.load()
  }

  private load() {
    this.custom = exists(this.userPath())
    this.text = readText(this.custom ? this.userPath() : this.bundledPath()) ?? ''
  }

  private save() {
    try {
      writeText(this.userPath(), this.text.endsWith('\n') || !this.text ? this.text : `${this.text}\n`)
      this.custom = true
      this.status = '已保存，下次弹出键盘时生效。'
    } catch (e) {
      this.status = `保存失败：${e}`
    }
  }

  private restore() {
    try {
      if (exists(this.userPath())) {
        fs.unlinkSync(this.userPath())
      }
      this.load()
      this.status = '已恢复默认，下次弹出键盘时生效。'
    } catch (e) {
      this.status = `恢复失败：${e}`
    }
  }

  build() {
    NavDestination() {
      Column({ space: 8 }) {
        Text(this.param.hint).fontSize(14).fontColor($r('sys.color.font_secondary')).width('100%')
        TextArea({ text: this.text })
          .layoutWeight(1)
          .width('100%')
          .fontSize(15)
          .onChange((value: string) => {
            this.text = value
          })
        Row({ space: 12 }) {
          Button('保存').layoutWeight(1).onClick(() => this.save())
          Button('恢复默认').layoutWeight(1).enabled(this.custom)
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .fontColor($r('sys.color.font_primary'))
            .onClick(() => this.restore())
        }
        if (this.status) {
          Text(this.status).fontSize(14).width('100%')
        }
      }
      .padding(16)
      .height('100%')
    }
    .title(this.param.title)
  }
}
