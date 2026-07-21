#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Voicedeck"
BUILD_PRODUCT="VoiceDeck"
BUNDLE_ID="com.bobhe.voicedeck.capture"
MIN_SYSTEM_VERSION="14.0"

# Keep this identifier stable across local test builds. macOS grants privacy
# permissions to an application's signed identity, not merely its visible name.
if [[ "$MODE" == "--test" || "$MODE" == "test" ]]; then
  MODE="run"
  APP_NAME="VoiceDeck12345"
  BUNDLE_ID="com.bobhe.voicedeck.test12345"
fi

if [[ "$MODE" == "--test2" || "$MODE" == "test2" ]]; then
  MODE="run"
  APP_NAME="VoiceDeck2"
  BUNDLE_ID="com.bobhe.voicedeck.test2"
fi

if [[ "$MODE" == "--test3" || "$MODE" == "test3" ]]; then
  MODE="run"
  APP_NAME="VoiceDeck3"
  BUNDLE_ID="com.bobhe.voicedeck.test3"
fi

if [[ "$MODE" == "--test4" || "$MODE" == "test4" ]]; then
  MODE="run"
  APP_NAME="VoiceDeck4"
  BUNDLE_ID="com.bobhe.voicedeck.test4"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$ROOT_DIR/assets/AppIcon.svg"
ICON_SET="$DIST_DIR/AppIcon.iconset"
ICON_FILE="$APP_RESOURCES/AppIcon.icns"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$BUILD_PRODUCT"

mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -f "$ICON_SOURCE" ]]; then
  rm -rf "$ICON_SET"
  mkdir -p "$ICON_SET"
  for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" "$ICON_SOURCE" --out "$ICON_SET/icon_${size}x${size}.png" >/dev/null
    sips -s format png -z "$((size * 2))" "$((size * 2))" "$ICON_SOURCE" --out "$ICON_SET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICON_SET" -o "$ICON_FILE"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Voice Deck uses your microphone to turn a spoken question into text.</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>Voice Deck captures the frontmost window when you choose to add it as conversation context.</string>
</dict>
</plist>
PLIST

# Bind the generated Info.plist to the app signature. A configured Apple
# Development identity is preferred; local builds fall back to an explicitly
# identified ad-hoc signature so the test bundle remains distinguishable.
SIGNING_IDENTITY="${VOICEDECK_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*\"\(Apple Development:.*\)\"/\1/p' | head -n 1)"
fi

if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --force --deep --sign "$SIGNING_IDENTITY" --identifier "$BUNDLE_ID" "$APP_BUNDLE"
else
  codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--test|--test2|--test3|--test4|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
