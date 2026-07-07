#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Nanum CSV Viewer"
BUNDLE="$ROOT/dist/$APP_NAME.app"
EXECUTABLE="$ROOT/.build/release/NanumCsvViewerMac"
IMPORT_SERVICE_EXECUTABLE="$ROOT/.build/release/ImportService"
IMPORT_SERVICE_ID="com.nanum.csvviewer.ImportService"
IMPORT_SERVICE_BUNDLE="$BUNDLE/Contents/XPCServices/$IMPORT_SERVICE_ID.xpc"
ICON="$ROOT/Resources/AppIcon.icns"

cd "$ROOT"
swift build -c release --product NanumCsvViewerMac
swift build -c release --product ImportService

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources" "$IMPORT_SERVICE_BUNDLE/Contents/MacOS"
cp "$EXECUTABLE" "$BUNDLE/Contents/MacOS/NanumCsvViewerMac"
cp "$IMPORT_SERVICE_EXECUTABLE" "$IMPORT_SERVICE_BUNDLE/Contents/MacOS/ImportService"

if [[ -f "$ICON" ]]; then
  cp "$ICON" "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>NanumCsvViewerMac</string>
  <key>CFBundleIdentifier</key>
  <string>com.nanum.csvviewer.mac</string>
  <key>CFBundleName</key>
  <string>Nanum CSV Viewer</string>
  <key>CFBundleDisplayName</key>
  <string>Nanum CSV Viewer</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.10.0</string>
  <key>CFBundleVersion</key>
  <string>200</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST

cat > "$IMPORT_SERVICE_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>ImportService</string>
  <key>CFBundleIdentifier</key>
  <string>com.nanum.csvviewer.ImportService</string>
  <key>CFBundleName</key>
  <string>ImportService</string>
  <key>CFBundlePackageType</key>
  <string>XPC!</string>
  <key>CFBundleShortVersionString</key>
  <string>1.10.0</string>
  <key>CFBundleVersion</key>
  <string>200</string>
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

echo "Built: $BUNDLE"
