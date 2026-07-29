#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/003-graphical/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/003-graphical/lib/build.sh"

ensure_directories

package="clang-headers-$LLVM_VERSION"
if graphical_binary_package_restore "$package"; then
    exit 0
fi

require_command clang cmake curl llvm-config llvm-tblgen ninja readelf sha256sum tar

host_llvm_version=$(llvm-config --version)
[[ $host_llvm_version == "$LLVM_VERSION" ]] || \
    die "host LLVM $host_llvm_version does not match required LLVM $LLVM_VERSION"
host_clang_version=$(clang --version | sed -n '1s/^clang version \([^ ]*\).*/\1/p')
[[ $host_clang_version == "$LLVM_VERSION" ]] || \
    die "host Clang $host_clang_version does not match required LLVM $LLVM_VERSION"
host_tablegen_version=$(llvm-tblgen --version | sed -n 's/^  LLVM version //p')
[[ $host_tablegen_version == "$LLVM_VERSION" ]] || \
    die "host llvm-tblgen $host_tablegen_version does not match required LLVM $LLVM_VERSION"

host_llvm_libdir=$(llvm-config --libdir)
host_clang_cpp="$host_llvm_libdir/libclang-cpp.so"
expected_clang_soname="libclang-cpp.so.${LLVM_VERSION%%.*}.1"
[[ -e $host_clang_cpp ]] || die "host libclang-cpp is missing: $host_clang_cpp"
LC_ALL=C readelf -d "$host_clang_cpp" | \
    grep -Fq "Library soname: [$expected_clang_soname]" || \
    die "host libclang-cpp does not provide $expected_clang_soname"

prepare_package "$package"
archive="llvm-project-$LLVM_VERSION.src.tar.xz"
download \
    "https://github.com/llvm/llvm-project/releases/download/llvmorg-$LLVM_VERSION/$archive" \
    "$EFILINUX_DOWNLOADS/$archive"
verify_sha256 "$LLVM_SHA256" "$EFILINUX_DOWNLOADS/$archive"
extract_source "$EFILINUX_DOWNLOADS/$archive" "$PACKAGE_SOURCE"

log "Configuring build-time Clang headers"
graphical_cmake_setup "$PACKAGE_SOURCE/clang" "$PACKAGE_BUILD" \
    -DLLVM_DIR="$EFILINUX_SYSROOT/usr/lib/cmake/llvm" \
    -DLLVM_TABLEGEN_EXE="$(command -v llvm-tblgen)" \
    -DBUILD_SHARED_LIBS=OFF \
    -DCLANG_BUILD_TOOLS=OFF \
    -DCLANG_INCLUDE_TESTS=OFF \
    -DCLANG_INCLUDE_DOCS=OFF \
    -DCLANG_BUILD_EXAMPLES=OFF \
    -DCLANG_ENABLE_STATIC_ANALYZER=OFF \
    -DCLANG_ENABLE_OBJC_REWRITER=OFF \
    -DCLANG_ENABLE_HLSL=OFF \
    -DCLANG_LINK_CLANG_DYLIB=OFF \
    -DLLVM_INCLUDE_TESTS=OFF

log "Building build-time Clang headers"
LD_LIBRARY_PATH="$EFILINUX_SYSROOT/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    cmake --build "$PACKAGE_BUILD" \
        --target clang-headers clang-resource-headers \
        -j "$EFILINUX_JOBS"

DESTDIR="$PACKAGE_STAGING" \
LD_LIBRARY_PATH="$EFILINUX_SYSROOT/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    cmake --build "$PACKAGE_BUILD" \
        --target install-clang-headers install-clang-resource-headers \
        -j "$EFILINUX_JOBS"

for artifact in \
    usr/include/clang/Config/config.h \
    usr/include/clang/Driver/Driver.h \
    usr/lib/clang/22/include/opencl-c-base.h \
    usr/lib/clang/22/include/opencl-c.h; do
    [[ -s "$PACKAGE_STAGING/$artifact" ]] || \
        die "build-time Clang header is missing: /$artifact"
done
if find "$PACKAGE_STAGING" \( -type f -o -type l \) \
    \( -path '*/usr/bin/*' -o -name 'libclang*.a' -o -name 'libclang-cpp.so*' \) \
    -print -quit | grep -q .; then
    die "Clang library or executable leaked into the header-only staging tree"
fi

find "$EFILINUX_SYSROOT/usr/lib" -maxdepth 1 \
    \( -type f -o -type l \) -name 'libclang*.a' -delete
find "$EFILINUX_SYSROOT/usr/lib" -maxdepth 1 \
    \( -type f -o -type l \) -name 'libclang-cpp.so*' -delete
graphical_binary_package_publish "$package"
