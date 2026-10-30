#!/bin/zsh
set -euo pipefail
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="$ROOT/Codex Battery.app"
TASK_BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$TASK_BUILD_DIR"' EXIT
APP="$TASK_BUILD_DIR/Codex Battery.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos15.0 \
  "$ROOT"/Sources/*.swift -o "$APP/Contents/MacOS/CodexBattery" \
  -framework AppKit -framework SwiftUI -framework ServiceManagement
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
fi
xattr -cr "$APP"
codesign --force --sign - --identifier local.neil.codexbattery "$APP"
ditto --noextattr --norsrc "$APP" "$OUTPUT"
echo "$OUTPUT"
