#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/001-runtime/storage-libraries/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command cmake curl gcc make ninja pkg-config sha256sum tar
ensure_directories
recipe_inputs=("$ROOT/001-runtime/storage-libraries/config.sh")

restore_package() {
    binary_package_restore_sysroot "$1" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"
}

publish_package() {
    find "$PACKAGE_STAGING" -type f -name '*.la' -delete 2>/dev/null || true
    binary_package_publish_sysroot "$1" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"
}

prepare_archive() {
    local package=$1 archive_name=$2 digest=$3 url=$4
    local archive="$EFILINUX_DOWNLOADS/$archive_name"
    prepare_package "$package"
    download "$url" "$archive"
    verify_sha256 "$digest" "$archive"
    extract_source "$archive" "$PACKAGE_SOURCE"
}

configure_target() {
    local source=$1
    shift
    (
        cd "$PACKAGE_BUILD"
        CC=gcc \
        CFLAGS="$(target_cflags) -std=gnu17" \
        LDFLAGS="$(target_ldflags)" \
        PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
        PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
            "$source/configure" \
                --prefix=/usr \
                --libdir=/usr/lib \
                --disable-static \
                --enable-shared \
                "$@"
    )
    make -C "$PACKAGE_BUILD" -j "$EFILINUX_JOBS"
    make -C "$PACKAGE_BUILD" DESTDIR="$PACKAGE_STAGING" install
}

package="gmp-$GMP_VERSION"
if ! restore_package "$package"; then
    prepare_archive "$package" "$package.tar.xz" "$GMP_SHA256" \
        "https://ftp.gnu.org/gnu/gmp/$package.tar.xz"
    configure_target "$PACKAGE_SOURCE" --enable-cxx=no
    publish_package "$package"
fi

package="mpfr-$MPFR_VERSION"
if ! restore_package "$package"; then
    prepare_archive "$package" "$package.tar.xz" "$MPFR_SHA256" \
        "https://ftp.gnu.org/gnu/mpfr/$package.tar.xz"
    configure_target "$PACKAGE_SOURCE"
    publish_package "$package"
fi

package="json-c-$JSON_C_VERSION"
if ! restore_package "$package"; then
    prepare_archive "$package" "$package.tar.gz" "$JSON_C_SHA256" \
        "https://s3.amazonaws.com/json-c_releases/releases/$package.tar.gz"
    cmake -S "$PACKAGE_SOURCE" -B "$PACKAGE_BUILD" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_SYSROOT="$EFILINUX_SYSROOT" \
        -DCMAKE_C_FLAGS="$(target_cflags)" \
        -DCMAKE_EXE_LINKER_FLAGS="$(target_ldflags)" \
        -DCMAKE_SHARED_LINKER_FLAGS="$(target_ldflags)" \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_STATIC_LIBS=OFF \
        -DBUILD_TESTING=OFF \
        -DDISABLE_WERROR=ON
    cmake --build "$PACKAGE_BUILD" -j "$EFILINUX_JOBS"
    DESTDIR="$PACKAGE_STAGING" cmake --install "$PACKAGE_BUILD"
    publish_package "$package"
fi

package="popt-$POPT_VERSION"
if ! restore_package "$package"; then
    prepare_archive "$package" "$package.tar.gz" "$POPT_SHA256" \
        "https://ftp.osuosl.org/pub/rpm/popt/releases/popt-1.x/$package.tar.gz"
    configure_target "$PACKAGE_SOURCE" --disable-nls
    publish_package "$package"
fi

package="keyutils-$KEYUTILS_VERSION"
if ! restore_package "$package"; then
    prepare_archive "$package" "$package.tar.gz" "$KEYUTILS_SHA256" \
        "https://git.kernel.org/pub/scm/linux/kernel/git/dhowells/keyutils.git/snapshot/keyutils-v$KEYUTILS_VERSION.tar.gz"
    make -C "$PACKAGE_SOURCE" -j "$EFILINUX_JOBS" \
        CC=gcc \
        CFLAGS="$(target_cflags)" \
        LDFLAGS="$(target_ldflags)" \
        NO_ARLIB=1 \
        BINDIR=/usr/bin \
        SBINDIR=/usr/bin \
        LIBDIR=/usr/lib \
        USRLIBDIR=/usr/lib
    make -C "$PACKAGE_SOURCE" install \
        DESTDIR="$PACKAGE_STAGING" \
        NO_ARLIB=1 \
        BINDIR=/usr/bin \
        SBINDIR=/usr/bin \
        LIBDIR=/usr/lib \
        USRLIBDIR=/usr/lib
    publish_package "$package"
fi
