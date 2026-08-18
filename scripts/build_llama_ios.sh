#!/usr/bin/env bash
# Builds llama.cpp + our wrapper into a single static lib (libhandyllm.a) that
# exports ONLY handy_llm_* — all llama/ggml symbols are localized so they don't
# collide with transcribe.cpp's own ggml. CPU-only (Metal off) so it runs in the
# background where iOS forbids the GPU.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/llama.cpp"
BUILD="$ROOT/build-llama-ios"
OUT="$ROOT/build-llama-ios/libhandyllm.a"
MIN_IOS=17.0

[ -f "$SRC/CMakeLists.txt" ] || { echo "run: git submodule update --init --recursive"; exit 1; }

# 1. Build llama.cpp (static, CPU, Accelerate) for iOS arm64
cmake -S "$SRC" -B "$BUILD" -GXcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN_IOS \
  -DCMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH=NO \
  -DGGML_METAL=OFF -DGGML_ACCELERATE=ON -DGGML_OPENMP=OFF \
  -DBUILD_SHARED_LIBS=OFF \
  -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_TOOLS=OFF -DLLAMA_BUILD_SERVER=OFF -DLLAMA_CURL=OFF
cmake --build "$BUILD" --config Release --target llama -- -sdk iphoneos

# 2. Compile our wrapper
xcrun -sdk iphoneos clang++ -c "$ROOT/LlamaLLM/handyllm.cpp" \
  -o "$BUILD/handyllm.o" \
  -arch arm64 -miphoneos-version-min=$MIN_IOS -std=c++17 -O2 \
  -I "$ROOT/LlamaLLM/include" -I "$SRC/include" -I "$SRC/ggml/include"

# 3. Gather the built static libs
LIBS=$(find "$BUILD" -name "libllama.a" -o -name "libggml*.a" | grep -i "release-iphoneos" || true)
[ -n "$LIBS" ] || LIBS=$(find "$BUILD" -name "libllama.a" -o -name "libggml*.a")
echo "linking: $LIBS"

# 4. Partial-link everything, exporting ONLY handy_llm_* (localizes ggml/llama)
SYMS="$BUILD/handy_exported_symbols.txt"
printf '_handy_llm_load\n_handy_llm_rewrite\n_handy_llm_free_string\n_handy_llm_free\n' > "$SYMS"

FORCE=""
for l in $LIBS; do FORCE="$FORCE -force_load $l"; done

ld -r -arch arm64 \
  -exported_symbols_list "$SYMS" \
  "$BUILD/handyllm.o" $FORCE \
  -o "$BUILD/handyllm_combined.o"

# 5. Archive
rm -f "$OUT"
ar crs "$OUT" "$BUILD/handyllm_combined.o"

# 6. Copy header for the app
mkdir -p "$ROOT/LlamaLLM/include"
echo "Done: $OUT"
echo "Exported symbols:"
nm "$OUT" 2>/dev/null | grep " T " | grep -i handy || true
