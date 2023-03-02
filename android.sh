#!/bin/bash

# PREREQUISITES:
# - Install target `rustup target add aarch64-linux-android`
# - Install NDK from Android Studio

# Manual build script for Android

DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd ${DIR}
PROJECT_ROOT=`pwd`

if [ "$1" == "clean" ] ; then
    echo "Cleaning"
    rm -rf target/
    rm -rf tmp/
    exit 0
elif [ "$1" == "build" ] ; then
    echo "Building for aarch64"
else
    echo "Usage: $0 [build|clean]"
    exit 1
fi


echo ""
echo "=> Configuring Android build settings <============================================="
echo ""

# Android SDK and NDK paths
if [ -z "$ANDROID_HOME" ]; then
    export ANDROID_HOME=$HOME/Android/Sdk
fi
echo "Using ANDROID_HOME: ${ANDROID_HOME}"
# If ANDROID_NDK_HOME is not set, then use the latest NDK in the SDK
if [ -z "$ANDROID_NDK_HOME" ]; then
    TMP_NDK_VER=$(ls $ANDROID_HOME/ndk | tail -n1)
    if [ -z "$TMP_NDK_VER" ] ; then
        echo "Could not find NDK in Android SDK"
        echo "  Is the Android SDK and NDK installed?"
        exit 1
    fi
    export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/$TMP_NDK_VER
fi
echo "Using ANDROID_NDK_HOME: ${ANDROID_NDK_HOME}"
if [ -z "$ANDROID_TOOLCHAIN_PATH" ]; then
    ANDROID_TOOLCHAIN_PATH=${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake
fi
echo "Using ANDROID_TOOLCHAIN_PATH: ${ANDROID_TOOLCHAIN_PATH}"
if [ -z "$ANDROID_NDK_TOOLCHAIN_BIN_PATH" ]; then
    ANDROID_NDK_TOOLCHAIN_BIN_PATH=${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin
fi
echo "Using ANDROID_NDK_TOOLCHAIN_BIN_PATH: ${ANDROID_NDK_TOOLCHAIN_BIN_PATH}"
if [ -z "$ANDROID_NDK_VARIANT" ]; then
    ANDROID_NDK_VARIANT=33
fi
echo "Using ANDROID_NDK_VARIANT: ${ANDROID_NDK_VARIANT}"
if [ -z "$ANDROID_PLATFORM" ]; then
    ANDROID_PLATFORM=android-${ANDROID_NDK_VARIANT}
fi
echo "Using ANDROID_PLATFORM: ${ANDROID_PLATFORM}"
if [ -z "$ANDROID_SDK_BUILD_TOOLS_REVISION" ]; then
    ANDROID_SDK_BUILD_TOOLS_REVISION=30.0.3
fi
echo "Using ANDROID_SDK_BUILD_TOOLS_REVISION: ${ANDROID_SDK_BUILD_TOOLS_REVISION}"
if [ -z "$ANDROID_TARGET_ARCH" ]; then
    ANDROID_TARGET_ARCH=arm64-v8a
fi
echo "Using ANDROID_TARGET_ARCH: ${ANDROID_TARGET_ARCH}"
if [ -z "$ANDROID_SYSROOT_BASE" ]; then
  ANDROID_SYSROOT_BASE=${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot
fi
echo "Using ANDROID_SYSROOT_BASE: ${ANDROID_SYSROOT_BASE}"
if [ -z "$ANDROID_SYSROOT" ]; then
  ANDROID_SYSROOT=${ANDROID_SYSROOT_BASE}/usr/lib/aarch64-linux-android/${ANDROID_NDK_VARIANT}
fi
echo "Using ANDROID_SYSROOT: ${ANDROID_SYSROOT}"

# Set up a hack for -lgcc failing
# unwind.a is supposed to be the replacement for gcc stuff in android IIRC
# so we just make a fake libgcc.a that links to unwind.a
ANDROIDLIBLOC=$(find $ANDROID_HOME | grep unwind\\.a | grep aarch64)
if [ -z "$ANDROIDLIBLOC" ] ; then
    echo "Could not find unwind.a in Android SDK"
    echo "  Is the Android SDK and NDK installed?"
    exit 1
fi
ANDROIDLIB_DIR=$(dirname $ANDROIDLIBLOC)
ANDROIDLIBGCC_PATH=$ANDROIDLIB_DIR/libgcc.a
echo "INPUT(-lunwind)" > $ANDROIDLIBGCC_PATH

echo ""
echo "=> Building rust crate <============================================="
echo ""

export PATH=$PATH:$ANDROID_NDK_TOOLCHAIN_BIN_PATH

export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER=aarch64-linux-android${ANDROID_NDK_VARIANT}-clang++
export CC_aarch64_linux_android=aarch64-linux-android${ANDROID_NDK_VARIANT}-clang
export CXX_aarch64_linux_android=aarch64-linux-android${ANDROID_NDK_VARIANT}-clang++
export AR=${ANDROID_NDK_TOOLCHAIN_BIN_PATH}/llvm-ar

# These are embedded into build.rs
export ANDROID_CLANG_ARGS1="--sysroot=${ANDROID_SYSROOT}"
export ANDROID_CLANG_ARGS2="-I${ANDROID_NDK_HOME}/sources/cxx-stl/llvm-libc++/include/"
export ANDROID_CLANG_ARGS3="-I${ANDROID_SYSROOT_BASE}/usr/include/aarch64-linux-android/"
export ANDROID_CLANG_ARGS4="-I${ANDROID_SYSROOT_BASE}/usr/include/"

~/.cargo/bin/cargo build --target aarch64-linux-android --no-default-features --features androidbuild --release
