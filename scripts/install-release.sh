#!/usr/bin/env bash
set -euo pipefail

REPO="${HAGO_REPO:-0xIvan/hago}"
APP_NAME="Hago"
INSTALL_DIR="${HAGO_INSTALL_DIR:-/Applications}"
ARCHIVE_URL="${HAGO_ARCHIVE_URL:-}"
TARGET_APP="$INSTALL_DIR/$APP_NAME.app"
TEMP_DIR="$(mktemp -d)"
cleanup() {
  if [[ -d "$TEMP_DIR/previous.app" && ! -d "$TARGET_APP" ]]; then
    echo "Previous app retained for recovery at $TEMP_DIR/previous.app" >&2
    return
  fi
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

if [[ -z "$ARCHIVE_URL" ]]; then
  curl --fail --silent --show-error --location "https://api.github.com/repos/$REPO/releases/latest" --output "$TEMP_DIR/release.json"
  python3 - "$TEMP_DIR/release.json" "$TEMP_DIR/urls" <<'PY'
import json,pathlib,sys
assets={x['name']:x['browser_download_url'] for x in json.load(open(sys.argv[1]))['assets']}
pathlib.Path(sys.argv[2]).write_text(assets['Hago.app.zip']+'\n'+assets['Hago.app.zip.sha256']+'\n')
PY
  ARCHIVE_URL="$(sed -n '1p' "$TEMP_DIR/urls")"
  CHECKSUM_URL="$(sed -n '2p' "$TEMP_DIR/urls")"
else
  CHECKSUM_URL="${HAGO_CHECKSUM_URL:-$ARCHIVE_URL.sha256}"
fi

curl --fail --location --progress-bar "$ARCHIVE_URL" --output "$TEMP_DIR/Hago.app.zip"
curl --fail --silent --show-error --location "$CHECKSUM_URL" --output "$TEMP_DIR/Hago.app.zip.sha256"
python3 - "$TEMP_DIR/Hago.app.zip.sha256" <<'PY_CHECKSUM'
import pathlib,re,sys
assert re.fullmatch(r'[0-9a-fA-F]{64} [ *]Hago\.app\.zip\n?',pathlib.Path(sys.argv[1]).read_text()), 'Unexpected checksum manifest'
PY_CHECKSUM
(cd "$TEMP_DIR" && shasum -a 256 -c Hago.app.zip.sha256)
ditto -x -k "$TEMP_DIR/Hago.app.zip" "$TEMP_DIR"
APP="$TEMP_DIR/Hago.app"
[[ -d "$APP" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == com.ivan.hago ]]
codesign --verify --deep --strict "$APP"
TEAM="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
[[ "$TEAM" == AB879DAVK8 ]] || { echo 'Unexpected signing team.' >&2; exit 1; }
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

if pgrep -x "$APP_NAME" >/dev/null; then
  pkill -x "$APP_NAME" || true
  sleep 1
fi

if [[ -w "$INSTALL_DIR" ]]; then
  if [[ -d "$TARGET_APP" ]]; then mv "$TARGET_APP" "$TEMP_DIR/previous.app"; fi
  if ! ditto "$APP" "$TARGET_APP"; then
    rm -rf "$TARGET_APP"
    if [[ -d "$TEMP_DIR/previous.app" ]]; then mv "$TEMP_DIR/previous.app" "$TARGET_APP"; fi
    exit 1
  fi
else
  if [[ -d "$TARGET_APP" ]]; then sudo mv "$TARGET_APP" "$TEMP_DIR/previous.app"; fi
  if ! sudo ditto "$APP" "$TARGET_APP"; then
    sudo rm -rf "$TARGET_APP"
    if [[ -d "$TEMP_DIR/previous.app" ]]; then sudo mv "$TEMP_DIR/previous.app" "$TARGET_APP"; fi
    exit 1
  fi
fi
open -n "$TARGET_APP"
echo "Installed $TARGET_APP"
