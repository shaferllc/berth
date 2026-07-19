#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

echo "› Building release binary…"
swift build -c release

if [ ! -f AppIcon.icns ] || [ make-icon.swift -nt AppIcon.icns ]; then
  echo "› Generating AppIcon.icns…"
  swift make-icon.swift
fi

STAGE="$(mktemp -d)"
APP="$STAGE/Berth.app"
echo "› Assembling in staging: $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Berth "$APP/Contents/MacOS/Berth"
cp AppIcon.icns         "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>Berth</string>
    <key>CFBundleDisplayName</key>          <string>Berth</string>
    <key>CFBundleIdentifier</key>           <string>com.tomshafer.berth</string>
    <key>CFBundleVersion</key>              <string>1</string>
    <key>CFBundleShortVersionString</key>   <string>0.1</string>
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

DEST="/Applications/Berth.app"
echo "› Installing to $DEST"
/usr/bin/pkill -x Berth 2>/dev/null || true
/bin/sleep 0.3
rm -rf "$DEST"
/bin/mv "$APP" "$DEST"
rm -rf "$STAGE"
open "$DEST"
echo "› Installed and launched: $DEST"
