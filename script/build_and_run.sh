#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
PRODUCT_NAME="JMUCoursePlanner"
APP_NAME="JMU Course Planner"
BUNDLE_ID="edu.jmu.courseplanner.local"
MIN_SYSTEM_VERSION="14.0"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
SEMANTIC_VERSION="$(tr -d '\n' < "$ROOT_DIR/VERSION")"
VERSION_WITHOUT_METADATA="${SEMANTIC_VERSION%%+*}"
MARKETING_VERSION="${MARKETING_VERSION:-${VERSION_WITHOUT_METADATA%%-*}}"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$PRODUCT_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"

pkill -x "$PRODUCT_NAME" >/dev/null 2>&1 || true

read -r -a EXTRA_BUILD_FLAGS <<< "${SWIFT_BUILD_FLAGS:-}"
swift build --disable-sandbox ${EXTRA_BUILD_FLAGS[@]+"${EXTRA_BUILD_FLAGS[@]}"}
BUILD_BINARY="$(swift build --disable-sandbox ${EXTRA_BUILD_FLAGS[@]+"${EXTRA_BUILD_FLAGS[@]}"} --show-bin-path)/$PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ROOT_DIR/Data/catalog_seed.json" "$APP_RESOURCES/catalog_seed.json"
cp "$ROOT_DIR/Data/catalog_snapshot.json" "$APP_RESOURCES/catalog_snapshot.json"
cp "$ROOT_DIR/Data/prereq_coreq_overrides.json" "$APP_RESOURCES/prereq_coreq_overrides.json"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>JMUPlannerSemanticVersion</key>
  <string>$SEMANTIC_VERSION</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --no-launch|no-launch)
    echo "Built $APP_BUNDLE"
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PRODUCT_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$PRODUCT_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--no-launch|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
