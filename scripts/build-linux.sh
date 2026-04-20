#!/usr/bin/env bash
#
# Build Graphviz shared library for Linux
#
# Builds all Graphviz components as static libraries, then links them
# together with the C ABI wrapper into a single unified libgraphviz_api.so.
#
# Usage:
#   ./scripts/build-linux.sh [--arch x86_64|aarch64]
#
# Environment variables:
#   BUILD_DIR   - Build directory (default: build/linux-<arch>)
#   INSTALL_DIR - Install prefix (default: output/linux-<arch>)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

ARCH="${ARCH:-$(uname -m)}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --arch) ARCH="$2"; shift 2 ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

case "$ARCH" in
    x86_64|amd64) ARCH="x86_64" ;;
    aarch64|arm64) ARCH="aarch64" ;;
    *) log_error "Unsupported architecture: $ARCH"; exit 1 ;;
esac

BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/build/linux-${ARCH}}"
INSTALL_DIR="${INSTALL_DIR:-${PROJECT_ROOT}/output/linux-${ARCH}}"

log_info "Building Graphviz for Linux ${ARCH}"
log_info "Build directory: ${BUILD_DIR}"
log_info "Install directory: ${INSTALL_DIR}"

check_build_deps
for dep in bison flex; do
    check_command "$dep"
done

# Detect extra include paths for harfbuzz (needed by pango headers on some distros)
HB_CFLAGS=""
if command -v pkg-config &>/dev/null; then
    HB_CFLAGS="$(pkg-config --cflags-only-I harfbuzz 2>/dev/null || true)"
fi

# Step 1: Prepare patched source
mkdir -p "${BUILD_DIR}"
GV_PATCHED="${BUILD_DIR}/graphviz-src"
prepare_graphviz_source "${GV_PATCHED}"

# Step 2: Configure and build Graphviz (all static)
log_info "Configuring Graphviz..."
mkdir -p "${BUILD_DIR}/graphviz"
cmake -S "${GV_PATCHED}" -B "${BUILD_DIR}/graphviz" \
    "${GV_CMAKE_COMMON_ARGS[@]}" \
    "-DCMAKE_C_FLAGS=-O2 -fPIC ${HB_CFLAGS}" \
    -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}/graphviz-install"

log_info "Building Graphviz library targets..."
GV_TARGETS=("${GV_LIB_TARGETS[@]}")
# Add pango plugin if available
if pkg-config --exists pangocairo 2>/dev/null; then
    GV_TARGETS+=("gvplugin_pango")
fi
cmake --build "${BUILD_DIR}/graphviz" --parallel "$(nproc)" \
    --target "${GV_TARGETS[@]}"

GV_INSTALL="${BUILD_DIR}/graphviz-install"
install_graphviz_headers "${GV_PATCHED}" "${BUILD_DIR}/graphviz" "${GV_INSTALL}"

# Step 3: Collect all static libraries and build unified .so
log_info "Collecting static libraries..."
GV_STATIC_LIBS=()
while IFS= read -r lib; do
    GV_STATIC_LIBS+=("$lib")
done < <(collect_static_libs "${BUILD_DIR}/graphviz" "${GV_INSTALL}")
log_info "Found ${#GV_STATIC_LIBS[@]} static libraries"

log_info "Building unified libgraphviz_api.so..."
mkdir -p "${INSTALL_DIR}/lib" "${INSTALL_DIR}/include"

gcc -c -fPIC -O2 \
    -DPACKAGE_VERSION="\"${GRAPHVIZ_VERSION}\"" \
    -I"${GV_INSTALL}/include" \
    -I"${GV_INSTALL}/include/graphviz" \
    -o "${BUILD_DIR}/graphviz_api.o" \
    "${WRAPPER_SRC}/graphviz_api.c"

# System libraries. WITH_EXPAT=OFF / WITH_ZLIB=OFF in GV_CMAKE_COMMON_ARGS
# means the static libs shouldn't reference libexpat / libz. Keep them in
# SYS_LIBS defensively on Linux where apt pulls them in anyway — the linker
# will just resolve them. Drop only if the link actually fails.
SYS_LIBS=(-lm -lz -lexpat)
if pkg-config --exists pangocairo 2>/dev/null; then
    while IFS= read -r flag; do
        [[ -n "$flag" ]] && SYS_LIBS+=("$flag")
    done < <(pkg-config --libs pangocairo | tr ' ' '\n')
fi

gcc -shared -o "${INSTALL_DIR}/lib/libgraphviz_api.so" \
    "${BUILD_DIR}/graphviz_api.o" \
    -Wl,--whole-archive \
    "${GV_STATIC_LIBS[@]}" \
    -Wl,--no-whole-archive \
    "${SYS_LIBS[@]}"

cp "${WRAPPER_SRC}/graphviz_api.h" "${INSTALL_DIR}/include/"

# Step 4: Verify
log_info "Verifying outputs..."
verify_output "${INSTALL_DIR}/lib/libgraphviz_api.so" "Unified shared library"
verify_output "${INSTALL_DIR}/include/graphviz_api.h" "Wrapper header"

log_info "Library size: $(du -h "${INSTALL_DIR}/lib/libgraphviz_api.so" | cut -f1)"
log_info "Linux ${ARCH} build complete: ${INSTALL_DIR}"
