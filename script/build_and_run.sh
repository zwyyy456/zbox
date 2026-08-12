#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="zbox"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${TMPDIR:-/tmp}/zbox-derived-data"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/zbox.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/zbox"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -project "$ROOT_DIR/zbox.xcodeproj" \
  -scheme zbox \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  build

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate 'process == "zbox"'
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "tech.hyperseek.zbox"'
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
