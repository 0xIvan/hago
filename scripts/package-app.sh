#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP_NAME="Hago"
VERSION="${HAGO_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")}"
BUILD_NUMBER="${HAGO_BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$ROOT_DIR/Resources/Info.plist")}"
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' && "$BUILD_NUMBER" =~ '^[0-9]+(\.[0-9]+){0,2}$' ]] || { echo "Invalid release version or build number." >&2; exit 1; }
APP_DIR="$ROOT_DIR/outputs/$APP_NAME.app"

cd "$ROOT_DIR"
BUILD_ARGS=(-c "$CONFIGURATION" --product "$APP_NAME")
if [[ -n "${HAGO_ARCHS:-}" ]]; then
  for architecture in ${=HAGO_ARCHS}; do
    [[ "$architecture" == arm64 || "$architecture" == x86_64 ]] || { echo "Unsupported architecture." >&2; exit 1; }
    BUILD_ARGS+=(--arch "$architecture")
  done
fi
swift build "${BUILD_ARGS[@]}"
BUILD_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
EXECUTABLE_PATH="$BUILD_DIR/$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
SPARKLE_DIR="$("$ROOT_DIR/scripts/sparkle.sh")"
mkdir -p "$APP_DIR/Contents/Frameworks"
ditto "$SPARKLE_DIR/Sparkle.framework" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
cp "$SPARKLE_DIR/LICENSE" "$APP_DIR/Contents/Resources/Sparkle-LICENSE.txt"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/Resources/AppIcon.png" "$APP_DIR/Contents/Resources/AppIcon.png"
cp "$ROOT_DIR/Resources/AppIcon-dark.png" "$APP_DIR/Contents/Resources/AppIcon-dark.png"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

echo "$APP_DIR"
