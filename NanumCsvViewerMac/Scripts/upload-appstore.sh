#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-1.10.0}"
PKG_PATH="${PKG_PATH:-$ROOT/dist/appstore/Nanum-CSV-Viewer-AppStore-v$VERSION.pkg}"

if [[ ! -f "$PKG_PATH" ]]; then
  "$ROOT/Scripts/package-appstore.sh"
fi

if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
  xcrun altool --validate-app "$PKG_PATH" --api-key "$ASC_KEY_ID" --api-issuer "$ASC_ISSUER_ID"
  xcrun altool --upload-package "$PKG_PATH" --api-key "$ASC_KEY_ID" --api-issuer "$ASC_ISSUER_ID" --wait
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" && -n "${APPLE_PROVIDER_PUBLIC_ID:-}" ]]; then
  xcrun altool --validate-app "$PKG_PATH" \
    --username "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --provider-public-id "$APPLE_PROVIDER_PUBLIC_ID"
  xcrun altool --upload-package "$PKG_PATH" \
    --username "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --provider-public-id "$APPLE_PROVIDER_PUBLIC_ID" \
    --wait
else
  cat >&2 <<'MESSAGE'
Missing App Store Connect upload credentials.

Use an App Store Connect API key:

  ASC_KEY_ID="XXXXXXXXXX" \
  ASC_ISSUER_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
  Scripts/upload-appstore.sh

The private key file must be available where altool can find it, such as:

  ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8

Or use Apple ID authentication:

  APPLE_ID="you@example.com" \
  APPLE_APP_PASSWORD="app-specific-password" \
  APPLE_PROVIDER_PUBLIC_ID="provider-id" \
  Scripts/upload-appstore.sh

You can list providers after credentials are configured with:

  xcrun altool --list-providers --username "$APPLE_ID" --password "$APPLE_APP_PASSWORD"
MESSAGE
  exit 1
fi
