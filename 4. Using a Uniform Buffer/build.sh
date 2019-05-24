#!/bin/sh

clear

EXE_NAME="UsingAUniformBuffer"

COMMON_COMPILER_FLAGS="-Wall -std=c++11 -fno-exceptions -fno-rtti -Wno-missing-braces"
DEBUG_FLAGS="-g -fno-inline"
RELEASE_FLAGS="-O3"

COMPILER_FLAGS="$COMMON_COMPILER_FLAGS $DEBUG_FLAGS"
# COMPILER_FLAGS="$COMMON_COMPILER_FLAGS $RELEASE_FLAGS"

FRAMEWORKS="-framework Cocoa -framework Metal -framework QuartzCore"

# Turn on Metal API Validation. Great for catching API misuse, remove for Release build
METAL_DEVICE_WRAPPER_TYPE=1

mkdir -p build
pushd build > /dev/null
clang $COMPILER_FLAGS $FRAMEWORKS -o $EXE_NAME ../main.mm

xcrun -sdk macosx metal -c ../shaders.metal -o shaders.air
xcrun -sdk macosx metallib shaders.air -o shaders.metallib

popd > /dev/null
echo Done