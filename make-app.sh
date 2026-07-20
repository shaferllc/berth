#!/bin/bash
# Build Berth.app (via build-app.sh), install it to /Applications, launch it.
set -euo pipefail
cd "$(dirname "$0")"

./build-app.sh

DEST="/Applications/Berth.app"
echo "› Installing to $DEST"
/usr/bin/pkill -x Berth 2>/dev/null || true
/bin/sleep 0.3
rm -rf "$DEST"
cp -R dist/Berth.app "$DEST"
open "$DEST"
echo "› Installed and launched: $DEST"
