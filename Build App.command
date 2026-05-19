#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
if "$DIR/script/build_and_run.sh" --no-launch; then
  echo
  echo "Build finished. You can open dist/JMU Course Planner.app from Finder."
else
  echo
  echo "Build FAILED. Scroll up to see the error, or report it."
fi
read -r -p "Press Return to close this window."
