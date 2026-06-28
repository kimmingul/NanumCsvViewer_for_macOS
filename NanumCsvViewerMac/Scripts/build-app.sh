#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Nanum CSV Viewer"
BUNDLE="$ROOT/dist/$APP_NAME.app"
EXECUTABLE="$ROOT/.build/release/NanumCsvViewerMac"
ICON="$ROOT/Resources/AppIcon.icns"

cd "$ROOT"
swift build -c release

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$EXECUTABLE" "$BUNDLE/Contents/MacOS/NanumCsvViewerMac"

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
  <string>1.7.5</string>
  <key>CFBundleVersion</key>
  <string>175</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST

echo "Built: $BUNDLE"
