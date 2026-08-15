#!/usr/bin/env bash
# Compiles transcribe.cpp as a static library for iOS (arm64, Metal enabled).
# Output: build-ios/libtranscribe.a + headers copied to TranscribeCpp/include/
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_ROOT/transcribe.cpp"
BUILD="$REPO_ROOT/build-ios"
OUT_LIB="$BUILD/libtranscribe.a"
OUT_HEADERS="$REPO_ROOT/TranscribeCpp/include"

if [ ! -f "$SRC/CMakeLists.txt" ]; then
    echo "ERROR: transcribe.cpp submodule not initialised. Run:"
    echo "  git submodule update --init --recursive"
    exit 1
fi

mkdir -p "$BUILD" "$OUT_HEADERS"

cmake -S "$SRC" -B "$BUILD" \
    -GXcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH=NO \
    -DTRANSCRIBE_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DTRANSCRIBE_BUILD_TESTS=OFF \
    -DTRANSCRIBE_BUILD_EXAMPLES=OFF \
    -DTRANSCRIBE_USE_SYSTEM_BLAS=OFF

cmake --build "$BUILD" \
    --config Release \
    -- -sdk iphoneos

# Merge all .a files into one fat archive
LIBS=$(find "$BUILD" -name "*.a" -not -name "libtranscribe.a")
if [ -n "$LIBS" ]; then
    libtool -static -o "$OUT_LIB" $LIBS
fi

# Copy public headers
cp "$SRC/include/transcribe.h" "$OUT_HEADERS/"
cp -r "$SRC/include/transcribe/" "$OUT_HEADERS/transcribe/" 2>/dev/null || true

echo "Done: $OUT_LIB"
echo "Headers: $OUT_HEADERS"
