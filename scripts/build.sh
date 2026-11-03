#!/bin/bash
set -euo pipefail
MB_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$MB_ROOT"
mkdir -p build/module-cache build/clang-cache
export CLANG_MODULE_CACHE_PATH="$MB_ROOT/build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$MB_ROOT/build/module-cache"
swift build -c release --scratch-path "$MB_ROOT/build/swift" --disable-sandbox
MB_APP="$MB_ROOT/MoonBridge.app"
mkdir -p "$MB_APP/Contents/MacOS" "$MB_APP/Contents/Resources/Art"
cp "$MB_ROOT/build/swift/release/MoonBridge" "$MB_APP/Contents/MacOS/MoonBridge"
cp "$MB_ROOT/Resources/Art/"*.png "$MB_APP/Contents/Resources/Art/"
cp "$MB_ROOT/Resources/Info.plist" "$MB_APP/Contents/Info.plist"
if [ -f "$MB_ROOT/Resources/MoonBridge.icns" ]; then cp "$MB_ROOT/Resources/MoonBridge.icns" "$MB_APP/Contents/Resources/"; fi
xattr -dr com.apple.FinderInfo "$MB_APP" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$MB_APP" 2>/dev/null || true
codesign --force --sign - "$MB_APP"
echo "Built $MB_APP"
