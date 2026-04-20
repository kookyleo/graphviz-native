#!/usr/bin/env bash
#
# Common build utilities for graphviz-anywhere
# Sourced by per-platform build scripts.
#
# shellcheck disable=SC2034  # Variables are used by sourcing scripts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GRAPHVIZ_SRC="${PROJECT_ROOT}/graphviz"
WRAPPER_SRC="${PROJECT_ROOT}/capi"

# BUILD_DIR and INSTALL_DIR are set by each platform script
# They can be overridden via environment variables

# Graphviz version from submodule (keep in sync with `graphviz/` checkout)
GRAPHVIZ_VERSION="14.1.5"

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
#
# Graphviz 14.x renamed the CMake flag family to UPPERCASE and defaults
# `WITH_EXPAT`/`WITH_ZLIB` to AUTO (ON if detected). We explicitly force
# them OFF because our native wrapper doesn't link expat/zlib and we want
# behavior identical to the Graphviz 12.x era. The old lowercase vars are
# kept for belt-and-braces compat with older CMakeLists that still read them.
#
# Usage: cmake "${GV_CMAKE_COMMON_ARGS[@]}" ...
GV_CMAKE_COMMON_ARGS=(
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    -DBUILD_SHARED_LIBS=OFF
    # CMake's IPO/LTO test emits a host-tagged libfoo.a we'd accidentally
    # sweep into the final link on cross-compile targets (notably Android).
    # Disable it globally; we don't need LTO for the static libs.
    -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF
    # 14.x UPPERCASE flag family — these are the authoritative names.
    -DWITH_EXPAT=OFF
    -DWITH_ZLIB=OFF
    -DWITH_GVEDIT=OFF
    -DWITH_SMYRNA=OFF
    -DENABLE_LTDL=OFF
    -DENABLE_TCL=OFF
    -DENABLE_SWIG=OFF
    -DGRAPHVIZ_CLI=OFF
    # Graphviz 14.x's neatogen/delaunay.c pulls in GTS + glib when
    # find_package(GTS) succeeds. Windows-latest has GTS installed via
    # chocolatey's toolchain, which then breaks our static link because
    # glib / GTS aren't in our wrapper's library list. Suppress the
    # find_package entirely so delaunay.c uses its no-GTS branch.
    # ANN is similarly optional and unused by our wrapper surface.
    -DCMAKE_DISABLE_FIND_PACKAGE_GTS=TRUE
    -DCMAKE_DISABLE_FIND_PACKAGE_ANN=TRUE
    # Legacy lowercase names, still read by some CMakeLists.
    -Denable_ltdl=OFF
    -Dwith_smyrna=OFF
    -Dwith_digcola=ON
    -Dwith_ortho=ON
    -Dwith_sfdp=ON
)

# List of CMake library targets needed for the unified build.
# Adjusted for Graphviz 14.x layout: `ingraphs` is now folded into cgraph;
# `util` and `vpsc` are first-class libs.
GV_LIB_TARGETS=(
    gvc cgraph cdt pathplan xdot common util vpsc
    dotgen neatogen fdpgen sfdpgen circogen twopigen osage patchwork
    pack label sparse ortho rbtree
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
        # Use cp -r with error suppression for Windows symlink compatibility
        cp -r "${GRAPHVIZ_SRC}" "${output_dir}" 2>/dev/null || true
        if [ ! -d "${output_dir}/lib" ]; then
            log_error "Failed to copy Graphviz source"
            exit 1
        fi
        # Graphviz 14.x ships a handful of source files containing non-UTF8
        # bytes (e.g. translated strings, author names). BSD sed on macOS
        # aborts with "RE error: illegal byte sequence" unless we pin the
        # locale to C for byte-literal processing. GNU sed is unaffected
        # but the override is harmless there.
        export LC_ALL=C
        export LANG=C
        # Patch CMakeLists: SHARED→STATIC, remove LTDL/EXPAT/ZLIB refs, remove DLL export macros
        # Use sed -i.bak for BSD/GNU sed compatibility
        find "${output_dir}" -name CMakeLists.txt -exec \
            sed -i.bak \
                -e 's/add_library(\([^ ]*\) SHARED/add_library(\1 STATIC/g' \
                -e 's/\${LTDL_INCLUDE_DIRS}//g' \
                -e 's/\${LTDL_INCLUDE_DIR}//g' \
                -e 's/\${LTDL_LIBRARIES}//g' \
                -e 's/\${LTDL_LIBRARY}//g' \
                -e 's/\${EXPAT_INCLUDE_DIRS}//g' \
                -e 's/\${EXPAT_INCLUDE_DIR}//g' \
                -e 's/\${EXPAT_LIBRARIES}//g' \
                -e 's/\${EXPAT_LIBRARY}//g' \
                -e 's/\${ZLIB_INCLUDE_DIRS}//g' \
                -e 's/\${ZLIB_INCLUDE_DIR}//g' \
                -e 's/\${ZLIB_LIBRARIES}//g' \
                -e 's/\${ZLIB_LIBRARY}//g' \
                -e 's/-DEXPORT_[A-Z]*//g' \
                {} +
        # Top-level CMakeLists: remove cmd/tclpkg (we only build libs), and
        # neutralize the UNIX `find_library(MATH_LIB m)` step which fails
        # under Emscripten (libm is built into musl and has no *.a on disk).
        # Replacing with a direct `-lm` that emcc knows how to resolve.
        # Also force-disable the IPO auto-enable so
        # `-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF` on the command line
        # actually wins — Graphviz 14.x unconditionally sets IPO=ON for
        # Release builds, which emits LLVM bitcode objects that
        # xcodebuild -create-xcframework refuses on iOS.
        sed -i.bak \
            -e '/add_subdirectory(cmd)/d' \
            -e '/add_subdirectory(tclpkg)/d' \
            -e 's|find_library(MATH_LIB m)|set(MATH_LIB m CACHE STRING "math library")|' \
            -e 's|set(CMAKE_INTERPROCEDURAL_OPTIMIZATION ON)|set(CMAKE_INTERPROCEDURAL_OPTIMIZATION OFF)|' \
            "${output_dir}/CMakeLists.txt"
        # Strip __declspec from headers for clean static linking on Windows
        find "${output_dir}" -name "*.h" -exec \
            sed -i.bak \
                -e 's/__declspec(dllexport)//g' \
                -e 's/__declspec(dllimport)//g' \
                {} +
        # Create regex compatibility header (stubs for Windows MSVC, real regex.h elsewhere)
        cat > "${output_dir}/lib/gvc/regex_compat.h" << 'REGEX_EOF'
#ifndef REGEX_COMPAT_H
#define REGEX_COMPAT_H
#ifdef _WIN32
/* Stub POSIX regex for Windows static builds */
typedef struct { int unused; } regex_t;
typedef int regoff_t;
typedef struct { regoff_t rm_so; regoff_t rm_eo; } regmatch_t;
#define REG_EXTENDED 1
#define REG_NOSUB 2
static inline int regcomp(regex_t *re, const char *pattern, int flags) { (void)re; (void)pattern; (void)flags; return -1; }
static inline int regexec(const regex_t *re, const char *str, size_t nmatch, regmatch_t pmatch[], int flags) { (void)re; (void)str; (void)nmatch; (void)pmatch; (void)flags; return -1; }
static inline void regfree(regex_t *re) { (void)re; }
#else
#include <regex.h>
#endif
#endif
REGEX_EOF
        sed -i.bak 's|#include <regex.h>|#include "regex_compat.h"|g' \
            "${output_dir}/lib/gvc/gvusershape.c" \
            "${output_dir}/lib/gvc/gvconfig.c"
        # Fix malloc.h (not available on macOS/iOS — use stdlib.h instead)
        find "${output_dir}" -name "*.c" -exec \
            sed -i.bak 's|#include <malloc.h>|#include <stdlib.h>|g' {} +
        # Stub out system() calls (unavailable on iOS)
        sed -i.bak 's|return system(c);|return -1; /* system() unavailable on iOS */|g' \
            "${output_dir}/lib/sparse/general.c"
        find "${output_dir}" -name "*.bak" -delete
    fi
}

# Download expat source for cross-compilation targets that lack it.
# Usage: download_expat <target_dir>
download_expat() {
    local target_dir="$1"
    local version="${EXPAT_VERSION:-2.6.2}"
    if [ ! -d "${target_dir}" ]; then
        local url="https://github.com/libexpat/libexpat/releases/download/R_${version//./_}/expat-${version}.tar.gz"
        log_info "Downloading expat ${version}..."
        mkdir -p "$(dirname "${target_dir}")"
        curl -sL "${url}" | tar xz -C "$(dirname "${target_dir}")"
        mv "$(dirname "${target_dir}")/expat-${version}" "${target_dir}"
    fi
}

# Build expat as a static library for cross-compilation.
# Usage: build_expat <source_dir> <build_dir> <install_dir> [extra_cmake_args...]
build_expat() {
    local source_dir="$1"
    local build_dir="$2"
    local install_dir="$3"
    shift 3
    local cmake_extra_args=("$@")

    if [ -f "${install_dir}/lib/libexpat.a" ] || [ -f "${install_dir}/lib/expat.lib" ]; then
        return 0
    fi

    log_info "Building expat..."
    mkdir -p "${build_dir}"
    cmake -S "${source_dir}" -B "${build_dir}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DEXPAT_BUILD_TOOLS=OFF \
        -DEXPAT_BUILD_EXAMPLES=OFF \
        -DEXPAT_BUILD_TESTS=OFF \
        -DEXPAT_BUILD_DOCS=OFF \
        -DEXPAT_BUILD_FUZZERS=OFF \
        -DEXPAT_BUILD_PKGCONFIG=OFF \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DCMAKE_INSTALL_PREFIX="${install_dir}" \
        "${cmake_extra_args[@]}"

    cmake --build "${build_dir}" --config Release \
        --parallel "$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
    cmake --install "${build_dir}" --config Release
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
# Excludes:
#   - CMake's internal `_CMakeLTOTest-*/bin/libfoo.a` scratch archive (it's
#     built with host attributes and breaks cross-target links, notably
#     Android x86_64 where it's tagged for glibc-x86_64 ELF).
#   - CMake feature-probe scratch under CMakeFiles/<check>/.
#
# Usage: collect_static_libs <build_dir> <install_dir>
collect_static_libs() {
    local build_dir="$1"
    local install_dir="$2"
    find "${build_dir}" "${install_dir}" -name "*.a" -type f 2>/dev/null \
        | grep -Ev '(_CMakeLTOTest-|/CMakeScratch/|/CMakeTmp/)' \
        | sort -u
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
