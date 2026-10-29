#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild -quiet -project boringNotch.xcodeproj -scheme boringNotch -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build

app=build/Build/Products/Release/Notchy.app
codesign --verify --deep --strict "$app"

osascript -e 'quit app "Notchy"' 2>/dev/null || true
while pgrep -xq Notchy; do sleep 0.5; done
# Notchy leaves its mediaremote-adapter stream running after quit.
pkill -f Notchy.app/Contents/Resources/mediaremote-adapter.pl || true
rm -rf /Applications/Notchy.app
ditto "$app" /Applications/Notchy.app
open /Applications/Notchy.app
echo "Installed and launched /Applications/Notchy.app"
