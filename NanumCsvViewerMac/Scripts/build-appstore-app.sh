#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Nanum CSV Viewer"
BUNDLE_ID="${BUNDLE_ID:-com.nanumspace.mgkim.nanumcsvviewer}"
VERSION="${VERSION:-1.10.0}"
BUILD_NUMBER="${BUILD_NUMBER:-200}"
APP_PATH="${APP_PATH:-$ROOT/dist/appstore/$APP_NAME.app}"
EXECUTABLE="$ROOT/.build/release/NanumCsvViewerMac"
IMPORT_SERVICE_EXECUTABLE="$ROOT/.build/release/ImportService"
IMPORT_SERVICE_ID="com.nanum.csvviewer.ImportService"
IMPORT_SERVICE_BUNDLE="$APP_PATH/Contents/XPCServices/$IMPORT_SERVICE_ID.xpc"
ICON="$ROOT/Resources/AppIcon.icns"
ENTITLEMENTS="${ENTITLEMENTS:-$ROOT/Config/AppStore.entitlements}"
SERVICE_ENTITLEMENTS="${SERVICE_ENTITLEMENTS:-$ROOT/Config/ImportService.entitlements}"
SIGN_IDENTITY="${SIGN_IDENTITY:-${APPLE_DISTRIBUTION:-Apple Distribution: MINGUL KIM (XB673TQF3A)}}"

cd "$ROOT"
swift build -c release --product NanumCsvViewerMac
swift build -c release --product ImportService

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$IMPORT_SERVICE_BUNDLE/Contents/MacOS"
cp "$EXECUTABLE" "$APP_PATH/Contents/MacOS/NanumCsvViewerMac"
cp "$IMPORT_SERVICE_EXECUTABLE" "$IMPORT_SERVICE_BUNDLE/Contents/MacOS/ImportService"

if [[ -f "$ICON" ]]; then
  cp "$ICON" "$APP_PATH/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>NanumCsvViewerMac</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>MacOSX</string>
  </array>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
  <key>ITSAppUsesNonExemptEncryption</key>
  <false/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 MINGUL KIM. All rights reserved.</string>
</dict>
</plist>
PLIST

cat > "$IMPORT_SERVICE_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>ImportService</string>
  <key>CFBundleIdentifier</key>
  <string>$IMPORT_SERVICE_ID</string>
  <key>CFBundleName</key>
  <string>ImportService</string>
  <key>CFBundlePackageType</key>
  <string>XPC!</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>XPCService</key>
  <dict>
    <key>ServiceType</key>
    <string>Application</string>
    <key>RunLoopType</key>
    <string>NSRunLoop</string>
  </dict>
</dict>
</plist>
PLIST

echo "Signing App Store app: $APP_PATH"
echo "Bundle ID: $BUNDLE_ID"
echo "Identity: $SIGN_IDENTITY"

codesign \
  --force \
  --options runtime \
  --entitlements "$SERVICE_ENTITLEMENTS" \
  --sign "$SIGN_IDENTITY" \
  "$IMPORT_SERVICE_BUNDLE"

codesign \
  --force \
  --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGN_IDENTITY" \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign --display --verbose=2 "$APP_PATH"
codesign -d --entitlements :- "$APP_PATH"

echo "Built App Store app: $APP_PATH"
