#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:---build-only}"
case "$MODE" in --build-only|--release|--run) ;; *) echo 'Usage: build_review.sh [--build-only|--release|--run]' >&2; exit 2 ;; esac
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache"
OPTIONS=(--disable-sandbox --cache-path "$ROOT_DIR/.build/cache" --config-path "$ROOT_DIR/.build/config" --security-path "$ROOT_DIR/.build/security")
APP="$ROOT_DIR/dist/EvidenceWorkbenchReview.app"
mkdir -p "$APP/Contents/MacOS"
if [ "$MODE" = '--release' ]; then
  for ARCH in arm64 x86_64; do swift build "${OPTIONS[@]}" -c release --arch "$ARCH" --product EvidenceWorkbench; done
  /usr/bin/lipo -create "$ROOT_DIR/.build/arm64-apple-macosx/release/EvidenceWorkbench" "$ROOT_DIR/.build/x86_64-apple-macosx/release/EvidenceWorkbench" -output "$APP/Contents/MacOS/EvidenceWorkbenchReview"
else
  swift build "${OPTIONS[@]}" --product EvidenceWorkbench
  BIN_DIR="$(swift build "${OPTIONS[@]}" --show-bin-path)"
  cp "$BIN_DIR/EvidenceWorkbench" "$APP/Contents/MacOS/EvidenceWorkbenchReview"
fi
BUILD_COMMIT="$(git rev-parse HEAD 2>/dev/null || cat SOURCE-REVISION.txt 2>/dev/null || printf 'unversioned')"
BUILD_SOURCE_HASH="$(python3 - <<'PYHASH'
from pathlib import Path
import hashlib
root=Path.cwd();digest=hashlib.sha256()
files=[root/'Package.swift']
for directory in ['Sources','script']:
    files.extend(p for p in (root/directory).rglob('*') if p.is_file() and '__pycache__' not in p.parts and not p.name.endswith('.pyc'))
for path in sorted(files):
    digest.update(str(path.relative_to(root)).encode());digest.update(b'\0');digest.update(path.read_bytes());digest.update(b'\0')
print(digest.hexdigest())
PYHASH
)"
export APP BUILD_COMMIT BUILD_SOURCE_HASH
python3 - <<'PY'
import os, pathlib, plistlib
app=pathlib.Path(os.environ['APP'])
p={'CFBundleExecutable':'EvidenceWorkbenchReview','CFBundleIdentifier':'com.matheusrech.EvidenceWorkbench.Review','CFBundleName':'Evidence Workbench Review','CFBundleDisplayName':'Evidence Workbench Review','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.5.0','CFBundleVersion':'5','LSMinimumSystemVersion':'14.0','NSPrincipalClass':'NSApplication','NSHighResolutionCapable':True,'EWIsolatedReview':True,'EWBuildBaseCommit':os.environ['BUILD_COMMIT'],'EWBuildSourceDiffSHA256':os.environ['BUILD_SOURCE_HASH']}
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(p))
PY
chmod +x "$APP/Contents/MacOS/EvidenceWorkbenchReview"
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
/usr/bin/lipo -info "$APP/Contents/MacOS/EvidenceWorkbenchReview"
if [ "$MODE" = '--run' ]; then /usr/bin/open -n "$APP" --args --workspace "$ROOT_DIR/ReviewData"; fi
printf 'Isolated review built: %s\n' "$APP"
