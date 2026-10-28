#!/bin/bash
# Usage: make-dmg.sh path/to/Carbon.app path/to/Carbon-X.Y.Z.dmg
# Builds a compressed DMG whose window shows the app, an Applications symlink and a
# drag-to-Applications background, with Carbon's icon on the volume. Signing comes after.
set -euo pipefail

app="$1"
dmg="$2"
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

python3 -m venv "$work/venv"
"$work/venv/bin/pip" install --quiet --disable-pip-version-check --require-hashes --only-binary :all: \
  -r "$here/dmg/requirements.txt"

swift "$here/dmg/background.swift" "$work"
tiffutil -cathidpicheck "$work/background.png" "$work/background@2x.png" -out "$work/background.tiff"

rm -f "$dmg"
"$work/venv/bin/dmgbuild" -s "$here/dmg/settings.py" \
  -D app="$app" \
  -D background="$work/background.tiff" \
  -D volume_icon="$app/Contents/Resources/Carbon.icns" \
  Carbon "$dmg"
