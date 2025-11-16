#!/bin/bash

set -e

ROOT_DIR=$(pwd)
OUTPUT_DIR="$ROOT_DIR/build/output"

rm -rf "$ROOT_DIR/build"
mkdir -p "$OUTPUT_DIR"

echo "===== Zopfli iOS + Simulator Build ====="

###############################################################################
# 1. Build iOS (arm64)
###############################################################################
echo "===== Building iOS (arm64) ====="

cmake -S . -B build/ios \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_BUILD_TYPE=Release

cmake --build build/ios --config Release

IOS_LIB=$(find build/ios -name "libzopfli.a" | head -n 1)
cp "$IOS_LIB" "$OUTPUT_DIR/libzopfli_ios.a"

echo "iOS library: $IOS_LIB"
file "$OUTPUT_DIR/libzopfli_ios.a"


###############################################################################
# 2. Build Simulator (arm64 + x86_64)
###############################################################################
echo "===== Building Simulator (arm64 + x86_64) ====="

cmake -S . -B build/sim \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DCMAKE_BUILD_TYPE=Release

cmake --build build/sim --config Release

SIM_LIB=$(find build/sim -name "libzopfli.a" | head -n 1)


###############################################################################
# 3. Split Simulator slices for a clean FAT output
###############################################################################

echo "===== Splitting Simulator slices ====="

SIM_ARM64="$OUTPUT_DIR/sim_arm64.a"
SIM_X86="$OUTPUT_DIR/sim_x86_64.a"

lipo "$SIM_LIB" -thin arm64 -output "$SIM_ARM64"
lipo "$SIM_LIB" -thin x86_64 -output "$SIM_X86"

# Merge simulator slices
lipo -create "$SIM_ARM64" "$SIM_X86" -output "$OUTPUT_DIR/libzopfli_sim.a"

echo "Simulator library created:"
file "$OUTPUT_DIR/libzopfli_sim.a"


###############################################################################
# 4. Produce final universal static library
###############################################################################

echo "===== Creating Universal libzopfli.a (iOS + Simulator) ====="

lipo -create \
  "$OUTPUT_DIR/libzopfli_ios.a" \
  "$OUTPUT_DIR/libzopfli_sim.a" \
  -output "$OUTPUT_DIR/libzopfli_universal.a"

echo "===== Build Completed ====="
echo "Output files:"
ls -lh "$OUTPUT_DIR"
file "$OUTPUT_DIR/libzopfli_universal.a"