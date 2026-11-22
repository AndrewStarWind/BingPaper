#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT_DIR/Scripts/build-app.sh"

SRC_APP="$ROOT_DIR/dist/BingPaper.app"
DEST_APP="/Applications/BingPaper.app"

echo "==> Installing BingPaper.app to /Applications..."
rm -rf "$DEST_APP"
cp -R "$SRC_APP" "$DEST_APP"

echo "==> Installed at $DEST_APP"
echo "    Launch it with: open /Applications/BingPaper.app"
