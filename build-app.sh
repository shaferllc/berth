#!/bin/bash
# Build a distributable Berth.app into dist/. Used by make-app.sh locally and
# by the release workflow on CI.
#
#   VERSION=x.y.z    stamp the bundle (defaults to the VERSION file)
#   --universal      build for arm64 and x86_64, as anything shipped must be
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION 2>/dev/null || echo 0.0.0-dev)}"
UNIVERSAL=""
[ "${1:-}" = "--universal" ] && UNIVERSAL=1

# Local builds are for this machine; anything people download has to run on
# both architectures, or it's a broken download for every Intel Mac.
if [ -n "$UNIVERSAL" ]; then
  echo "› Building universal release binary…"
  swift build -c release --arch arm64 --arch x86_64
  BIN=".build/apple/Products/Release/Berth"
else
  echo "› Building release binary…"
  swift build -c release
  BIN=".build/release/Berth"
fi

if [ ! -f AppIcon.icns ] || [ make-icon.swift -nt AppIcon.icns ]; then
  echo "› Generating AppIcon.icns…"
  swift make-icon.swift
fi

APP="dist/Berth.app"
echo "› Assembling $APP (version $VERSION)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN"       "$APP/Contents/MacOS/Berth"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>Berth</string>
    <key>CFBundleDisplayName</key>          <string>Berth</string>
    <key>CFBundleIdentifier</key>           <string>com.tomshafer.berth</string>
    <key>CFBundleVersion</key>              <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>   <string>${VERSION}</string>
    <key>CFBundleExecutable</key>           <string>Berth</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleSupportedPlatforms</key>   <array><string>MacOSX</string></array>
    <key>CFBundleIconFile</key>             <string>AppIcon</string>
    <key>CFBundleIconName</key>             <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>       <string>14.0</string>
    <key>NSHighResolutionCapable</key>      <true/>
    <key>NSHumanReadableCopyright</key>     <string>© 2026 Tom Shafer</string>
    <!-- Accept web URLs dragged onto the Dock icon. -->
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>     <string>Web URL</string>
            <key>CFBundleTypeRole</key>     <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array><string>public.url</string></array>
        </dict>
    </array>
    <!-- Metadata fetch must reach plain-http sites too. -->
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>   <true/>
    </dict>
</dict>
</plist>
PLIST

xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "› Built: $APP"
