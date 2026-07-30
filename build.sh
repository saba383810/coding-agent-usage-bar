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
codesign --force --sign - "$APP"

echo "Built: $APP"
echo "起動:  open $APP"
