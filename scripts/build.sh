#!/bin/zsh
set -euo pipefail
BREW_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BREW_ROOT"
if [[ "${1:-}" == "--standalone" ]]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
else
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi
export CLANG_MODULE_CACHE_PATH="$BREW_ROOT/build/module-cache"
mkdir -p "$BREW_ROOT/build/Brew.iconset" "$BREW_ROOT/dist"
xcrun swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" scripts/GenerateIcon.swift "$BREW_ROOT/build/Brew.iconset"
python3 scripts/package_icon.py
python3 scripts/generate_project.py
if [[ "${1:-}" == "--standalone" ]]; then
    mkdir -p "$BREW_ROOT/dist/Brew.app/Contents/MacOS" "$BREW_ROOT/dist/Brew.app/Contents/Resources"
    BREW_ARCH="$(uname -m)"
    BREW_SDK="$(xcrun --sdk macosx --show-sdk-path)"
    xcrun swiftc -parse-as-library -swift-version 5 -O -module-name Brew -target "$BREW_ARCH-apple-macos13.0" \
        -sdk "$BREW_SDK" -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
        Sources/BrewKit/*.swift Sources/Brew/Entry.swift -o "$BREW_ROOT/dist/Brew.app/Contents/MacOS/Brew" \
        > "$BREW_ROOT/build/standalone-build.log" 2>&1 || {
        tail -n 80 "$BREW_ROOT/build/standalone-build.log"
        exit 1
    }
    python3 - <<'PY'
import plistlib
from pathlib import Path
p = plistlib.loads(Path('Resources/Info.plist').read_bytes())
p.update(CFBundleIdentifier='app.local.brew', CFBundleExecutable='Brew', LSMinimumSystemVersion='13.0', BrewNativeShortcuts=False)
Path('dist/Brew.app/Contents/Info.plist').write_bytes(plistlib.dumps(p))
PY
    cp Resources/Brew.icns Resources/Brew.sdef "$BREW_ROOT/dist/Brew.app/Contents/Resources/"
    codesign --force --sign - --options runtime "$BREW_ROOT/dist/Brew.app"
else
    xcodebuild -project Brew.xcodeproj -scheme Brew -configuration Release \
        -derivedDataPath "$BREW_ROOT/build/xcode" -destination 'platform=macOS' \
        CODE_SIGN_IDENTITY=- build > "$BREW_ROOT/build/xcode-build.log" 2>&1 || {
        tail -n 80 "$BREW_ROOT/build/xcode-build.log"
        exit 1
    }
    ditto "$BREW_ROOT/build/xcode/Build/Products/Release/Brew.app" "$BREW_ROOT/dist/Brew.app"
fi
codesign --verify --deep --strict "$BREW_ROOT/dist/Brew.app"
ditto -c -k --sequesterRsrc --keepParent "$BREW_ROOT/dist/Brew.app" "$BREW_ROOT/dist/Brew.zip"
print "Built $BREW_ROOT/dist/Brew.app"
print "Packaged $BREW_ROOT/dist/Brew.zip"
