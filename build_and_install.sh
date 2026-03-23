#!/bin/bash

# Complete build and install script for UltraWhisper
# This script builds the app and installs it to /Applications

set -e

echo "========================================="
echo "UltraWhisper Build & Install Script"
echo "========================================="
echo ""

# Build the Flutter app
echo "Step 1: Building Flutter app (Release mode)..."
echo "-----------------------------------------"
flutter build macos --release

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

echo ""
echo "✅ Build completed successfully!"
echo ""

# Copy to Applications
echo "Step 2: Installing to Applications folder..."
echo "-----------------------------------------"
./macos/Scripts/copy_to_applications.sh

if [ $? -ne 0 ]; then
    echo "❌ Installation failed!"
    exit 1
fi

echo ""
echo "========================================="
echo "✅ Build and installation complete!"
echo "========================================="
echo ""
echo "UltraWhisper has been successfully built and installed to /Applications"
echo ""
echo "Launch options:"
echo "  1. Open from Applications folder in Finder"
echo "  2. Use Spotlight search (Cmd+Space, type 'UltraWhisper')"
echo "  3. From Terminal: open /Applications/UltraWhisper.app"
echo ""