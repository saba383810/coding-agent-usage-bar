#!/bin/bash
# CodingAgentUsageBar を .app バンドルとしてビルドする
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/CodingAgentUsageBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/CodingAgentUsageBar "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"

# Resources/AppIcon.png (1024x1024) から各サイズを作って .icns にまとめる
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET" "$APP/Contents/Resources"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"

echo "Built: $APP"
echo "起動:  open $APP"
