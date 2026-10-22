#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Hago"
APP_DIR="${1:-outputs/$APP_NAME.app}"
NOTARY_ARCHIVE="${2:-outputs/notarization.zip}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIGN_IDENTITY="${HAGO_CODE_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${HAGO_NOTARY_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"

require_env() {
  local name="$1"
  local value="$2"

  if [[ -z "$value" ]]; then
    echo "$name is required." >&2
    exit 1
  fi
}

require_env HAGO_CODE_SIGN_IDENTITY "$SIGN_IDENTITY"
if [[ -z "$NOTARY_PROFILE" ]]; then
  require_env APPLE_ID "$APPLE_ID"
  require_env APPLE_TEAM_ID "$APPLE_TEAM_ID"
  require_env APPLE_APP_SPECIFIC_PASSWORD "$APPLE_APP_SPECIFIC_PASSWORD"
fi

if [[ ! -d "$APP_DIR" ]]; then
  echo "Could not find app bundle at $APP_DIR." >&2
  exit 1
fi

if [[ "$SIGN_IDENTITY" != "Developer ID Application:"* ]]; then
  echo "Distribution requires a Developer ID Application identity." >&2
  exit 1
fi
FRAMEWORK="$APP_DIR/Contents/Frameworks/Sparkle.framework"
if [[ -d "$FRAMEWORK" ]]; then
  for component in Versions/B/XPCServices/Downloader.xpc Versions/B/XPCServices/Installer.xpc Versions/B/Autoupdate Versions/B/Updater.app; do
    codesign --force --sign "$SIGN_IDENTITY" --timestamp --options runtime --preserve-metadata=identifier,entitlements "$FRAMEWORK/$component"
  done
  codesign --force --sign "$SIGN_IDENTITY" --timestamp --options runtime "$FRAMEWORK"
fi
codesign \
  --force \
  --deep \
  --timestamp \
  --options runtime \
  --entitlements "$ROOT_DIR/Resources/Hago.entitlements" \
  --sign "$SIGN_IDENTITY" \
  "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

rm -f "$NOTARY_ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$NOTARY_ARCHIVE"

if [[ -n "$NOTARY_PROFILE" ]]; then
  RESULT="$(xcrun notarytool submit "$NOTARY_ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
else
  RESULT="$(xcrun notarytool submit "$NOTARY_ARCHIVE" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --wait --output-format json)"
fi
STATUS="$(printf '%s' "$RESULT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')"
[[ "$STATUS" == "Accepted" ]] || { echo "Notarization was not accepted: $STATUS" >&2; exit 1; }

xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"
spctl --assess --type execute --verbose "$APP_DIR"
