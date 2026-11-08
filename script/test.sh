#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache"
swift test --disable-sandbox --cache-path "$ROOT_DIR/.build/cache" --config-path "$ROOT_DIR/.build/config" --security-path "$ROOT_DIR/.build/security" "$@"
