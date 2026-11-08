#!/bin/bash
set -e

# Build the customized fcitx5-keyboard-web for Harmony and bundle it as rawfile/index.html.
cd entry/src/main/fcitx5-keyboard-web

# The Google Pinyin symbol board uses symbol data newer than the pinned layouts.
LAYOUTS_COMMIT=f9a6982cbe992009b21ca1edb61f283e865c0d0e
if [[ $(git -C fcitx5-keyboard-layouts rev-parse HEAD) != $LAYOUTS_COMMIT ]]; then
  git -C fcitx5-keyboard-layouts fetch origin $LAYOUTS_COMMIT
  git -C fcitx5-keyboard-layouts checkout $LAYOUTS_COMMIT
fi

# Apply the Google Pinyin look unless it is already applied.
if git apply --check ../../../../patches/keyboard-web.patch 2>/dev/null; then
  git apply ../../../../patches/keyboard-web.patch
fi

pnpm i --config.strict-dep-builds=false
pnpm --config.verify-deps-before-run=false run build:harmony
cp dist/harmony/index.html ../resources/rawfile/index.html
