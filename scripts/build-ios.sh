#!/usr/bin/env bash
#
# Build Graphviz.xcframework for iOS
#
# Produces a unified static XCFramework containing all Graphviz functionality
# for arm64 (device) and x86_64+arm64 (simulator).
#
# Usage:
#   ./scripts/build-ios.sh
#
# Environment variables:
#   BUILD_DIR       - Build directory (default: build/ios)
#   INSTALL_DIR     - Install prefix (default: output/ios)
#   IOS_MIN_VERSION - Minimum iOS version (default: 12.0)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

IOS_MIN_VERSION="${IOS_MIN_VERSION:-12.0}"
BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/build/ios}"
INSTALL_DIR="${INSTALL_DIR:-${PROJECT_ROOT}/output/ios}"

log_info "Building Graphviz for iOS (min version: ${IOS_MIN_VERSION})"

check_build_deps
check_command "xcrun"
check_command "xcodebuild"

# Prepare patched source
mkdir -p "${BUILD_DIR}"
GV_PATCHED="${BUILD_DIR}/graphviz-src"
prepare_graphviz_source "${GV_PATCHED}"

get_sdk_path() {
    xcrun --sdk "$1" --show-sdk-path
}

build_ios_arch() {
    local arch="$1"
    local sdk="$2"
    local sdk_path
    sdk_path=$(get_sdk_path "$sdk")
    local build_dir="${BUILD_DIR}/${sdk}-${arch}"
    local gv_install="${build_dir}/graphviz-install"

    log_info "Building for iOS ${sdk} ${arch}..."

    mkdir -p "${build_dir}/graphviz"
    cmake -S "${GV_PATCHED}" -B "${build_dir}/graphviz" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_ARCHITECTURES="${arch}" \
        -DCMAKE_OSX_SYSROOT="${sdk_path}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${IOS_MIN_VERSION}" \
        "${GV_CMAKE_COMMON_ARGS[@]}" \
        "-DCMAKE_C_FLAGS=-arch ${arch} -isysroot ${sdk_path} -miphoneos-version-min=${IOS_MIN_VERSION} -O2 -fPIC" \
        -DCMAKE_INSTALL_PREFIX="${gv_install}"

    # Build only library targets (skip pango — not available on iOS)
    cmake --build "${build_dir}/graphviz" --parallel "$(sysctl -n hw.ncpu)" \
        --target "${GV_LIB_TARGETS[@]}" 2>&1 || true

    install_graphviz_headers "${GV_PATCHED}" "${build_dir}/graphviz" "${gv_install}"

    # Compile wrapper
    xcrun -sdk "${sdk}" clang -c -O2 \
        -arch "${arch}" \
        -isysroot "${sdk_path}" \
        -miphoneos-version-min="${IOS_MIN_VERSION}" \
        -DPACKAGE_VERSION="\"${GRAPHVIZ_VERSION}\"" \
        -I"${gv_install}/include" \
        -I"${gv_install}/include/graphviz" \
        -o "${build_dir}/graphviz_api.o" \
        "${WRAPPER_SRC}/graphviz_api.c"

    # Merge all .a and wrapper .o into single archive
    local libs=()
    while IFS= read -r lib; do
        libs+=("$lib")
    done < <(collect_static_libs "${build_dir}/graphviz" "${gv_install}")

    local tmpdir="${build_dir}/merge_objs"
    rm -rf "${tmpdir}"
    mkdir -p "${tmpdir}"
    for lib in "${libs[@]}"; do
        local libname
        libname=$(basename "$lib" .a)
        mkdir -p "${tmpdir}/${libname}"
        (cd "${tmpdir}/${libname}" && ar x "$lib")
    done
    cp "${build_dir}/graphviz_api.o" "${tmpdir}/"

    mkdir -p "${build_dir}/out"
    ar rcs "${build_dir}/out/libGraphviz.a" "${tmpdir}"/*.o "${tmpdir}"/**/*.o 2>/dev/null || \
        find "${tmpdir}" -name "*.o" -exec ar rcs "${build_dir}/out/libGraphviz.a" {} +

    rm -rf "${tmpdir}"
}

# Build for device and simulator
build_ios_arch "arm64" "iphoneos"
build_ios_arch "x86_64" "iphonesimulator"
build_ios_arch "arm64" "iphonesimulator"

# Create fat simulator library (x86_64 + arm64)
log_info "Creating fat simulator library..."
mkdir -p "${BUILD_DIR}/sim-fat"
lipo -create \
    "${BUILD_DIR}/iphonesimulator-x86_64/out/libGraphviz.a" \
    "${BUILD_DIR}/iphonesimulator-arm64/out/libGraphviz.a" \
    -output "${BUILD_DIR}/sim-fat/libGraphviz.a"

# Headers for XCFramework
HEADER_DIR="${BUILD_DIR}/iphoneos-arm64/graphviz-install/include"

# Create XCFramework
log_info "Creating XCFramework..."
rm -rf "${INSTALL_DIR}/Graphviz.xcframework"
mkdir -p "${INSTALL_DIR}"

xcodebuild -create-xcframework \
    -library "${BUILD_DIR}/iphoneos-arm64/out/libGraphviz.a" -headers "${HEADER_DIR}" \
    -library "${BUILD_DIR}/sim-fat/libGraphviz.a" -headers "${HEADER_DIR}" \
    -output "${INSTALL_DIR}/Graphviz.xcframework"

# Also install standalone header
cp "${WRAPPER_SRC}/graphviz_api.h" "${INSTALL_DIR}/"

log_info "Verifying outputs..."
verify_output "${INSTALL_DIR}/Graphviz.xcframework/Info.plist" "XCFramework"

log_info "iOS build complete: ${INSTALL_DIR}"
