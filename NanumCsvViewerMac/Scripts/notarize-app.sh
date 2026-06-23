#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Nanum CSV Viewer"
APP_PATH="${APP_PATH:-$ROOT/dist/$APP_NAME.app}"
ZIP_PATH="${ZIP_PATH:-$ROOT/dist/$APP_NAME.zip}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  echo "Run Scripts/build-app.sh and Scripts/sign-app.sh first." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Submitting to Apple notarization service: $ZIP_PATH"

KEYCHAIN_PROFILE="${NOTARYTOOL_PROFILE:-${NOTARY_PROFILE:-}}"

if [[ -n "$KEYCHAIN_PROFILE" ]]; then
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait
elif [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
  ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
  if [[ ! -f "$ASC_KEY_PATH" ]]; then
    echo "App Store Connect API key not found: $ASC_KEY_PATH" >&2
    exit 1
  fi
  xcrun notarytool submit "$ZIP_PATH" \
    --key "$ASC_KEY_PATH" \
    --key-id "$ASC_KEY_ID" \
    --issuer "$ASC_ISSUER_ID" \
    --wait
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait
else
  cat >&2 <<'MESSAGE'
No notarization credentials configured.

Use one of these:

  NOTARYTOOL_PROFILE="profile-name" Scripts/notarize-app.sh

  NOTARY_PROFILE="profile-name" Scripts/notarize-app.sh

  ASC_KEY_ID="XXXXXXXXXX" \
  ASC_ISSUER_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
  Scripts/notarize-app.sh

or:

  APPLE_ID="you@example.com" \
  APPLE_TEAM_ID="TEAMID1234" \
  APPLE_APP_PASSWORD="app-specific-password" \
  Scripts/notarize-app.sh

Create a keychain profile with:

  xcrun notarytool store-credentials "profile-name" \
    --apple-id "you@example.com" \
    --team-id "TEAMID1234" \
    --password "app-specific-password"
MESSAGE
  exit 1
fi

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl -a -vv --type exec "$APP_PATH"

echo "Notarized and stapled: $APP_PATH"
