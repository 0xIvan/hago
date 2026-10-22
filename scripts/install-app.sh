#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Hago"
SOURCE_APP="$ROOT_DIR/outputs/$APP_NAME.app"
TARGET_APP="/Applications/$APP_NAME.app"
SIGN_IDENTITY="${HAGO_CODE_SIGN_IDENTITY:-}"

if (( $# > 1 )) || [[ $# == 1 && "$1" != "--check-signing" ]]; then
  echo "Usage: $0 [--check-signing]" >&2
  exit 1
fi

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "Ad hoc signing is not allowed for local installs: it breaks permission continuity." >&2
  exit 1
fi

IDENTITIES="$(security find-identity -v -p codesigning)"

identity_hash() {
  printf '%s\n' "$IDENTITIES" | awk -v requested="$1" '
    length($2) == 40 && $2 ~ /^[[:xdigit:]]+$/ {
      name = $0
      sub(/^[^"]*"/, "", name)
      sub(/"[^"]*$/, "", name)
      if ($2 == toupper(requested) || name == requested) print $2
    }
  '
}

if [[ -z "$SIGN_IDENTITY" ]]; then
  # Preserve the installed certificate even when both old and new app-name certificates exist.
  INSTALLED_SIGNATURE="$(codesign -dvv "$TARGET_APP" 2>&1 || true)"
  SIGN_IDENTITY="$(printf '%s\n' "$INSTALLED_SIGNATURE" | sed -n 's/^Authority=//p' | head -n 1)"
  if [[ -z "$SIGN_IDENTITY" ]]; then
    for candidate in "Hago Local Code Signing" "Worklog Local Code Signing"; do
      if [[ -n "$(identity_hash "$candidate")" ]]; then
        SIGN_IDENTITY="$candidate"
        break
      fi
    done
  fi
fi

SIGNING_HASH="$(identity_hash "$SIGN_IDENTITY")"
if [[ -z "$SIGNING_HASH" || "$SIGNING_HASH" == *$'\n'* ]]; then
  echo "No unique valid signing identity found for '${SIGN_IDENTITY:-Hago Local Code Signing}'." >&2
  echo "Set HAGO_CODE_SIGN_IDENTITY to a valid certificate name or SHA-1 fingerprint. The installed app was not changed." >&2
  exit 1
fi

if [[ "${1:-}" == "--check-signing" ]]; then
  echo "$SIGNING_HASH"
  exit 0
fi

cd "$ROOT_DIR"
"$ROOT_DIR/scripts/package-app.sh" release >/dev/null
codesign --force --deep --sign "$SIGNING_HASH" "$SOURCE_APP"
codesign --verify --deep --strict "$SOURCE_APP"

# Do not stop or replace the working app until the new bundle has a valid stable signature.
if pgrep -x "$APP_NAME" >/dev/null; then
  pkill -x "$APP_NAME" || true
  sleep 1
fi

rm -rf "$TARGET_APP"
ditto "$SOURCE_APP" "$TARGET_APP"
open -n "$TARGET_APP"

echo "$TARGET_APP"
