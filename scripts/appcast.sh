#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${1:-$ROOT_DIR/outputs/Hago.app}"
DMG="${2:?Usage: appcast.sh Hago.app versioned.dmg [release-notes.md]}"
NOTES="${3:-}"
SPARKLE_DIR="$("$ROOT_DIR/scripts/sparkle.sh")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp "$DMG" "$STAGING/$(basename "$DMG")"
if [[ -n "$NOTES" ]]; then cp "$NOTES" "$STAGING/$(basename "$DMG" .dmg).md"; fi
OPTIONS=(--maximum-deltas 0 --embed-release-notes
  --download-url-prefix "https://github.com/0xIvan/hago/releases/download/v$VERSION/"
  --link "https://github.com/0xIvan/hago")
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_DIR/bin/generate_appcast" --ed-key-file - "${OPTIONS[@]}" "$STAGING"
else
  "$SPARKLE_DIR/bin/generate_appcast" --account hago-sparkle "${OPTIONS[@]}" "$STAGING"
fi
swift "$ROOT_DIR/scripts/verify-appcast.swift" "$APP_DIR/Contents/Info.plist" "$STAGING/appcast.xml" "$DMG"
cp "$STAGING/appcast.xml" "$(dirname "$DMG")/appcast.xml"
