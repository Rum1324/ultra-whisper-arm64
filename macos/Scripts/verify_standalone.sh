#!/bin/bash

# Standalone Verification Script for UltraWhisper.app
# This script verifies that the built app bundle is completely standalone
# and doesn't depend on any external libraries or system installations.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Usage
if [ $# -ne 1 ]; then
    echo "Usage: $0 <path-to-UltraWhisper.app>"
    echo "Example: $0 build/macos/Build/Products/Release/UltraWhisper.app"
    exit 1
fi

APP_PATH="$1"

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: App bundle not found at: $APP_PATH${NC}"
    exit 1
fi

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}UltraWhisper Standalone Verification${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

RESOURCES="${APP_PATH}/Contents/Resources"
ISSUES_FOUND=0

# Function to check library dependencies
check_library_deps() {
    local lib_path="$1"
    local lib_name=$(basename "$lib_path")

    # Get dependencies
    local deps=$(otool -L "$lib_path" | tail -n +2 | awk '{print $1}')

    # Check each dependency
    while IFS= read -r dep; do
        # Skip if empty
        [ -z "$dep" ] && continue

        # Check if dependency is external (not system framework, not @rpath, not @executable_path, not @loader_path)
        if [[ ! "$dep" =~ ^/System/ ]] && \
           [[ ! "$dep" =~ ^/usr/lib/ ]] && \
           [[ ! "$dep" =~ ^@rpath ]] && \
           [[ ! "$dep" =~ ^@executable_path ]] && \
           [[ ! "$dep" =~ ^@loader_path ]]; then
            echo -e "    ${RED}✗ External dependency: $dep${NC}"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    done <<< "$deps"
}

# 1. Check Python Runtime
echo -e "${BLUE}[1] Checking Python Runtime...${NC}"
if [ -f "${RESOURCES}/python/bin/python3.12" ]; then
    echo -e "  ${GREEN}✓ Python executable found${NC}"

    # Check Python dependencies
    check_library_deps "${RESOURCES}/python/bin/python3.12"

    # Check libpython
    if [ -f "${RESOURCES}/python/lib/libpython3.12.dylib" ]; then
        echo -e "  ${GREEN}✓ libpython3.12.dylib found${NC}"

        # Check install_name
        install_name=$(otool -D "${RESOURCES}/python/lib/libpython3.12.dylib" | tail -n 1)
        if [[ "$install_name" =~ ^@loader_path ]] || [[ "$install_name" =~ ^@rpath ]]; then
            echo -e "  ${GREEN}✓ libpython3.12.dylib has correct install_name: $install_name${NC}"
        else
            echo -e "  ${RED}✗ libpython3.12.dylib has absolute install_name: $install_name${NC}"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi

        check_library_deps "${RESOURCES}/python/lib/libpython3.12.dylib"
    else
        echo -e "  ${RED}✗ libpython3.12.dylib NOT found${NC}"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
else
    echo -e "  ${RED}✗ Python executable NOT found${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# 2. Check Python Dependencies
echo -e "${BLUE}[2] Checking Python Dependencies...${NC}"
SITE_PACKAGES="${RESOURCES}/python/lib/python3.12/site-packages"

# Check websockets
if [ -f "${SITE_PACKAGES}/websockets/speedups.cpython-312-darwin.so" ]; then
    echo -e "  ${GREEN}✓ websockets (with speedups) found${NC}"
else
    echo -e "  ${YELLOW}⚠ websockets speedups not found (will use pure Python)${NC}"
fi

# Check numpy
if [ -d "${SITE_PACKAGES}/numpy" ]; then
    echo -e "  ${GREEN}✓ numpy found${NC}"

    # Check a key numpy extension
    NUMPY_CORE="${SITE_PACKAGES}/numpy/_core/_multiarray_umath.cpython-312-darwin.so"
    if [ -f "$NUMPY_CORE" ]; then
        check_library_deps "$NUMPY_CORE"
    fi
else
    echo -e "  ${RED}✗ numpy NOT found${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# 3. Check whisper.cpp Libraries
echo -e "${BLUE}[3] Checking whisper.cpp Libraries...${NC}"

# Check libwhisper
if [ -f "${RESOURCES}/backend/whisper.cpp/build/src/libwhisper.dylib" ]; then
    echo -e "  ${GREEN}✓ libwhisper.dylib found${NC}"
    check_library_deps "${RESOURCES}/backend/whisper.cpp/build/src/libwhisper.dylib"
else
    echo -e "  ${RED}✗ libwhisper.dylib NOT found${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check GGML libraries
GGML_LIBS=(
    "ggml/src/libggml.dylib"
    "ggml/src/libggml-base.dylib"
    "ggml/src/libggml-cpu.dylib"
    "ggml/src/ggml-blas/libggml-blas.dylib"
    "ggml/src/ggml-metal/libggml-metal.dylib"
)

for lib in "${GGML_LIBS[@]}"; do
    lib_path="${RESOURCES}/backend/whisper.cpp/build/${lib}"
    lib_name=$(basename "$lib")

    if [ -f "$lib_path" ]; then
        echo -e "  ${GREEN}✓ $lib_name found${NC}"
        check_library_deps "$lib_path"
    else
        echo -e "  ${RED}✗ $lib_name NOT found${NC}"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
done
echo ""

# 4. Check Metal Shader
echo -e "${BLUE}[4] Checking Metal GPU Support...${NC}"
if [ -f "${RESOURCES}/backend/whisper.cpp/build/bin/ggml-metal.metal" ]; then
    echo -e "  ${GREEN}✓ Metal shader (ggml-metal.metal) found${NC}"
else
    echo -e "  ${RED}✗ Metal shader NOT found (GPU acceleration will not work)${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# 5. Whisper model: downloaded at first run, never bundled
echo -e "${BLUE}[5] Checking Whisper Model...${NC}"
if ls "${RESOURCES}/backend/whisper.cpp/models/"*.bin >/dev/null 2>&1; then
    echo -e "  ${YELLOW}⚠ A model is bundled — releases download it at first run instead${NC}"
else
    echo -e "  ${GREEN}✓ No model bundled (first-run setup downloads it)${NC}"
fi
echo ""

# 6. Check Backend Scripts
echo -e "${BLUE}[6] Checking Backend Scripts...${NC}"
if [ -f "${RESOURCES}/backend/server.py" ]; then
    echo -e "  ${GREEN}✓ server.py found${NC}"
    if [ -x "${RESOURCES}/backend/server.py" ]; then
        echo -e "  ${GREEN}✓ server.py is executable${NC}"
    else
        echo -e "  ${YELLOW}⚠ server.py is not executable${NC}"
    fi
else
    echo -e "  ${RED}✗ server.py NOT found${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

if [ -f "${RESOURCES}/backend/whisper_wrapper.py" ]; then
    echo -e "  ${GREEN}✓ whisper_wrapper.py found${NC}"
else
    echo -e "  ${RED}✗ whisper_wrapper.py NOT found${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# 7. Check Code Signatures (optional)
echo -e "${BLUE}[7] Checking Code Signatures...${NC}"
if codesign -v "$APP_PATH" 2>/dev/null; then
    echo -e "  ${GREEN}✓ App bundle is signed${NC}"

    # Check if libraries are signed
    signed_count=0
    unsigned_count=0

    for lib in "${RESOURCES}"/backend/whisper.cpp/build/**/*.dylib; do
        if [ -f "$lib" ]; then
            if codesign -v "$lib" 2>/dev/null; then
                signed_count=$((signed_count + 1))
            else
                unsigned_count=$((unsigned_count + 1))
            fi
        fi
    done

    if [ $unsigned_count -eq 0 ]; then
        echo -e "  ${GREEN}✓ All bundled libraries are signed${NC}"
    else
        echo -e "  ${YELLOW}⚠ $unsigned_count bundled libraries are not signed${NC}"
        echo -e "    ${YELLOW}(This may cause issues on other machines)${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠ App bundle is not signed${NC}"
    echo -e "    ${YELLOW}(Required for distribution outside development)${NC}"
fi
echo ""

# 8. Calculate Bundle Size
echo -e "${BLUE}[8] Bundle Size Analysis...${NC}"
total_size=$(du -sh "$APP_PATH" | awk '{print $1}')
python_size=$(du -sh "${RESOURCES}/python" 2>/dev/null | awk '{print $1}' || echo "N/A")
backend_size=$(du -sh "${RESOURCES}/backend" 2>/dev/null | awk '{print $1}' || echo "N/A")

echo -e "  Total app size: ${GREEN}$total_size${NC}"
echo -e "  Python runtime: $python_size"
echo -e "  Backend + models: $backend_size"
echo ""

# Final Summary
echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}Verification Summary${NC}"
echo -e "${BLUE}=====================================${NC}"

if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo -e "${GREEN}✓ App appears to be fully standalone${NC}"
    exit 0
else
    echo -e "${RED}✗ Found $ISSUES_FOUND issue(s)${NC}"
    echo -e "${YELLOW}⚠ App may not be fully standalone${NC}"
    exit 1
fi
