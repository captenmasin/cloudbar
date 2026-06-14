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
echo "$APPLE_API_KEY_BASE64" | base64 --decode > "$API_KEY_PATH"

echo "Signing $APP_DIR..."
codesign --force --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGNING_IDENTITY" \
  "$APP_DIR/Contents/MacOS/CloudBar"

codesign --force --options runtime \
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

echo "Submitting $DMG_PATH for notarization..."
SUBMISSION_JSON="$(mktemp)"
trap 'rm -f "$API_KEY_PATH" "$SUBMISSION_JSON"' EXIT

if ! xcrun notarytool submit "$DMG_PATH" \
  --key "$API_KEY_PATH" \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER_ID" \
  --output-format json > "$SUBMISSION_JSON"; then
  cat "$SUBMISSION_JSON" >&2
  exit 1
fi

SUBMISSION_ID="$(python3 -c "import json, sys; print(json.load(open(sys.argv[1]))['id'])" "$SUBMISSION_JSON")"
echo "Notarization submission ID: $SUBMISSION_ID"

echo "Waiting for Apple notarization..."
MAX_WAIT_ATTEMPTS=120
WAIT_SLEEP_SECONDS=30
for ((attempt = 1; attempt <= MAX_WAIT_ATTEMPTS; attempt++)); do
  if xcrun notarytool wait "$SUBMISSION_ID" \
    --key "$API_KEY_PATH" \
    --key-id "$APPLE_API_KEY_ID" \
    --issuer "$APPLE_API_ISSUER_ID"; then
    echo "Notarization accepted."
    break
  fi

  if [[ "$attempt" -eq "$MAX_WAIT_ATTEMPTS" ]]; then
    echo "Notarization did not complete after $MAX_WAIT_ATTEMPTS attempts." >&2
    xcrun notarytool log "$SUBMISSION_ID" \
      --key "$API_KEY_PATH" \
      --key-id "$APPLE_API_KEY_ID" \
      --issuer "$APPLE_API_ISSUER_ID" >&2 || true
    exit 1
  fi

  echo "Notarization wait failed (attempt $attempt/$MAX_WAIT_ATTEMPTS). Retrying in ${WAIT_SLEEP_SECONDS}s..."
  sleep "$WAIT_SLEEP_SECONDS"
done

echo "Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

echo "$DMG_PATH"
