#!/usr/bin/env bash
# Build the public app and package it for a GitHub release.
#
# usage: script/package_release.sh "<release title>" <output-dir>
#
# Produces <output-dir>/<release title>.zip containing a folder named
# <release title> that holds "JMU Course Planner.app". The app is the default
# (public) build: universal, optimized, ad-hoc signed.
set -euo pipefail

TITLE="${1:?release title required}"
OUT_DIR="${2:?output directory required}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="JMU Course Planner.app"

if [ -n "${SWIFT_BUILD_FLAGS:-}" ]; then
  echo "package_release.sh builds the public app only; unset SWIFT_BUILD_FLAGS." >&2
  exit 2
fi

SWIFT_BUILD_FLAGS="-c release --arch arm64 --arch x86_64" "$ROOT_DIR/script/build_and_run.sh" --no-launch >&2

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$TITLE"
ditto --norsrc --noextattr --noqtn "$ROOT_DIR/dist/$APP_NAME" "$STAGE/$TITLE/$APP_NAME"
xattr -cr "$STAGE/$TITLE"
codesign --force --deep --sign - "$STAGE/$TITLE/$APP_NAME" >&2
codesign --verify --deep --strict "$STAGE/$TITLE/$APP_NAME" >&2

ZIP="$OUT_DIR/$TITLE.zip"
rm -f "$ZIP"
(cd "$STAGE" && ditto -c -k --norsrc --noextattr --keepParent "$TITLE" "$ZIP")
echo "$ZIP"
