#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
source "$ROOT/modules/001-recovery/lib/target-layout.sh"
pkgname=usbimager
pkgver=1.0.10
depends=(glibc gtk3 udisks)
builddepends=()
makedepends=(gcc make pkg-config)
prepare() {
    local archive="$downloaddir/usbimager-$pkgver.tar.gz"
    download "https://gitlab.com/bztsrc/usbimager/-/archive/$pkgver/usbimager-$pkgver.tar.gz" "$archive"
    checksum sha256 582a4121bec523c5f737d4c91a5a96357243c146330d7785ab54aa3730fba4ff "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    input_shared_file "$ROOT/modules/001-recovery/lib/target-layout.sh" "$srcdir/recovery-target-layout.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    grep -qx 'CC = gcc' "$srcdir/source/src/Makefile" || die "USBImager compiler definition changed upstream"
    grep -qx 'LD = gcc' "$srcdir/source/src/Makefile" || die "USBImager linker definition changed upstream"
    grep -qx 'STRIP = strip' "$srcdir/source/src/Makefile" || die "USBImager strip definition changed upstream"
    grep -qx 'DECOMPRESSORS = zlib/libz.a bzip2/libbz2.a xz/libxz.a zstd/libzstd.a' \
        "$srcdir/source/src/Makefile" || die "USBImager bundled decompressor list changed upstream"
    grep -q -- '-I/usr/include/gio-unix-2.0' "$srcdir/source/src/Makefile" ||
        die "USBImager gio-unix include handling changed upstream"
    sed -i \
        -e 's/^CC = gcc$/CC ?= gcc/' \
        -e 's/^LD = gcc$/LD ?= gcc/' \
        -e 's/^STRIP = strip$/STRIP ?= strip/' \
        -e 's/^CFLAGS = /CFLAGS += /' \
        -e 's/^LDFLAGS =$/LDFLAGS +=/' \
        -e 's# -I/usr/include/gio-unix-2.0##g' \
        -e 's#@cd zlib && CFLAGS="$(CFLAGS_MINVER)" ./configure#@cd zlib \&\& CC="$(CC)" AR="$(AR)" RANLIB="$(RANLIB)" CFLAGS="$(CFLAGS_MINVER)" ./configure#' \
        -e 's#@make CFLAGS="$(CFLAGS_MINVER)" -C zlib libz.a#@$(MAKE) CC="$(CC)" AR="$(AR)" RANLIB="$(RANLIB)" CFLAGS="$(CFLAGS_MINVER)" -C zlib libz.a#' \
        -e 's#@make CFLAGS="$(CFLAGS_MINVER)" -C bzip2 libbz2.a#@$(MAKE) CC="$(CC)" AR="$(AR)" RANLIB="$(RANLIB)" CFLAGS="$(CFLAGS_MINVER)" -C bzip2 libbz2.a#' \
        -e 's#@make CFLAGS="$(CFLAGS_MINVER)" -C xz libxz.a#@$(MAKE) CC="$(CC) -std=gnu89" AR="$(AR)" CFLAGS="$(CFLAGS_MINVER)" -C xz libxz.a#' \
        -e 's#@make CFLAGS="$(CFLAGS_MINVER)" -C zstd libzstd.a#@$(MAKE) CC="$(CC)" AR="$(AR)" RANLIB="$(RANLIB)" CFLAGS="$(CFLAGS_MINVER)" -C zstd libzstd.a#' \
        "$srcdir/source/src/Makefile"
    ! grep -q -- '-I/usr/include/gio-unix-2.0' "$srcdir/source/src/Makefile" ||
        die "USBImager retains a host gio-unix include path"
}
build() {
    cp -a "$srcdir/source/." "$builddir/"
    (
        cd "$builddir/src"
        export CC="$(target_compiler_wrapper gcc)"
        export LD="$CC"
        export AR=ar
        export RANLIB=ranlib
        export STRIP=true
        export CFLAGS="$CFLAGS $CPPFLAGS"
        export LDFLAGS="$LDFLAGS"
        export PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT"
        export PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig"
        make -j"$EFILINUX_JOBS" USE_GTK=1 USE_UDISKS2=1
    )
    install -Dm0755 "$builddir/src/usbimager" "$develdir/opt/recovery/bin/usbimager"
    install -Dm0644 "$builddir/src/misc/usbimager.desktop" "$develdir/opt/recovery/share/applications/usbimager.desktop"
    sed -i \
        -e 's#^Version=.*#Version=1.0#' \
        -e 's#^Exec=.*#Exec=/opt/recovery/bin/usbimager#' \
        -e 's#^Icon=.*#Icon=media-removable#' \
        -e 's#^Categories=.*#Categories=System;#' \
        "$develdir/opt/recovery/share/applications/usbimager.desktop"
    recovery_publish_usr_paths "$develdir" \
        share/applications
}
check() { [[ -x "$develdir/opt/recovery/bin/usbimager" ]] || die "usbimager binary is missing"; }
devel() { strip_all "$develdir/opt/recovery/bin/usbimager"; }
package() {
    package_keep \
        /opt/recovery/bin/usbimager \
        /usr/share/applications/usbimager.desktop
}
recipe_main "$@"
