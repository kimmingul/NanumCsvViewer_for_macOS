#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Nanum CSV Viewer"
VERSION="${VERSION:-1.10.0}"
APP_PATH="${APP_PATH:-$ROOT/dist/appstore/$APP_NAME.app}"
PKG_PATH="${PKG_PATH:-$ROOT/dist/appstore/Nanum-CSV-Viewer-AppStore-v$VERSION.pkg}"
INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-${MAC_INSTALLER_IDENTITY:-3rd Party Mac Developer Installer: MINGUL KIM (XB673TQF3A)}}"

if [[ ! -d "$APP_PATH" ]]; then
  "$ROOT/Scripts/build-appstore-app.sh"
fi

mkdir -p "$(dirname "$PKG_PATH")"
rm -f "$PKG_PATH"

productbuild \
  --component "$APP_PATH" /Applications \
  --sign "$INSTALLER_IDENTITY" \
  "$PKG_PATH"

pkgutil --check-signature "$PKG_PATH"

if [[ "${RUN_SPCTL:-0}" == "1" ]]; then
  spctl -a -vv --type install "$PKG_PATH"
fi

echo "Created App Store package: $PKG_PATH"
