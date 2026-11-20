#!/usr/bin/env bash
set -euo pipefail

APP="$1"
OUT="$2"

case "$OUT" in
  /*) ABS_OUT="$OUT" ;;
  *) ABS_OUT="$PWD/$OUT" ;;
esac

test -d "$APP"
APP_NAME=$(basename "$APP")
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/Payload"
cp -R "$APP" "$WORK/Payload/$APP_NAME"
find "$WORK/Payload" -name '.DS_Store' -delete

for EXT in "$WORK/Payload/$APP_NAME"/PlugIns/*.appex; do
  if [ -d "$EXT" ]; then
    codesign --force --sign - --timestamp=none --generate-entitlement-der "$EXT"
  fi
done

codesign --force --sign - --timestamp=none --generate-entitlement-der "$WORK/Payload/$APP_NAME"
(cd "$WORK" && /usr/bin/zip -qry -X "$ABS_OUT" Payload)
test -s "$ABS_OUT"
