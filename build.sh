#!/bin/bash
set -e

echo "=== Building SMC Helper (C) ==="
clang -framework IOKit -framework Foundation smc_helper.c -o smc-helper

echo "=== Building SwiftUI App (Swift) ==="
SDK_PATH=$(xcrun --show-sdk-path)
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
swiftc -sdk "$SDK_PATH" -target arm64-apple-macosx14.0 -module-cache-path "$PWD/.build/module-cache" -framework Cocoa -framework SwiftUI -framework IOKit -framework ServiceManagement FanControlApp.swift MenuView.swift HelperManager.swift -o FanControl

echo "=== Packaging as FanControl.app ==="
mkdir -p FanControl.app/Contents/MacOS
mkdir -p FanControl.app/Contents/Resources

# Create Info.plist
cat <<EOF > FanControl.app/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FanControl</string>
    <key>CFBundleIdentifier</key>
    <string>com.rooshi.FanControl</string>
    <key>CFBundleName</key>
    <string>FanControl</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

# Copy binaries
cp FanControl FanControl.app/Contents/MacOS/FanControl
cp smc-helper FanControl.app/Contents/MacOS/smc-helper

echo "=== Build Successful! ==="
echo "You can find your application at: /Users/rooshi/Documents/programming/mac/fan/FanControl.app"
echo "To run, execute: open FanControl.app"
