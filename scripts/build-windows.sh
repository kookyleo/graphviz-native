#!/usr/bin/env bash
#
# Build Graphviz shared library for Windows (MSVC)
#
# Requires: CMake, MSVC 2019+ (via Visual Studio or Build Tools), Git Bash/MSYS2
#
# Usage:
#   ./scripts/build-windows.sh
#
# Environment variables:
#   BUILD_DIR   - Build directory (default: build/windows-x86_64)
#   INSTALL_DIR - Install prefix (default: output/windows-x86_64)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

ARCH="x86_64"
BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/build/windows-${ARCH}}"
INSTALL_DIR="${INSTALL_DIR:-${PROJECT_ROOT}/output/windows-${ARCH}}"

log_info "Building Graphviz for Windows ${ARCH}"

check_command "cmake"

# Prepare patched source
mkdir -p "${BUILD_DIR}"
GV_PATCHED="${BUILD_DIR}/graphviz-src"
prepare_graphviz_source "${GV_PATCHED}"

# Configure Graphviz (expat disabled — see GV_CMAKE_COMMON_ARGS which sets
# WITH_EXPAT=OFF for 14.x. We build without HTML-label parsing on Windows
# to match the 12.x-era behavior of this script. Graphviz 14.x's bundled
# FindEXPAT on the windows-latest runner picks up a system expat that
# doesn't expose its include dir on the vcxproj command line, which is why
# htmllex.c fails with "Cannot open include file: 'expat.h'".)
log_info "Configuring Graphviz..."
mkdir -p "${BUILD_DIR}/graphviz"
cmake -S "${GV_PATCHED}" -B "${BUILD_DIR}/graphviz" \
    -G "Visual Studio 17 2022" -A x64 \
    "${GV_CMAKE_COMMON_ARGS[@]}" \
    -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}/graphviz-install"

log_info "Building Graphviz library targets..."
cmake --build "${BUILD_DIR}/graphviz" --config Release --parallel \
    --target "${GV_LIB_TARGETS[@]}"

GV_INSTALL="${BUILD_DIR}/graphviz-install"
install_graphviz_headers "${GV_PATCHED}" "${BUILD_DIR}/graphviz" "${GV_INSTALL}"

# Build wrapper DLL
log_info "Building graphviz_api wrapper..."
mkdir -p "${BUILD_DIR}/wrapper" "${INSTALL_DIR}/lib" "${INSTALL_DIR}/bin" "${INSTALL_DIR}/include"

cat > "${BUILD_DIR}/wrapper/CMakeLists.txt" << 'CMAKE_EOF'
cmake_minimum_required(VERSION 3.16)
project(graphviz_api C)

file(GLOB_RECURSE GV_STATIC_LIBS "${GV_BUILD_DIR}/*.lib")
# Drop CMake scratch libs (feature probes / LTO tests) — they are compiled
# with host attributes and can pull in incompatible objects at link time.
list(FILTER GV_STATIC_LIBS EXCLUDE REGEX "CMakeFiles|_CMakeLTOTest-|/CMakeScratch/|/CMakeTmp/")
file(GLOB GV_INSTALL_LIBS "${GV_INSTALL_DIR}/lib/*.lib")
list(APPEND GV_ALL_LIBS ${GV_STATIC_LIBS} ${GV_INSTALL_LIBS})

add_library(graphviz_api SHARED "${SRC_DIR}/graphviz_api.c")

target_include_directories(graphviz_api PRIVATE
    "${GV_INSTALL_DIR}/include"
    "${GV_INSTALL_DIR}/include/graphviz"
)

target_compile_definitions(graphviz_api PRIVATE
    GRAPHVIZ_API_EXPORTS
    PACKAGE_VERSION="${GV_VERSION}"
)

target_link_libraries(graphviz_api PRIVATE ${GV_ALL_LIBS})

install(TARGETS graphviz_api
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)
CMAKE_EOF

cmake -S "${BUILD_DIR}/wrapper" -B "${BUILD_DIR}/wrapper/build" \
    -G "Visual Studio 17 2022" -A x64 \
    -DSRC_DIR="${WRAPPER_SRC}" \
    -DGV_BUILD_DIR="${BUILD_DIR}/graphviz" \
    -DGV_INSTALL_DIR="${GV_INSTALL}" \
    -DGV_VERSION="${GRAPHVIZ_VERSION}" \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}"

cmake --build "${BUILD_DIR}/wrapper/build" --config Release
cmake --install "${BUILD_DIR}/wrapper/build" --config Release

cp "${WRAPPER_SRC}/graphviz_api.h" "${INSTALL_DIR}/include/"

log_info "Verifying outputs..."
verify_output "${INSTALL_DIR}/bin/graphviz_api.dll" "Wrapper DLL"
verify_output "${INSTALL_DIR}/include/graphviz_api.h" "Wrapper header"

log_info "Windows ${ARCH} build complete: ${INSTALL_DIR}"
