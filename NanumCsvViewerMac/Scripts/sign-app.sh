#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Nanum CSV Viewer"
APP_PATH="${APP_PATH:-$ROOT/dist/$APP_NAME.app}"
ENTITLEMENTS="${ENTITLEMENTS:-$ROOT/Config/Release.entitlements}"
SERVICE_ENTITLEMENTS="${SERVICE_ENTITLEMENTS:-$ROOT/Config/ImportService.entitlements}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  echo "Run Scripts/build-app.sh first." >&2
  exit 1
fi

IDENTITY="${SIGN_IDENTITY:-${DEVID_APP:-}}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -n 1)"
fi

if [[ -z "$IDENTITY" ]]; then
  echo "No Developer ID Application signing identity found." >&2
  echo "Install the certificate from Xcode > Settings > Accounts > Manage Certificates." >&2
  echo "Or pass SIGN_IDENTITY=\"Developer ID Application: ...\"." >&2
  echo "The notepad_macOS-compatible DEVID_APP variable is also supported." >&2
  exit 1
fi

echo "Signing: $APP_PATH"
echo "Identity: $IDENTITY"

while IFS= read -r -d '' service; do
  echo "Signing XPC service: $service"
  if [[ "$IDENTITY" == "-" ]]; then
    codesign \
      --force \
      --options runtime \
      --entitlements "$SERVICE_ENTITLEMENTS" \
      --sign "$IDENTITY" \
      "$service"
  else
    codesign \
      --force \
      --timestamp \
      --options runtime \
      --entitlements "$SERVICE_ENTITLEMENTS" \
      --sign "$IDENTITY" \
      "$service"
  fi
done < <(find "$APP_PATH/Contents/XPCServices" -name '*.xpc' -type d -print0 2>/dev/null || true)

if [[ "$IDENTITY" == "-" ]]; then
  codesign \
    --force \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" \
    "$APP_PATH"
else
  codesign \
    --force \
    --timestamp \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" \
    "$APP_PATH"
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign --display --verbose=2 "$APP_PATH"

echo "Signed: $APP_PATH"
