// File helpers for the settings pages: picker URIs and the shared dir.
import { fileIo as fs } from '@kit.CoreFileKit'

export function readBytes(uriOrPath: string): Uint8Array {
  const file = fs.openSync(uriOrPath, fs.OpenMode.READ_ONLY)
  try {
    const size = fs.statSync(file.fd).size
    const buffer = new ArrayBuffer(size)
    let offset = 0
    while (offset < size) {
      const n = fs.readSync(file.fd, buffer, { offset: offset, length: size - offset })
      if (n <= 0) {
        break
      }
      offset += n
    }
    return new Uint8Array(buffer, 0, offset)
  } finally {
    fs.closeSync(file)
  }
}

export function writeBytes(uriOrPath: string, bytes: Uint8Array) {
  const file = fs.openSync(uriOrPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
  try {
    fs.writeSync(file.fd, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength))
  } finally {
    fs.closeSync(file)
  }
}

export function ensureDir(path: string) {
  if (!fs.accessSync(path)) {
    fs.mkdirSync(path, true)
  }
}

export function exists(path: string): boolean {
  try {
    return fs.accessSync(path)
  } catch (e) {
    return false
  }
}

export function listFiles(dir: string): string[] {
  try {
    return exists(dir) ? fs.listFileSync(dir) : []
  } catch (e) {
    return []
  }
}

// Name of a picked file, from the last path segment of its URI.
export function fileName(uri: string): string {
  return decodeURIComponent(uri.substring(uri.lastIndexOf('/') + 1))
}

// Copy the contents of src into dest, overwriting files.
export function copyTree(src: string, dest: string) {
  ensureDir(dest)
  for (const name of listFiles(src)) {
    const from = `${src}/${name}`
    const to = `${dest}/${name}`
    if (fs.statSync(from).isDirectory()) {
      copyTree(from, to)
    } else {
      fs.copyFileSync(from, to)
    }
  }
}

export function removeTree(path: string) {
  if (exists(path)) {
    fs.rmdirSync(path)
  }
}
