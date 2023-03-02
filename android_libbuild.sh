#!/bin/bash

# PREREQUISITES:
# - Install target `rustup target add aarch64-linux-android`
# - Install NDK from Android Studio

# Builds an Android library for tflite

DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd ${DIR}
PROJECT_ROOT=`pwd`

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
if [ -z "$ANDROID_SYSROOT" ]; then
  ANDROID_SYSROOT=${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/${ANDROID_NDK_VARIANT}
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
echo "=> Building tflite c library <============================================="
echo ""

if [ -z "$OUT_DIR" ]; then
    OUTPUT_DIR=${PROJECT_ROOT}/tmp/output
    mkdir -p ${OUTPUT_DIR}
    BUILD_DIR=${PROJECT_ROOT}/tmp/build
    CODE_DIR=${PROJECT_ROOT}/tmp/tensorflow
else
    OUTPUT_DIR=${OUT_DIR}
    BUILD_DIR=${OUT_DIR}/tmp/build
    CODE_DIR=${OUT_DIR}/tmp/tensorflow
fi
mkdir -p ${BUILD_DIR}

echo " Using code directory: ${CODE_DIR}"
echo " Using build directory: ${BUILD_DIR}"
echo " Using output directory: ${OUTPUT_DIR}"

# Checkout source code
if [ ! -d ${CODE_DIR} ]; then
    echo "Tensorflow source code not found"
    echo "  Copying tensorflow source code"
    echo ""
    cp -r ${PROJECT_ROOT}/submodules/tensorflow/ ${CODE_DIR}
fi

# Setup up make
cd ${BUILD_DIR}
cmake -S ${CODE_DIR}/tensorflow/lite \
    -DCMAKE_TOOLCHAIN_FILE=${ANDROID_TOOLCHAIN_PATH} \
    -DANDROID_SDK_BUILD_TOOLS_REVISION=${ANDROID_SDK_BUILD_TOOLS_REVISION} \
    -DANDROID_ABI=${ANDROID_TARGET_ARCH} \
    -DANDROID_PLATFORM=${ANDROID_PLATFORM} \
    -DCMAKE_BUILD_TYPE=Release

# Do the build
cmake --build . -j$(nproc)


# Create output directory structure
cd ${OUTPUT_DIR}

mkdir -p include
mkdir -p include/tensorflow/lite
mkdir -p include/flatbuffers
mkdir -p lib
mkdir -p include/tensorflow/lite/c
mkdir -p include/tensorflow/lite/core
mkdir -p include/tensorflow/lite/experimental
mkdir -p include/tensorflow/lite/kernels
mkdir -p include/tensorflow/lite/schema
mkdir -p include/tensorflow/lite/tools
mkdir -p include/tensorflow/lite/core/api

# Copy headers and stuff
cp -r ${BUILD_DIR}/flatbuffers/include/flatbuffers/* include/flatbuffers/.
cp ${CODE_DIR}/tensorflow/lite/*.h include/tensorflow/lite/.
cp ${CODE_DIR}/tensorflow/lite/*.h include/tensorflow/lite/.

cp ${CODE_DIR}/tensorflow/lite/c/*.h include/tensorflow/lite/c/.
cp ${CODE_DIR}/tensorflow/lite/core/*.h include/tensorflow/lite/core/.
cp -r ${CODE_DIR}/tensorflow/lite/experimental/resource include/tensorflow/lite/experimental/.
cp ${CODE_DIR}/tensorflow/lite/kernels/*.h include/tensorflow/lite/kernels/.
cp ${CODE_DIR}/tensorflow/lite/schema/*.h include/tensorflow/lite/schema/.
cp ${CODE_DIR}/tensorflow/lite/tools/*.h include/tensorflow/lite/tools/.
cp ${CODE_DIR}/tensorflow/lite/core/api/*.h include/tensorflow/lite/core/api/.

# Copy libraries
cp ${BUILD_DIR}/libtensorflow-lite.a lib/.
cp ${BUILD_DIR}/_deps/xnnpack-build/libXNNPACK.a lib/.
cp ${BUILD_DIR}/_deps/flatbuffers-build/libflatbuffers.a lib/.
cp ${BUILD_DIR}/_deps/abseil-cpp-build/absl/**/*.a lib/.
cp ${BUILD_DIR}/cpuinfo/libcpuinfo.a lib/.
cp ${BUILD_DIR}/_deps/fft2d-build/*.a lib/.
cp ${BUILD_DIR}/pthreadpool/libpthreadpool.a lib/.
cp ${BUILD_DIR}/_deps/ruy-build/libruy.a lib/.
cp ${BUILD_DIR}/clog/libclog.a lib/.
cp ${BUILD_DIR}/_deps/farmhash-build/libfarmhash.a lib/.

# Create archive
cd ${OUTPUT_DIR}/lib
echo "create libtflite.a" > ${OUTPUT_DIR}/libtflite.mri
echo "save" >> ${OUTPUT_DIR}/libtflite.mri
AFILES=$(ls *.a)
for f in ${AFILES}; do
    echo "addlib ${f}" >> ${OUTPUT_DIR}/libtflite.mri
done
echo "end" >> ${OUTPUT_DIR}/libtflite.mri
$AR -M < ${OUTPUT_DIR}/libtflite.mri
if [ -f ${OUTPUT_DIR}/libtensorflow-lite.a ]; then
    echo "Can't deal with libtensorflow-lite.a already existing"
    exit 1
fi
mv libtflite.a ${OUTPUT_DIR}/libtensorflow-lite.a

export TFLITE_LIB_DIR=${OUTPUT_DIR}

if [ ! -f "${TFLITE_LIB_DIR}/libtensorflow-lite.a" ]; then
    echo "Could not find tflite library"
    echo "  Did the build fail?"
    exit 1
fi
