#!/bin/sh
# PROTOTYPE, throwaway. Builds a menu-bar-only .app so native notifications work, then opens it.
set -e
cd "$(dirname "$0")"
swift build -c debug
APP=".build/Carbon Mock.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/debug/CarbonMock "$APP/Contents/MacOS/CarbonMock"
cp ../icon-board/final/menubar-idle.svg "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>me.alexandrejoly.carbon.prototype</string>
  <key>CFBundleName</key><string>Carbon Mock</string>
  <key>CFBundleExecutable</key><string>CarbonMock</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.1</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign -s - --force "$APP"
pkill -x CarbonMock 2>/dev/null || true
open "$APP" --args ${1:+-variant "$1"}
