#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
COMMON="$(git rev-parse --path-format=absolute --git-common-dir)"
DEST="$COMMON/release-policy-hooks"
EXISTING="$(git config --get core.hooksPath || true)"
if [ -n "$EXISTING" ] && [ "$EXISTING" != "$DEST" ]; then
  echo "Existing hooksPath $EXISTING: integrate commit validation there; refusing to replace it." >&2
  exit 1
fi
if [ -z "$EXISTING" ] && [ -f "$COMMON/hooks/commit-msg" ]; then
  echo 'Existing commit-msg hook found; integrate validation before installing.' >&2
  exit 1
fi
mkdir -p "$DEST"
# Preserve all existing non-sample hooks in the shared location.
for HOOK in "$COMMON"/hooks/*; do
  [ -f "$HOOK" ] || continue
  case "$HOOK" in *.sample) continue ;; esac
  cp -p "$HOOK" "$DEST/"
done
cp "$ROOT/script/release-commit-msg" "$DEST/commit-msg"
chmod +x "$DEST/commit-msg"
git config --local core.hooksPath "$DEST"
echo "Installed shared commit validation: $DEST"
