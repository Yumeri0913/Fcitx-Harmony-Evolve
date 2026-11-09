[中文](README.md)
|
English

# Fcitx HarmonyOS Evolve

A pinyin keyboard for HarmonyOS built on [Fcitx5](https://github.com/fcitx/fcitx5),
focused on the hand-typed input experience in the AI era: getting the typing feel
right, kept in line with its Android and iOS siblings.

It is a fork of [fcitx5-harmony](https://github.com/fcitx-contrib/fcitx5-harmony).

> Status: personal project, in daily use on a HarmonyOS 7.0 phone but not
> released. There is no prebuilt HAP yet; build it yourself (see below).

## What's different from fcitx5-harmony

### Look
- Light / dark themes with borderless keys, a pill space bar and a round return
  key; adjustable key radius and margins
- Retuned keyboard height: a fixed height per screen size, or a percentage of
  the screen height
- The toolbar always shows 中/英, undo, redo, text editing, clipboard, theme
  and more

### Typing feel
- Tuned gestures: swipe sensitivity, long press delay, space bar cursor
  dragging, backspace repeat
- Key previews above the finger, kept 100 ms after release
- Vibration with adjustable strength, and key sound

### Pinyin and dictionaries
- Better dictionary import (libime `.dict` / `.txt` and Sogou `.scel`)
- Much better mixed Chinese and English input

### Symbols and emoji
- Symbol keyboard with categories
- Emoji and emoticon panel (long press comma)

### Settings
- The globe key only toggles Chinese / English; long press space to pick an
  input method
- The settings app includes all fcitx settings: input methods, pinyin, global
  options, addons
- Backup and restore; Android backups restore here
- Clipboard panel and LAN clipboard sync (sync off by default)

### Fixes
- Pinyin unavailable on real devices: HarmonyOS puts native libraries in
  `libs/arm64`; they are now located with `dladdr`
- The input method extension has its own sandbox; settings and dictionaries are
  exchanged through `distributedFilesDir`, which both sides can reach
- Native code in Debug builds is compiled at -O2: decoding long sentences went
  from about 100 ms to 25 ms a key

## Build

You need DevEco Studio (HarmonyOS SDK, `ohpm`, `hvigorw`), Node.js with pnpm 10,
gettext and wget. Below builds for a phone (`arm64-v8a`); use `x86_64` for the
emulator.

```sh
git clone --recursive https://github.com/Yumeri0913/Fcitx-Harmony-Evolve.git && cd Fcitx-Harmony-Evolve
npm i -g pnpm@10

# Download prebuilt dependencies and build the customized web keyboard
# (scripts/build-keyboard.sh)
./scripts/install-deps.sh arm64-v8a

# Patch the submodules
git apply --directory=entry/src/main/cpp/fcitx5 patches/fcitx5.patch
git apply --directory=entry/src/main/cpp/fcitx5-chinese-addons patches/chinese-addons.patch
git apply --directory=entry/src/main/cpp/libime patches/libime.patch

ohpm install --all
hvigorw assembleHap --mode module -p product=default -p buildABI=arm64-v8a -p buildMode=release
```

Installing on a device needs signing: use automatic signing in DevEco Studio
(File → Project Structure → Signing Configs). It writes the signing material
into `build-profile.json5`; don't commit those changes.

## Upstream

Generic fixes are welcome upstream at
[fcitx5-harmony](https://github.com/fcitx-contrib/fcitx5-harmony). Thanks to
its authors and to the [Fcitx](https://github.com/fcitx) project.

## License

[GPL-3.0](LICENSE).
