#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command bison curl flex g++ gcc make perl sha256sum tar
ensure_directories

package="gcc-runtime-$GCC_RUNTIME_VERSION"
if binary_package_restore_sysroot "$package" "${BASH_SOURCE[0]}"; then
    exit 0
fi
archive="$EFILINUX_DOWNLOADS/gcc-$GCC_RUNTIME_VERSION.tar.xz"
prepare_package "$package"

download \
    "https://ftpmirror.gnu.org/gcc/gcc-$GCC_RUNTIME_VERSION/gcc-$GCC_RUNTIME_VERSION.tar.xz" \
    "$archive"
verify_sha256 "$GCC_RUNTIME_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"

build_triplet=$(gcc -dumpmachine)
target_flags="-O2 -march=$EFILINUX_X86_64_LEVEL -mtune=generic --sysroot=$EFILINUX_SYSROOT"

log "Configuring GCC runtime libraries"
cd "$PACKAGE_BUILD"
"$PACKAGE_SOURCE/configure" \
    --build="$build_triplet" \
    --host="$build_triplet" \
    --target="$build_triplet" \
    --prefix=/usr \
    --libdir=/usr/lib \
    --with-sysroot="$EFILINUX_SYSROOT" \
    --with-native-system-header-dir=/usr/include \
    --enable-languages=c,c++ \
    --disable-bootstrap \
    --disable-multilib \
    --disable-nls \
    --disable-werror \
    --disable-libstdcxx-pch \
    --disable-libsanitizer

log "Building GCC ABI runtime libraries"
make -j"$EFILINUX_JOBS" \
    CFLAGS_FOR_TARGET="$target_flags" \
    CXXFLAGS_FOR_TARGET="$target_flags" \
    all-target-libgcc all-target-libstdc++-v3
make \
    DESTDIR="$PACKAGE_STAGING" \
    CFLAGS_FOR_TARGET="$target_flags" \
    CXXFLAGS_FOR_TARGET="$target_flags" \
    install-target-libgcc install-target-libstdc++-v3

if [[ -d "$PACKAGE_STAGING/usr/lib64" ]]; then
    mkdir -p "$PACKAGE_STAGING/usr/lib"
    cp -a --remove-destination "$PACKAGE_STAGING/usr/lib64/." "$PACKAGE_STAGING/usr/lib/"
    rm -rf "$PACKAGE_STAGING/usr/lib64"
fi

[[ -f "$PACKAGE_STAGING/usr/lib/libgcc_s.so.1" ]] || \
    die "GCC runtime did not install libgcc_s.so.1"
[[ -L "$PACKAGE_STAGING/usr/lib/libstdc++.so.6" ]] || \
    die "GCC runtime did not install libstdc++.so.6"
[[ ! -d "$PACKAGE_STAGING/usr/bin" ]] || \
    die "GCC compiler programs leaked into the runtime staging tree"

binary_package_publish_sysroot "$package" "${BASH_SOURCE[0]}"
