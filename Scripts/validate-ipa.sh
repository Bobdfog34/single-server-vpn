#!/usr/bin/env bash
set -euo pipefail

IPA="$1"
BUNDLE_ID="${2:-com.singleserver.vpn}"

unzip -tq "$IPA"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
unzip -q "$IPA" -d "$WORK"

APP=$(find "$WORK/Payload" -maxdepth 1 -name '*.app' -type d | head -n 1)
test -d "$APP"

ACTUAL=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
test "$ACTUAL" = "$BUNDLE_ID"

EXT="$APP/PlugIns/SingleServerVPNExtension.appex"
test -d "$EXT"
test -f "$EXT/SingleServerVPNExtension"
test -f "$APP/server.json"
test -f "$EXT/server.json"

codesign --verify --verbose "$APP"
