#!/usr/bin/env bash
#
# Common build utilities for graphviz-native
# Sourced by per-platform build scripts.
#
# shellcheck disable=SC2034  # Variables are used by sourcing scripts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GRAPHVIZ_SRC="${PROJECT_ROOT}/graphviz"
WRAPPER_SRC="${PROJECT_ROOT}/src"

# BUILD_DIR and INSTALL_DIR are set by each platform script
# They can be overridden via environment variables

# Graphviz version from submodule
GRAPHVIZ_VERSION="2.44.0"

log_info() {
    echo "[INFO] $*"
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required command not found: $cmd"
        return 1
    fi
}

check_build_deps() {
    local deps=("cmake" "make" "pkg-config")
    for dep in "${deps[@]}"; do
        check_command "$dep"
    done
}

# Common CMake options for Graphviz:
# - Disable GUI/editor features and plugin loading
# - Enable core layout engines
# Usage: cmake "${GV_CMAKE_COMMON_ARGS[@]}" ...
GV_CMAKE_COMMON_ARGS=(
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    -DBUILD_SHARED_LIBS=OFF
    -Denable_ltdl=OFF
    -Dwith_smyrna=OFF
    -Dwith_digcola=ON
    -Dwith_ortho=ON
    -Dwith_sfdp=ON
)

# List of CMake library targets needed for the unified build
GV_LIB_TARGETS=(
    gvc cgraph cdt pathplan xdot common
    dotgen neatogen fdpgen sfdpgen circogen twopigen osage patchwork
    pack label sparse ortho rbtree ingraphs
    gvplugin_dot_layout gvplugin_neato_layout gvplugin_core
)

# Prepare a patched Graphviz source tree with all libs forced to STATIC.
# Graphviz CMakeLists hardcodes SHARED for some public libs;
# we need everything STATIC so we can merge into a single .so/.dylib.
#
# Usage: prepare_graphviz_source <output_dir>
prepare_graphviz_source() {
    local output_dir="$1"
    if [ ! -d "${output_dir}" ]; then
        log_info "Patching Graphviz source for static build..."
        cp -a "${GRAPHVIZ_SRC}" "${output_dir}"
        find "${output_dir}" -name CMakeLists.txt -exec \
            sed -i 's/add_library(\([^ ]*\) SHARED/add_library(\1 STATIC/g' {} +
    fi
}

# Install Graphviz headers from a patched source tree + build directory.
#
# Usage: install_graphviz_headers <patched_src> <build_dir> <install_dir>
install_graphviz_headers() {
    local src="$1"
    local build_dir="$2"
    local install_dir="$3"

    mkdir -p "${install_dir}/include/graphviz"
    # Generated config.h
    cp "${build_dir}/config.h" "${install_dir}/include/graphviz/" 2>/dev/null || true
    # All .h from lib/
    find "${src}/lib" -name "*.h" -exec cp {} "${install_dir}/include/graphviz/" \; 2>/dev/null
}

# Collect all .a files from a build tree.
# Prints paths to stdout.
#
# Usage: collect_static_libs <build_dir> <install_dir>
collect_static_libs() {
    local build_dir="$1"
    local install_dir="$2"
    find "${build_dir}" "${install_dir}" -name "*.a" -type f 2>/dev/null | sort -u
}

verify_output() {
    local file="$1"
    local desc="$2"
    if [ -f "$file" ]; then
        local size
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "unknown")
        log_info "${desc}: ${file} (${size} bytes)"
    else
        log_error "${desc} not found: ${file}"
        return 1
    fi
}
