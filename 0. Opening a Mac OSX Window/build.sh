#!/bin/sh

clear

EXE_NAME="HelloMacOSXWindow"

COMMON_COMPILER_FLAGS="-Wall -fno-exceptions -fno-rtti"
DEBUG_FLAGS='-g -fno-inline'
RELEASE_FLAGS='-O3'

COMPILER_FLAGS="$COMMON_COMPILER_FLAGS $DEBUG_FLAGS"
# COMPILER_FLAGS="$COMMON_COMPILER_FLAGS $RELEASE_FLAGS"

FRAMEWORKS="-framework Cocoa"
mkdir -p build
pushd build > /dev/null
clang $COMPILER_FLAGS $FRAMEWORKS -o $EXE_NAME ../main.mm

popd > /dev/null
echo Done