#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${APP_DIR:-$ROOT_DIR/Build/CloudBar.app}"
DMG_PATH="${DMG_PATH:-$ROOT_DIR/Build/CloudBar.dmg}"
ENTITLEMENTS="$ROOT_DIR/Sources/CloudBar/Resources/CloudBar.entitlements"
NOTARY_TIMEOUT_MINUTES="${NOTARY_TIMEOUT_MINUTES:-60}"
NOTARY_POLL_SECONDS="${NOTARY_POLL_SECONDS:-20}"
NOTARY_MAX_NETWORK_ERRORS="${NOTARY_MAX_NETWORK_ERRORS:-10}"

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
chmod 600 "$API_KEY_PATH"

NOTARY_AUTH=(
  --key "$API_KEY_PATH"
  --key-id "$APPLE_API_KEY_ID"
  --issuer "$APPLE_API_ISSUER_ID"
)

cleanup() {
  rm -f "$API_KEY_PATH"
}
trap cleanup EXIT

print_notarization_log() {
  local submission_id="$1"
  echo "Fetching notarization log for $submission_id..." >&2
  xcrun notarytool log "$submission_id" "${NOTARY_AUTH[@]}" >&2 || true
}

wait_for_notarization() {
  local submission_id="$1"
  local deadline=$(( $(date +%s) + NOTARY_TIMEOUT_MINUTES * 60 ))
  local network_errors=0

  echo "Waiting for Apple notarization (submission $submission_id, timeout ${NOTARY_TIMEOUT_MINUTES}m)..."

  while (( $(date +%s) < deadline )); do
    local info_json
    if ! info_json="$(xcrun notarytool info "$submission_id" \
      "${NOTARY_AUTH[@]}" \
      --output-format json 2>&1)"; then
      network_errors=$((network_errors + 1))
      echo "Warning: could not fetch notarization status ($network_errors/$NOTARY_MAX_NETWORK_ERRORS): $info_json" >&2
      if (( network_errors >= NOTARY_MAX_NETWORK_ERRORS )); then
        echo "Too many consecutive notarization status errors." >&2
        print_notarization_log "$submission_id"
        return 1
      fi
      sleep "$NOTARY_POLL_SECONDS"
      continue
    fi

    network_errors=0
    local status
    status="$(python3 -c "import json, sys; print(json.load(sys.stdin)['status'])" <<< "$info_json")"

    case "$status" in
      Accepted)
        echo "Notarization accepted."
        return 0
        ;;
      Invalid|Rejected)
        echo "Notarization $status." >&2
        print_notarization_log "$submission_id"
        return 1
        ;;
      *)
        echo "Notarization status: $status ($(date -u +%H:%M:%S) UTC)"
        ;;
    esac

    sleep "$NOTARY_POLL_SECONDS"
  done

  echo "Notarization timed out after ${NOTARY_TIMEOUT_MINUTES} minutes." >&2
  echo "Submission ID: $submission_id (check status with: xcrun notarytool info $submission_id)" >&2
  xcrun notarytool info "$submission_id" "${NOTARY_AUTH[@]}" >&2 || true
  print_notarization_log "$submission_id"
  return 1
}

echo "Verifying App Store Connect API credentials..."
if ! xcrun notarytool history "${NOTARY_AUTH[@]}" >/dev/null 2>&1; then
  echo "App Store Connect API credentials are invalid or lack notarization access." >&2
  exit 1
fi

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

echo "Signing DMG..."
codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"

echo "Submitting $DMG_PATH for notarization..."
SUBMISSION_JSON="$(mktemp)"
trap 'cleanup; rm -f "$SUBMISSION_JSON"' EXIT

if ! xcrun notarytool submit "$DMG_PATH" \
  "${NOTARY_AUTH[@]}" \
  --no-wait \
  --output-format json > "$SUBMISSION_JSON"; then
  cat "$SUBMISSION_JSON" >&2
  exit 1
fi

SUBMISSION_ID="$(python3 -c "import json, sys; print(json.load(open(sys.argv[1]))['id'])" "$SUBMISSION_JSON")"
echo "Notarization submission ID: $SUBMISSION_ID"

wait_for_notarization "$SUBMISSION_ID"

echo "Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

echo "$DMG_PATH"
