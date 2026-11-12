#!/usr/bin/env bash
# Build the public app and package it for a GitHub release.
#
# usage: script/package_release.sh "<release title>" <output-dir>
#
# Produces <output-dir>/<release title>.zip containing a folder named
# <release title> that holds "JMU Course Planner.app" and a static installation
# guide. The app is the default
# (public) build: universal, optimized, ad-hoc signed.
set -euo pipefail

TITLE="${1:?release title required}"
OUT_DIR="${2:?output directory required}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="JMU Course Planner.app"
GUIDE="$ROOT_DIR/docs/INSTALLATION.txt"
if [ ! -f "$GUIDE" ]; then
  echo "package_release.sh: installation guide is missing: $GUIDE" >&2
  exit 2
fi

# The title becomes a folder and file name; accept only release titles.
if ! [[ "$TITLE" =~ ^JMU\ Course\ Planner\ v[0-9A-Za-z.+-]+$ ]] || [[ "$TITLE" == *..* ]]; then
  echo "package_release.sh: invalid release title: $TITLE" >&2
  exit 2
fi

if [ -n "${SWIFT_BUILD_FLAGS:-}" ]; then
  echo "package_release.sh builds the public app only; unset SWIFT_BUILD_FLAGS." >&2
  exit 2
fi

# One packaging run at a time per checkout: builds share .build/ and dist/.
LOCK="$ROOT_DIR/.build/package_release.lock"
mkdir -p "$ROOT_DIR/.build"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "package_release.sh: another packaging run holds $LOCK" >&2
  exit 3
fi
STAGE=""
cleanup() { rm -rf "$LOCK"; [ -n "$STAGE" ] && rm -rf "$STAGE"; }
trap cleanup EXIT

SWIFT_BUILD_FLAGS="-c release --arch arm64 --arch x86_64" "$ROOT_DIR/script/build_and_run.sh" --no-launch >&2

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
STAGE="$(mktemp -d)"
mkdir -p "$STAGE/$TITLE"
cp "$GUIDE" "$STAGE/$TITLE/START HERE - Installation Guide.txt"
ditto --norsrc --noextattr --noqtn "$ROOT_DIR/dist/$APP_NAME" "$STAGE/$TITLE/$APP_NAME"
xattr -cr "$STAGE/$TITLE"
codesign --force --deep --sign - "$STAGE/$TITLE/$APP_NAME" >&2
codesign --verify --deep --strict "$STAGE/$TITLE/$APP_NAME" >&2

ZIP="$OUT_DIR/$TITLE.zip"
rm -f "$ZIP"
(cd "$STAGE" && ditto -c -k --norsrc --noextattr --keepParent "$TITLE" "$ZIP")
echo "$ZIP"
