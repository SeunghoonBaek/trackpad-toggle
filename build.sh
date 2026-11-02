#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="Trackpad Toggle.app"
mkdir -p "$app/Contents/MacOS"
swiftc -O -target arm64-apple-macos13.0 -framework AppKit -framework ServiceManagement \
  TrackpadToggle.swift -o "$app/Contents/MacOS/TrackpadToggle"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
printf 'Built: %s/%s\n' "$PWD" "$app"
