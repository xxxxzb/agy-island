#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$DIR/build/AgyIsland.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"
cp "$DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

swiftc -O -parse-as-library \
  -framework AppKit \
  -framework SwiftUI \
  -framework Combine \
  -lsqlite3 \
  "$DIR/Sources/Models.swift" \
  "$DIR/Sources/CapsuleService.swift" \
  "$DIR/Sources/IslandView.swift" \
  "$DIR/Sources/AppMain.swift" \
  -o "$MACOS_DIR/AgyIsland"

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
echo "Built: $APP_DIR"
