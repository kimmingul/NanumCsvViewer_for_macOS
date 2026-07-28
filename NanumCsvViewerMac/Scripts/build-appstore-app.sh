#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Nanum CSV Viewer"
BUNDLE_ID="${BUNDLE_ID:-com.nanumspace.mgkim.nanumcsvviewer}"
VERSION="${VERSION:-1.10.0}"
BUILD_NUMBER="${BUILD_NUMBER:-201}"
APP_PATH="${APP_PATH:-$ROOT/dist/appstore/$APP_NAME.app}"
EXECUTABLE="$ROOT/.build/release/NanumCsvViewerMac"
IMPORT_SERVICE_EXECUTABLE="$ROOT/.build/release/ImportService"
# Derive the XPC service bundle ID from the app bundle ID so the App Store
# requirement (nested bundle ID prefixed by the host app's) always holds.
IMPORT_SERVICE_ID="$BUNDLE_ID.ImportService"
IMPORT_SERVICE_BUNDLE="$APP_PATH/Contents/XPCServices/$IMPORT_SERVICE_ID.xpc"
ICON="$ROOT/Resources/AppIcon.icns"
ENTITLEMENTS="${ENTITLEMENTS:-$ROOT/Config/AppStore.entitlements}"
SERVICE_ENTITLEMENTS="${SERVICE_ENTITLEMENTS:-$ROOT/Config/ImportService.entitlements}"
SIGN_IDENTITY="${SIGN_IDENTITY:-${APPLE_DISTRIBUTION:-Apple Distribution: MINGUL KIM (XB673TQF3A)}}"
TEAM_ID="${TEAM_ID:-XB673TQF3A}"
# The signed entitlements must carry the app identifier, or the upload is barred
# from TestFlight (altool warning 90886) even though App Store review accepts it.
# Derive it from BUNDLE_ID the way IMPORT_SERVICE_ID is, so it cannot drift.
APP_IDENTIFIER="$TEAM_ID.$BUNDLE_ID"
DERIVED_ENTITLEMENTS="$ROOT/dist/appstore/entitlements-appstore.plist"
# Mac App Store distribution requires an embedded provisioning profile. Keep it
# out of git (it is developer-specific); provide it via PROVISION_PROFILE or the
# default path below.
PROVISION_PROFILE="${PROVISION_PROFILE:-$ROOT/Config/AppStore.provisionprofile}"

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

if [[ ! -f "$PROVISION_PROFILE" ]]; then
  cat >&2 <<MESSAGE
ERROR: Mac App Store provisioning profile not found at:
  $PROVISION_PROFILE

Download a "Mac App Store" distribution profile for App ID
  $BUNDLE_ID
from the Apple Developer portal, then either place it at that path or set:
  PROVISION_PROFILE=/path/to/profile.provisionprofile Scripts/build-appstore-app.sh

The embedded profile is required for App Store upload; refusing to build an
unsubmittable bundle.
MESSAGE
  exit 1
fi

# codesign never reads the provisioning profile, so a profile issued for another
# app ID passes every local check and only fails server-side at upload. Compare
# the two here and fail closed rather than build an unsubmittable bundle.
PROFILE_PLIST="$(mktemp -t appstore-profile)"
trap 'rm -f "$PROFILE_PLIST"' EXIT
security cms -D -i "$PROVISION_PROFILE" -o "$PROFILE_PLIST"
PROFILE_APP_IDENTIFIER="$(/usr/libexec/PlistBuddy \
  -c 'Print :Entitlements:com.apple.application-identifier' "$PROFILE_PLIST")"
if [[ "$PROFILE_APP_IDENTIFIER" != "$APP_IDENTIFIER" ]]; then
  cat >&2 <<MESSAGE
ERROR: the provisioning profile is issued for a different app identifier.
  profile: $PROFILE_APP_IDENTIFIER
  build:   $APP_IDENTIFIER

Regenerate the Mac App Store profile for $BUNDLE_ID, or set TEAM_ID/BUNDLE_ID
to match the profile.
MESSAGE
  exit 1
fi

# Embed the profile before signing so codesign seals it into the app bundle.
cp "$PROVISION_PROFILE" "$APP_PATH/Contents/embedded.provisionprofile"
echo "Embedded provisioning profile: $PROVISION_PROFILE"

# A profile downloaded through a browser carries com.apple.quarantine, and cp
# preserves extended attributes, so the attribute rides into the bundle and the
# upload is rejected with ITMS-91109. Strip every xattr from the whole bundle
# before signing rather than just the profile, since any copied-in resource can
# carry one.
xattr -cr "$APP_PATH"

# Build the signed entitlements from the checked-in template so the template
# stays free of developer-specific identifiers.
cp "$ENTITLEMENTS" "$DERIVED_ENTITLEMENTS"
/usr/libexec/PlistBuddy \
  -c "Set :com.apple.application-identifier $APP_IDENTIFIER" \
  "$DERIVED_ENTITLEMENTS" 2>/dev/null \
  || /usr/libexec/PlistBuddy \
    -c "Add :com.apple.application-identifier string $APP_IDENTIFIER" \
    "$DERIVED_ENTITLEMENTS"

echo "Signing App Store app: $APP_PATH"
echo "App identifier: $APP_IDENTIFIER"
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
  --entitlements "$DERIVED_ENTITLEMENTS" \
  --sign "$SIGN_IDENTITY" \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign --display --verbose=2 "$APP_PATH"
codesign -d --entitlements :- "$APP_PATH"

# Signing rewrites files and can reintroduce attributes, so check the finished
# bundle rather than trusting the strip above. Only com.apple.quarantine blocks
# ingestion (ITMS-91109); com.apple.provenance is added by the OS and allowed.
QUARANTINED="$(find "$APP_PATH" -exec sh -c 'xattr "$1" 2>/dev/null | grep -q com.apple.quarantine && echo "$1"' _ {} \;)"
if [[ -n "$QUARANTINED" ]]; then
  cat >&2 <<MESSAGE
ERROR: com.apple.quarantine survives on files inside the bundle:
$QUARANTINED

App Store ingestion rejects these with ITMS-91109. Run: xattr -cr "$APP_PATH"
MESSAGE
  exit 1
fi
echo "No quarantined files in bundle."

echo "Built App Store app: $APP_PATH"
