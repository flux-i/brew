#!/bin/zsh
set -euo pipefail
BREW_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BREW_ROOT"
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
mkdir -p build/module-cache
xcrun swiftc -parse-as-library -swift-version 5 -module-name BrewTests \
    -module-cache-path "$BREW_ROOT/build/module-cache" \
    Sources/BrewKit/*.swift Tests/BrewTests/SessionTests.swift -o build/BrewCoreTests
build/BrewCoreTests
