#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/001-runtime/audio-libraries/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command cmake curl gcc ninja pkg-config sha256sum tar
ensure_directories

package="libsndfile-$LIBSNDFILE_VERSION"
recipe_inputs=("$ROOT/001-runtime/audio-libraries/config.sh")
if binary_package_restore_sysroot \
    "$package" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"; then
    exit 0
fi

archive="$EFILINUX_DOWNLOADS/$package.tar.xz"
prepare_package "$package"
download \
    "https://github.com/libsndfile/libsndfile/releases/download/$LIBSNDFILE_VERSION/$package.tar.xz" \
    "$archive"
verify_sha256 "$LIBSNDFILE_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"

cmake -S "$PACKAGE_SOURCE" -B "$PACKAGE_BUILD" -G Ninja \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_SYSROOT="$EFILINUX_SYSROOT" \
    -DCMAKE_C_FLAGS="$(target_cflags)" \
    -DCMAKE_EXE_LINKER_FLAGS="$(target_ldflags)" \
    -DCMAKE_SHARED_LINKER_FLAGS="$(target_ldflags)" \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_PROGRAMS=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_REGTEST=OFF \
    -DBUILD_TESTING=OFF \
    -DENABLE_EXTERNAL_LIBS=OFF \
    -DENABLE_MPEG=OFF \
    -DENABLE_EXPERIMENTAL=OFF \
    -DENABLE_CPACK=OFF \
    -DENABLE_BOW_DOCS=OFF \
    -DENABLE_PACKAGE_CONFIG=ON
cmake --build "$PACKAGE_BUILD" -j "$EFILINUX_JOBS"
DESTDIR="$PACKAGE_STAGING" cmake --install "$PACKAGE_BUILD"
find "$PACKAGE_STAGING" -type f -name '*.a' -delete

binary_package_publish_sysroot \
    "$package" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"
