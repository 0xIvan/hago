#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${1:-$ROOT_DIR/outputs/Hago.app}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
ARCH="$(lipo -archs "$APP_DIR/Contents/MacOS/Hago" | tr ' ' '-')"
OUTPUT_DIR="${2:-$ROOT_DIR/outputs}"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
NAME="Hago-$VERSION-$ARCH"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
codesign --verify --deep --strict "$APP_DIR"
ditto "$APP_DIR" "$STAGING/Hago.app"
ln -s /Applications "$STAGING/Applications"
[[ ! -e "$OUTPUT_DIR/$NAME.dmg" ]] || { echo "DMG already exists." >&2; exit 1; }
hdiutil create -volname "Hago $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$OUTPUT_DIR/$NAME.dmg"
if [[ -n "${HAGO_CODE_SIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$HAGO_CODE_SIGN_IDENTITY" --timestamp "$OUTPUT_DIR/$NAME.dmg"
fi
hdiutil verify "$OUTPUT_DIR/$NAME.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$OUTPUT_DIR/$NAME.zip"
(cd "$OUTPUT_DIR" && shasum -a 256 "$NAME.dmg" "$NAME.zip" > "$NAME.sha256")
printf '%s\n' "$OUTPUT_DIR/$NAME.dmg"
