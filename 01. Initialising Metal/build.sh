#!/bin/sh

clear

EXE_NAME="HelloMetalWindow"

COMMON_COMPILER_FLAGS="-Wall -fno-exceptions -fno-rtti"
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

popd > /dev/null
echo Done