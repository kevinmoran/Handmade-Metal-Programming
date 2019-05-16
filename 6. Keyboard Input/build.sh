#!/bin/sh

clear

EXE_NAME="MetalKeyboardInput"

COMMON_COMPILER_FLAGS="-Wall -std=c++11 -fno-exceptions -fno-rtti -Wno-missing-braces"
DEBUG_FLAGS="-g -fno-inline"
RELEASE_FLAGS="-O3"

COMPILER_FLAGS="$COMMON_COMPILER_FLAGS $DEBUG_FLAGS"
# COMPILER_FLAGS="$COMMON_COMPILER_FLAGS $RELEASE_FLAGS"

FRAMEWORKS="-framework Cocoa -framework Metal -framework QuartzCore"

mkdir -p build
pushd build > /dev/null
clang $COMPILER_FLAGS $FRAMEWORKS -o $EXE_NAME ../main.mm

xcrun -sdk macosx metal -c ../shaders.metal -o shaders.air
xcrun -sdk macosx metallib shaders.air -o shaders.metallib

popd > /dev/null
echo Done