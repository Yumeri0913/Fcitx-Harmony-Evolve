// Backup and restore like fcitx5-android's UserDataManager. The zip has the same layout
// (external/config, external/data, metadata.json), so fcitx5-android backups restore
// here. Learned words are private to the input method, so they are merged through the
// same queue as Google Pinyin imports rather than replaced.
import { bundleManager, common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import fcitx from 'libentry.so';
import { copyTree, ensureDir, exists, readBytes, removeTree, writeBytes } from '../../common/Files';
import { fromTsv, toTsv } from '../../common/GooglePinyinUserDict';
import {
  pendingImportPath, readText, sharedDataPath, userDataCopyPath, writeText
} from '../../common/Settings';

const PACKAGES: string[] = ['org.fcitx.fcitx5.android', 'org.fcitx.fcitx5.android.debug', 'org.fcitx.fcitx5.harmony']
// Same as syncDataIfChanged: files the settings page edits.
const EDITABLE_DATA: string[] = ['pinyin/dictionaries', 'pinyin/customphrase', 'data/quickphrase.d', 'punctuation']

interface Metadata {
  packageName: string
  versionCode: number
  versionName: string
  exportTime: number
}

function pad(n: number): string {
  return n < 10 ? `0${n}` : `${n}`
}

@Component
export struct BackupPage {
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext
  private sharedDir: string = this.context.distributedFilesDir
  @State status: string = ''

  private configDir(): string {
    return `${this.sharedDir}/config/fcitx5`
  }

  private async exportBackup() {
    const stage = `${this.context.filesDir}/tmp/backup`
    const zip = `${this.context.filesDir}/tmp/backup.zip`
    try {
      removeTree(stage)
      ensureDir(stage)
      copyTree(this.configDir(), `${stage}/external/config`)
      copyTree(sharedDataPath(this.sharedDir, ''), `${stage}/external/data`)
      for (const file of ['user.dict', 'user.history']) {
        const copy = userDataCopyPath(this.sharedDir, file)
        if (exists(copy)) {
          ensureDir(`${stage}/external/data/pinyin`)
          writeBytes(`${stage}/external/data/pinyin/${file}`, readBytes(copy))
        }
      }
      ensureDir(`${stage}/harmony`)
      const settings = readText(`${this.sharedDir}/settings.json`)
      if (settings !== null) {
        writeText(`${stage}/harmony/settings.json`, settings)
      }
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      const metadata: Metadata = {
        packageName: info.name,
        versionCode: info.versionCode,
        versionName: info.versionName,
        exportTime: Date.now(),
      }
      writeText(`${stage}/metadata.json`, JSON.stringify(metadata))
      if (exists(zip)) {
        writeBytes(zip, new Uint8Array(0))
      }
      await zlib.compressFiles([`${stage}/external`, `${stage}/harmony`, `${stage}/metadata.json`], zip, {
        level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION,
      })
      const now = new Date()
      const name = `fcitx5_${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}.zip`
      const uris = await new picker.DocumentViewPicker(this.context).save({ newFileNames: [name] })
      if (uris.length === 0) {
        return
      }
      writeBytes(uris[0], readBytes(zip))
      this.status = `已导出 ${name}。学到的词截至上次收起键盘。`
    } catch (e) {
      this.status = `导出失败：${e}`
    } finally {
      removeTree(stage)
    }
  }

  private async importBackup() {
    const dir = `${this.context.filesDir}/tmp/restore`
    const zip = `${this.context.filesDir}/tmp/restore.zip`
    try {
      const uris = await new picker.DocumentViewPicker(this.context).select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['.zip'],
      })
      if (uris.length === 0) {
        return
      }
      ensureDir(`${this.context.filesDir}/tmp`)
      writeBytes(zip, readBytes(uris[0]))
      removeTree(dir)
      ensureDir(dir)
      await zlib.decompressFile(zip, dir)
      const metadata = JSON.parse(readText(`${dir}/metadata.json`) ?? '{}') as Metadata
      if (!PACKAGES.includes(metadata.packageName)) {
        this.status = '这不是 Fcitx5（安卓或鸿蒙）的备份。'
        return
      }
      if (exists(`${dir}/external/config`)) {
        copyTree(`${dir}/external/config`, this.configDir())
      }
      for (const item of EDITABLE_DATA) {
        const from = `${dir}/external/data/${item}`
        if (exists(from)) {
          const to = sharedDataPath(this.sharedDir, item)
          ensureDir(to.substring(0, to.lastIndexOf('/')))
          if (item.endsWith('customphrase')) {
            writeBytes(to, readBytes(from))
          } else {
            copyTree(from, to)
          }
        }
      }
      if (exists(`${dir}/harmony/settings.json`)) {
        writeText(`${this.sharedDir}/settings.json`, readText(`${dir}/harmony/settings.json`) ?? '{}')
      }
      let words = 0
      const dict = `${dir}/external/data/pinyin/user.dict`
      if (exists(dict)) {
        const restored = fromTsv(fcitx.readPinyinUserWords(dict, `${dir}/external/data/pinyin/user.history`))
        const pending = fromTsv(readText(pendingImportPath(this.sharedDir)) ?? '')
        words = restored.length
        if (words > 0) {
          writeText(pendingImportPath(this.sharedDir), toTsv(pending.concat(restored)))
        }
      }
      const from = metadata.packageName.startsWith('org.fcitx.fcitx5.android') ? '安卓' : '鸿蒙'
      this.status = `已恢复${from}备份的设置和词库` + (words > 0 ? `，${words} 个学到的词将在下次弹出键盘时合并` : '') +
        '。重新打开设置页面可看到恢复的选项。'
    } catch (e) {
      this.status = `恢复失败：${e}`
    } finally {
      removeTree(dir)
    }
  }

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        Text('备份包含设置、词库、自定义短语、快速输入、标点和学到的词，格式与 Fcitx5 安卓版相同，也可以恢复安卓版的备份。')
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
        Button('导出备份').width('100%').onClick(() => {
          this.exportBackup()
        })
        Button('从备份恢复').width('100%')
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .fontColor($r('sys.color.font_primary'))
          .onClick(() => {
            this.importBackup()
          })
        if (this.status) {
          Text(this.status).fontSize(14).width('100%')
        }
      }
      .padding(16)
      .width('100%')
    }
    .title('备份与恢复')
  }
}
