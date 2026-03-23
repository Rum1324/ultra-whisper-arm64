#!/bin/bash

# Script to copy built app to /Applications folder
# This runs after the Flutter build completes

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

APP_PATH="$PROJECT_ROOT/build/macos/Build/Products/Release/UltraWhisper.app"
DEST_PATH="/Applications/UltraWhisper.app"

# Check if the built app exists
if [ ! -d "$APP_PATH" ]; then
    echo "Error: Built app not found at $APP_PATH"
    echo "Please run 'flutter build macos --release' first"
    exit 1
fi

echo "Copying UltraWhisper to Applications folder..."

# Kill running app if it exists
if pgrep -x "UltraWhisper" > /dev/null; then
    echo "Stopping running UltraWhisper..."
    killall UltraWhisper || true
    sleep 1
fi

# Remove old app if it exists
if [ -d "$DEST_PATH" ]; then
    echo "Removing old version from Applications..."
    rm -rf "$DEST_PATH"
fi

# Copy new app to Applications
echo "Copying new version to Applications..."
cp -R "$APP_PATH" "$DEST_PATH"

# Verify the copy
if [ -d "$DEST_PATH" ]; then
    echo "✅ Successfully copied UltraWhisper to /Applications"
    echo "   App size: $(du -sh "$DEST_PATH" | cut -f1)"
else
    echo "❌ Failed to copy app to Applications"
    exit 1
fi

echo ""
echo "You can now launch UltraWhisper from:"
echo "  - Applications folder in Finder"
echo "  - Spotlight search"
echo "  - Command line: open /Applications/UltraWhisper.app"