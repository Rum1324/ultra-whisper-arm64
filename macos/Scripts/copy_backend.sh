#!/bin/bash

# This script copies the backend (whisper.cpp + Python server) into the macOS app bundle
# during the build process for v3.

set -e

echo "Copying backend to app bundle (v3 - whisper.cpp)..."

# The Flutter build sets these environment variables
BUNDLE_RESOURCES="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources"
PROJECT_DIR="${SRCROOT}/../"

# Create backend directory in Resources
mkdir -p "${BUNDLE_RESOURCES}/backend"

# Copy the Python server and wrapper
echo "Copying backend/server.py..."
cp -f "${PROJECT_DIR}/backend/server.py" "${BUNDLE_RESOURCES}/backend/"

echo "Copying backend/whisper_wrapper.py..."
cp -f "${PROJECT_DIR}/backend/whisper_wrapper.py" "${BUNDLE_RESOURCES}/backend/"

echo "Copying backend/postprocess.py..."
cp -f "${PROJECT_DIR}/backend/postprocess.py" "${BUNDLE_RESOURCES}/backend/"

echo "Copying backend/requirements.txt..."
cp -f "${PROJECT_DIR}/backend/requirements.txt" "${BUNDLE_RESOURCES}/backend/"

# Copy whisper.cpp library (NEW - for in-memory transcription)
echo "Copying libwhisper.dylib..."
mkdir -p "${BUNDLE_RESOURCES}/backend/whisper.cpp/build/src"
cp -f "${PROJECT_DIR}/backend/whisper.cpp/build/src/libwhisper.dylib" "${BUNDLE_RESOURCES}/backend/whisper.cpp/build/src/"
cp -f "${PROJECT_DIR}/backend/whisper.cpp/build/src/libwhisper.1.dylib" "${BUNDLE_RESOURCES}/backend/whisper.cpp/build/src/"
cp -f "${PROJECT_DIR}/backend/whisper.cpp/build/src/libwhisper.1.8.2.dylib" "${BUNDLE_RESOURCES}/backend/whisper.cpp/build/src/"

# Copy GGML libraries (dependencies of libwhisper - CRITICAL for distribution)
echo "Copying GGML libraries..."
mkdir -p "${BUNDLE_RESOURCES}/backend/whisper.cpp/build/ggml/src"
if [ -f "${PROJECT_DIR}/backend/whisper.cpp/build/ggml/src/libggml.dylib" ]; then
    cp -f "${PROJECT_DIR}/backend/whisper.cpp/build/ggml/src/libggml.dylib" "${BUNDLE_RESOURCES}/backend/whisper.cpp/build/ggml/src/"
fi
if [ -f "${PROJECT_DIR}/backend/whisper.cpp/build/ggml/src/libggml-base.dylib" ]; then
    cp -f "${PROJECT_DIR}/backend/whisper.cpp/build/ggml/src/libggml-base.dylib" "${BUNDLE_RESOURCES}/backend/whisper.cpp/build/ggml/src/"
fi
if [ -f "${PROJECT_DIR}/backend/whisper.cpp/build/ggml/src/libggml-cpu.dylib" ]; then
    cp -f "${PROJECT_DIR}/backend/whisper.cpp/build/ggml/src/libggml-cpu.dylib" "${BUNDLE_RESOURCES}/backend/whisper.cpp/build/ggml/src/"
fi

# Copy GGML BLAS library
mkdir -p "${BUNDLE_RESOURCES}/backend/whisper.cpp/build/ggml/src/ggml-blas"
if [ -f "${PROJECT_DIR}/backend/whisper.cpp/build/ggml/src/ggml-blas/libggml-blas.dylib" ]; then
    cp -f "${PROJECT_DIR}/backend/whisper.cpp/build/ggml/src/ggml-blas/libggml-blas.dylib" "${BUNDLE_RESOURCES}/backend/whisper.cpp/build/ggml/src/ggml-blas/"
fi

# Copy GGML Metal library (for GPU acceleration)
mkdir -p "${BUNDLE_RESOURCES}/backend/whisper.cpp/build/ggml/src/ggml-metal"
if [ -f "${PROJECT_DIR}/backend/whisper.cpp/build/ggml/src/ggml-metal/libggml-metal.dylib" ]; then
    cp -f "${PROJECT_DIR}/backend/whisper.cpp/build/ggml/src/ggml-metal/libggml-metal.dylib" "${BUNDLE_RESOURCES}/backend/whisper.cpp/build/ggml/src/ggml-metal/"
fi

# Copy Metal shader files (CRITICAL for GPU acceleration)
echo "Copying Metal shader files..."
mkdir -p "${BUNDLE_RESOURCES}/backend/whisper.cpp/build/bin"
if [ -f "${PROJECT_DIR}/backend/whisper.cpp/build/bin/ggml-metal.metal" ]; then
    cp -f "${PROJECT_DIR}/backend/whisper.cpp/build/bin/ggml-metal.metal" "${BUNDLE_RESOURCES}/backend/whisper.cpp/build/bin/"
    echo "Copied ggml-metal.metal"
fi

echo "Copying whisper.cpp models (turbo only)..."
mkdir -p "${BUNDLE_RESOURCES}/backend/whisper.cpp/models"
cp -f "${PROJECT_DIR}/backend/whisper.cpp/models/ggml-large-v3-turbo.bin" "${BUNDLE_RESOURCES}/backend/whisper.cpp/models/"

# Copy bundled Python runtime (NEW - self-contained distribution)
echo "Copying bundled Python runtime..."
if [ -d "${PROJECT_DIR}/backend/python_bundle/python" ]; then
    mkdir -p "${BUNDLE_RESOURCES}/python"
    cp -R "${PROJECT_DIR}/backend/python_bundle/python/"* "${BUNDLE_RESOURCES}/python/"
    echo "Bundled Python copied successfully"
else
    echo "WARNING: Bundled Python not found at ${PROJECT_DIR}/backend/python_bundle/python"
    echo "App will require system Python installation"
fi

# Fix library install names for standalone distribution
echo "Fixing library install names..."

# Fix libpython3.12.dylib install_name (currently points to /install/lib/)
if [ -f "${BUNDLE_RESOURCES}/python/lib/libpython3.12.dylib" ]; then
    echo "  Fixing libpython3.12.dylib install_name..."
    install_name_tool -id "@loader_path/libpython3.12.dylib" "${BUNDLE_RESOURCES}/python/lib/libpython3.12.dylib"
    echo "  ✓ libpython3.12.dylib install_name fixed"
fi

# Verify critical libraries are present
echo "Verifying bundled libraries..."
MISSING_LIBS=0

# Check Python
if [ ! -f "${BUNDLE_RESOURCES}/python/bin/python3.12" ]; then
    echo "  ⚠️  WARNING: Python executable not found"
    MISSING_LIBS=1
fi

# Check libpython
if [ ! -f "${BUNDLE_RESOURCES}/python/lib/libpython3.12.dylib" ]; then
    echo "  ⚠️  WARNING: libpython3.12.dylib not found"
    MISSING_LIBS=1
fi

# Check whisper.cpp libraries
if [ ! -f "${BUNDLE_RESOURCES}/backend/whisper.cpp/build/src/libwhisper.dylib" ]; then
    echo "  ⚠️  WARNING: libwhisper.dylib not found"
    MISSING_LIBS=1
fi

# Check GGML libraries
if [ ! -f "${BUNDLE_RESOURCES}/backend/whisper.cpp/build/ggml/src/libggml.dylib" ]; then
    echo "  ⚠️  WARNING: libggml.dylib not found"
    MISSING_LIBS=1
fi

if [ ! -f "${BUNDLE_RESOURCES}/backend/whisper.cpp/build/ggml/src/ggml-metal/libggml-metal.dylib" ]; then
    echo "  ⚠️  WARNING: libggml-metal.dylib not found (GPU acceleration will not work)"
    MISSING_LIBS=1
fi

# Check Metal shader
if [ ! -f "${BUNDLE_RESOURCES}/backend/whisper.cpp/build/bin/ggml-metal.metal" ]; then
    echo "  ⚠️  WARNING: ggml-metal.metal not found (GPU acceleration will not work)"
    MISSING_LIBS=1
fi

# Check model
if [ ! -f "${BUNDLE_RESOURCES}/backend/whisper.cpp/models/ggml-large-v3-turbo.bin" ]; then
    echo "  ⚠️  WARNING: Whisper model not found"
    MISSING_LIBS=1
fi

if [ $MISSING_LIBS -eq 0 ]; then
    echo "  ✓ All critical libraries verified"
else
    echo "  ⚠️  Some libraries are missing - app may not be fully standalone"
fi

# Make server.py executable
chmod +x "${BUNDLE_RESOURCES}/backend/server.py"

# Code signing for distribution (optional, uncomment for manual builds)
# For automated builds, Xcode will handle code signing after this script runs
# For manual distribution builds:
#   1. Sign all dylib files with your Developer ID:
#      find "${BUNDLE_RESOURCES}" -name "*.dylib" -exec codesign --force --sign "Developer ID Application: Your Name (TEAM_ID)" {} \;
#   2. Sign the Python executable:
#      codesign --force --sign "Developer ID Application: Your Name (TEAM_ID)" "${BUNDLE_RESOURCES}/python/bin/python3.12"
#   3. Sign the entire app bundle (done automatically by Xcode):
#      codesign --force --deep --sign "Developer ID Application: Your Name (TEAM_ID)" "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app"
#   4. For notarization, submit to Apple:
#      xcrun notarytool submit "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app" --keychain-profile "YOUR_PROFILE" --wait

echo "Backend v3 copied successfully to: ${BUNDLE_RESOURCES}/backend/"
