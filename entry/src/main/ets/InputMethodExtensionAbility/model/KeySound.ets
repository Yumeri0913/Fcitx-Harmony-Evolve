// Key press sound, fcitx5-android's sound on key press. A short click is generated as a
// WAV file once, then played through a SoundPool so presses don't wait for decoding.
import { audio } from '@kit.AudioKit'
import { media } from '@kit.MediaKit'
import { fileIo as fs } from '@kit.CoreFileKit'

const SAMPLE_RATE = 22050
const DURATION = 0.012

// 16-bit mono PCM: a quickly decaying 2 kHz tick.
function clickWav(): ArrayBuffer {
  const samples = Math.round(SAMPLE_RATE * DURATION)
  const buffer = new ArrayBuffer(44 + samples * 2)
  const view = new DataView(buffer)
  const writeString = (offset: number, text: string) => {
    for (let i = 0; i < text.length; i++) {
      view.setUint8(offset + i, text.charCodeAt(i))
    }
  }
  writeString(0, 'RIFF')
  view.setUint32(4, 36 + samples * 2, true)
  writeString(8, 'WAVE')
  writeString(12, 'fmt ')
  view.setUint32(16, 16, true)
  view.setUint16(20, 1, true)
  view.setUint16(22, 1, true)
  view.setUint32(24, SAMPLE_RATE, true)
  view.setUint32(28, SAMPLE_RATE * 2, true)
  view.setUint16(32, 2, true)
  view.setUint16(34, 16, true)
  writeString(36, 'data')
  view.setUint32(40, samples * 2, true)
  for (let i = 0; i < samples; i++) {
    const t = i / SAMPLE_RATE
    const value = Math.sin(2 * Math.PI * 2000 * t) * Math.exp(-t * 400)
    view.setInt16(44 + i * 2, Math.round(value * 12000), true)
  }
  return buffer
}

export class KeySound {
  private soundPool: media.SoundPool | null = null
  private soundId = 0
  private loading = false

  init(filesDir: string) {
    if (this.soundPool || this.loading) {
      return
    }
    this.loading = true
    const path = `${filesDir}/click.wav`
    try {
      if (!fs.accessSync(path)) {
        const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
        fs.writeSync(file.fd, clickWav())
        fs.closeSync(file)
      }
    } catch (e) {
      console.error(`Failed to write key sound: ${e}`)
      this.loading = false
      return
    }
    const info: audio.AudioRendererInfo = {
      usage: audio.StreamUsage.STREAM_USAGE_NOTIFICATION,
      rendererFlags: 1,
    }
    media.createSoundPool(2, info).then(async (pool: media.SoundPool) => {
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY)
      this.soundId = await pool.load(file.fd, 0, fs.statSync(path).size)
      this.soundPool = pool
    }).catch((e: Error) => {
      console.error(`Failed to load key sound: ${e.message}`)
    }).finally(() => {
      this.loading = false
    })
  }

  // volume: 0 to 1.
  play(volume: number) {
    if (!this.soundPool) {
      return
    }
    this.soundPool.play(this.soundId, { leftVolume: volume, rightVolume: volume, priority: 1 })
      .catch((e: Error) => console.error(`Failed to play key sound: ${e.message}`))
  }
}
