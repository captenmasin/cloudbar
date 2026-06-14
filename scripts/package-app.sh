#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
APP_DIR="$ROOT_DIR/Build/CloudBar.app"
EXECUTABLE="$ROOT_DIR/.build/$CONFIGURATION/CloudBar"
APP_ICON_SOURCE="$ROOT_DIR/Sources/CloudBar/Resources/AppIcon.png"
ICONSET_DIR="$ROOT_DIR/Build/AppIcon.iconset"
ICON_PNG="$ICONSET_DIR/source.png"

cd "$ROOT_DIR"
swift build --configuration "$CONFIGURATION"

rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

INFO_PLIST_SOURCE="$ROOT_DIR/Sources/CloudBar/Resources/AppInfo.plist"
INFO_PLIST_DEST="$APP_DIR/Contents/Info.plist"
cp "$INFO_PLIST_SOURCE" "$INFO_PLIST_DEST"

if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST_DEST"
fi

if [[ -n "${BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST_DEST"
fi

cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/CloudBar"
chmod +x "$APP_DIR/Contents/MacOS/CloudBar"
cp "$ROOT_DIR/Sources/CloudBar/Resources/AppIcon.png" "$APP_DIR/Contents/Resources/"
cp "$ROOT_DIR/Sources/CloudBar/Resources/logo.svg" "$APP_DIR/Contents/Resources/"

mkdir -p "$ICONSET_DIR"
sips -s format png "$APP_ICON_SOURCE" --out "$ICON_PNG" >/dev/null
sips -z 16 16 "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

echo "$APP_DIR"
