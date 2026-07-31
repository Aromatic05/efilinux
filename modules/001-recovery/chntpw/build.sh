#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=chntpw
pkgver=140201
depends=(glibc libgcrypt)
builddepends=()
makedepends=(gcc make patch pkg-config tar unzip xz)

prepare() {
    local archive="$downloaddir/chntpw-source-$pkgver.zip"
    local debian_archive="$downloaddir/chntpw_${pkgver}-1.3.debian.tar.xz"
    download "https://pogostick.net/~pnh/ntpasswd/chntpw-source-$pkgver.zip" "$archive"
    checksum sha256 96e20905443e24cba2f21e51162df71dd993a1c02bfa12b1be2d0801a4ee2ccc "$archive"
    download "https://deb.debian.org/debian/pool/main/c/chntpw/chntpw_${pkgver}-1.3.debian.tar.xz" \
        "$debian_archive"
    checksum sha256 ee91998513f4073f364f8b1fb8ebd2f1e9f8400dde591fa99f10e853e5e09ebe \
        "$debian_archive"
    extract_zip "$archive" "$srcdir/source" "chntpw-$pkgver"
    extract_contents "$debian_archive" "$srcdir/debian"
    input_file "$recipedir/files/gcc16-64bit.patch" "$srcdir/gcc16-64bit.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return

    local patch_name
    local -a debian_patches=(
        01_port_to_gcrypt.patch
        04_get_abs_path
        06_correct_test_open_syscall
        07_detect_failure_to_write_key
        08_no_deref_null
        09_improve_robustness
        10_remove_static
        12_readonly_filesystem
        13_write_to_hive
        14_improve_description
        15_added_samunlock_binary
        16_gcry-pkg-config.diff
        17_hexdump-pointer-type.patch
    )
    for patch_name in "${debian_patches[@]}"; do
        patch -d "$srcdir/source" -Np1 -i "$srcdir/debian/debian/patches/$patch_name"
    done
    patch -d "$srcdir/source" -Np1 -i "$srcdir/gcc16-64bit.patch"
}

build() {
    local compiler gcrypt_cflags gcrypt_libs
    compiler=$(target_compiler_wrapper gcc)
    gcrypt_cflags=$(
        PKG_CONFIG_PATH= \
        PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
        PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
            pkg-config --cflags libgcrypt
    )
    gcrypt_libs=$(
        PKG_CONFIG_PATH= \
        PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
        PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
            pkg-config --libs libgcrypt
    )
    make -C "$srcdir/source" -j"$EFILINUX_JOBS" \
        CC="$compiler" \
        CFLAGS="$CFLAGS -DUSELIBGCRYPT -I. $gcrypt_cflags" \
        LIBS="$LDFLAGS $gcrypt_libs" \
        chntpw reged samusrgrp sampasswd samunlock
    install -Dm0755 "$srcdir/source/chntpw" "$develdir/usr/bin/chntpw"
    install -Dm0755 "$srcdir/source/reged" "$develdir/usr/bin/reged"
    install -Dm0755 "$srcdir/source/samusrgrp" "$develdir/usr/bin/samusrgrp"
    install -Dm0755 "$srcdir/source/sampasswd" "$develdir/usr/bin/sampasswd"
    install -Dm0755 "$srcdir/source/samunlock" "$develdir/usr/bin/samunlock"
}

devel() {
    strip_all "$develdir/usr/bin"
}

package() {
    package_keep \
        /usr/bin/chntpw \
        /usr/bin/reged \
        /usr/bin/samusrgrp \
        /usr/bin/sampasswd \
        /usr/bin/samunlock
}

recipe_main "$@"
