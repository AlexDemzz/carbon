#!/bin/bash
# Usage: make-dmg.sh path/to/Carbon.app path/to/Carbon-X.Y.Z.dmg
# Builds a compressed DMG holding the app and an Applications symlink.
set -euo pipefail

app="$1"
dmg="$2"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
hdiutil create -volname Carbon -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg"
