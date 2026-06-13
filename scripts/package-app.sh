#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
APP_DIR="$ROOT_DIR/Build/CloudBar.app"
EXECUTABLE="$ROOT_DIR/.build/$CONFIGURATION/CloudBar"

cd "$ROOT_DIR"
swift build --configuration "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/CloudBar"
chmod +x "$APP_DIR/Contents/MacOS/CloudBar"

echo "$APP_DIR"
