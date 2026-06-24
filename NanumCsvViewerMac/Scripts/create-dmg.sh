#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Nanum CSV Viewer"
APP_PATH="${APP_PATH:-$ROOT/dist/$APP_NAME.app}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  echo "Run Scripts/build-app.sh and Scripts/sign-app.sh first." >&2
  exit 1
fi

VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")}"
DMG_PATH="${DMG_PATH:-$ROOT/dist/Nanum-CSV-Viewer-v$VERSION.dmg}"
STAGING_DIR="$(mktemp -d "$ROOT/dist/dmg-stage.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

IDENTITY="${SIGN_IDENTITY:-${DEVID_APP:-}}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -n 1)"
fi

if [[ "${SKIP_DMG_SIGN:-0}" == "1" ]]; then
  echo "Skipping DMG signing because SKIP_DMG_SIGN=1."
elif [[ -n "$IDENTITY" ]]; then
  if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --sign "$IDENTITY" "$DMG_PATH"
  else
    codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"
  fi
  codesign --verify --verbose=2 "$DMG_PATH"
else
  echo "No Developer ID Application signing identity found; DMG left unsigned." >&2
fi

echo "Created: $DMG_PATH"
