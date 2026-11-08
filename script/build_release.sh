#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache"
for ARCHITECTURE in arm64 x86_64; do
  swift build --disable-sandbox --cache-path "$ROOT_DIR/.build/cache" --config-path "$ROOT_DIR/.build/config" --security-path "$ROOT_DIR/.build/security" -c release --arch "$ARCHITECTURE" --product EvidenceWorkbench
done
APP_BUNDLE="$ROOT_DIR/dist/EvidenceWorkbench.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
/usr/bin/lipo -create "$ROOT_DIR/.build/arm64-apple-macosx/release/EvidenceWorkbench" "$ROOT_DIR/.build/x86_64-apple-macosx/release/EvidenceWorkbench" -output "$APP_BUNDLE/Contents/MacOS/EvidenceWorkbench.new"
chmod +x "$APP_BUNDLE/Contents/MacOS/EvidenceWorkbench.new"
mv "$APP_BUNDLE/Contents/MacOS/EvidenceWorkbench.new" "$APP_BUNDLE/Contents/MacOS/EvidenceWorkbench"
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>EvidenceWorkbench</string>
<key>CFBundleIdentifier</key><string>com.matheusrech.EvidenceWorkbench</string>
<key>CFBundleName</key><string>Evidence Workbench</string>
<key>CFBundleDisplayName</key><string>Evidence Workbench</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
/usr/bin/lipo -info "$APP_BUNDLE/Contents/MacOS/EvidenceWorkbench"
echo "Universal release built. Ad-hoc signed; not notarized."
