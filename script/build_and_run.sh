#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
APP_NAME="EvidenceWorkbench"
BUNDLE_ID="com.matheusrech.EvidenceWorkbench"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
case "$MODE" in run|--debug|--logs|--telemetry|--verify|--build-only) ;; *) echo "Usage: $0 [run|--debug|--logs|--telemetry|--verify|--build-only]" >&2; exit 2 ;; esac
cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache"
if [ "$MODE" != "--build-only" ]; then pkill -x "$APP_NAME" >/dev/null 2>&1 || true; fi
swift build --disable-sandbox --cache-path "$ROOT_DIR/.build/cache" --config-path "$ROOT_DIR/.build/config" --security-path "$ROOT_DIR/.build/security" --product "$APP_NAME"
BUILD_BINARY="$(swift build --disable-sandbox --cache-path "$ROOT_DIR/.build/cache" --config-path "$ROOT_DIR/.build/config" --security-path "$ROOT_DIR/.build/security" --show-bin-path)/$APP_NAME"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BUILD_BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
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
touch "$APP_BUNDLE"
open_app() { /usr/bin/open -n -a "$APP_BUNDLE" --args --workspace "$ROOT_DIR/LocalData"; }
case "$MODE" in
  --build-only) echo "Built $APP_BUNDLE" ;;
  run) open_app ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" --workspace "$ROOT_DIR/LocalData" ;;
  --logs) open_app; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
  --telemetry) open_app; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
  --verify) open_app; sleep 1; pgrep -x "$APP_NAME" >/dev/null; echo "Built and launched $APP_NAME" ;;
esac
