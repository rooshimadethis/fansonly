#!/bin/bash
set -e

APP_NAME="FanControl.app"
INSTALL_DIR="${FANCONTROL_INSTALL_DIR:-$HOME/Applications}"
INSTALL_PATH="$INSTALL_DIR/$APP_NAME"

echo "=== Building FanControl ==="
./build.sh

echo "=== Installing to $INSTALL_PATH ==="
mkdir -p "$INSTALL_DIR"

if pgrep -x "FanControl" >/dev/null; then
    echo "FanControl is running. Asking it to quit before updating..."
    osascript -e 'tell application "FanControl" to quit' >/dev/null 2>&1 || true
    sleep 1
fi

rm -rf "$INSTALL_PATH"
ditto "$APP_NAME" "$INSTALL_PATH"

echo "=== Installed ==="
echo "Run with: open '$INSTALL_PATH'"
open "$INSTALL_PATH"
