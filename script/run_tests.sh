#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"

cd "$ROOT_DIR"
swift test --disable-sandbox
