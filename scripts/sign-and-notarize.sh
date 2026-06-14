#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${APP_DIR:-$ROOT_DIR/Build/CloudBar.app}"
DMG_PATH="${DMG_PATH:-$ROOT_DIR/Build/CloudBar.dmg}"
ENTITLEMENTS="$ROOT_DIR/Sources/CloudBar/Resources/CloudBar.entitlements"

: "${SIGNING_IDENTITY:?SIGNING_IDENTITY must be set}"
: "${APPLE_API_KEY_ID:?APPLE_API_KEY_ID must be set}"
: "${APPLE_API_ISSUER_ID:?APPLE_API_ISSUER_ID must be set}"
: "${APPLE_API_KEY_BASE64:?APPLE_API_KEY_BASE64 must be set}"

if [[ ! -d "$APP_DIR" ]]; then
  echo "App bundle not found at $APP_DIR" >&2
  exit 1
fi

if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "Entitlements file not found at $ENTITLEMENTS" >&2
  exit 1
fi

API_KEY_PATH="$(mktemp)"
trap 'rm -f "$API_KEY_PATH"' EXIT
echo "$APPLE_API_KEY_BASE64" | base64 --decode > "$API_KEY_PATH"

echo "Signing $APP_DIR..."
codesign --force --deep --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGNING_IDENTITY" \
  "$APP_DIR"

codesign --verify --deep --strict "$APP_DIR"

rm -f "$DMG_PATH"
mkdir -p "$(dirname "$DMG_PATH")"

echo "Creating DMG..."
if ! command -v create-dmg >/dev/null 2>&1; then
  echo "create-dmg is required. Install with: brew install create-dmg" >&2
  exit 1
fi

create-dmg \
  --volname "CloudBar" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 160 \
  --icon "CloudBar.app" 180 170 \
  --app-drop-link 480 170 \
  --hide-extension "CloudBar.app" \
  "$DMG_PATH" \
  "$(dirname "$APP_DIR")" \
  >/dev/null

echo "Notarizing $DMG_PATH..."
xcrun notarytool submit "$DMG_PATH" \
  --key "$API_KEY_PATH" \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER_ID" \
  --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

echo "$DMG_PATH"
