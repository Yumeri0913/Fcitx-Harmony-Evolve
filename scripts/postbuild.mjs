import { spawnSync } from 'child_process'
import { copyFileSync, mkdirSync, readdirSync } from 'fs'
import path from 'path'

const [destDir, buildDir, prebuiltUsrDir] = process.argv.slice(2)

const env = { ...process.env, DESTDIR: path.resolve(destDir) }

const destShareDir = `${destDir}/usr/share`
const isoJsonDir = `${destShareDir}/iso-codes/json`
mkdirSync(isoJsonDir, { recursive: true })

const commands = [
  ['cmake', '--install', buildDir, '--component', 'config'],
  ['cp', '-r', `${prebuiltUsrDir}/share/xkeyboard-config-2`, destShareDir],
  ['cp', `${prebuiltUsrDir}/share/iso-codes/json/iso_639-3.json`, isoJsonDir],
]

for (const command of commands) {
  const result = spawnSync(command[0], command.slice(1), {
    env,
    stdio: 'inherit',
    shell: true
  })
  
  if (result.error || result.status !== 0) {
    exit(1)
  }
}

// Translations built from source (fcitx5 core, chinese-addons, lua) are not part of the
// config component; install them as <domain>.mo like `make install` would.
const localeDir = `${destShareDir}/locale`
for (const project of readdirSync(buildDir, { withFileTypes: true })) {
  if (!project.isDirectory()) {
    continue
  }
  const poDir = path.join(buildDir, project.name, 'po')
  let files
  try {
    files = readdirSync(poDir)
  } catch {
    continue
  }
  for (const file of files) {
    const match = file.match(/^(.+)-([A-Za-z_@]+)\.mo$/)
    if (!match) {
      continue
    }
    const [, domain, lang] = match
    const dir = `${localeDir}/${lang}/LC_MESSAGES`
    mkdirSync(dir, { recursive: true })
    copyFileSync(path.join(poDir, file), `${dir}/${domain}.mo`)
  }
}
