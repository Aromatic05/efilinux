#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
source "$ROOT/modules/001-recovery/lib/target-layout.sh"
pkgname=grsync-gtk3
pkgver=1
depends=(glib glibc gtk3 rsync)
builddepends=()
makedepends=(gcc pkg-config)
prepare() {
    input_tree "$recipedir/files" "$srcdir/files"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    input_shared_file "$ROOT/modules/001-recovery/lib/target-layout.sh" "$srcdir/recovery-target-layout.sh"
}
build() {
    local cc
    cc=$(target_compiler_wrapper gcc)
    mkdir -p "$develdir/opt/recovery/bin"
    PKG_CONFIG_PATH= \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        "$cc" $CPPFLAGS $CFLAGS \
        $(PKG_CONFIG_PATH= PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
          PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
          pkg-config --cflags gtk+-3.0 gio-2.0) \
        "$srcdir/files/src/grsync.c" \
        $LDFLAGS \
        $(PKG_CONFIG_PATH= PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
          PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
          pkg-config --libs gtk+-3.0 gio-2.0) \
        -o "$develdir/opt/recovery/bin/grsync"
    install -d -m0755 "$develdir/opt/recovery/share"
    cp -a "$srcdir/files/usr/share/." "$develdir/opt/recovery/share/"
    recovery_publish_usr_paths "$develdir" \
        share/applications
}
check() { [[ -x "$develdir/opt/recovery/bin/grsync" ]] || die "GTK 3 Grsync binary is missing"; }
devel() { strip_all "$develdir/opt/recovery/bin/grsync"; }
package() {
    package_keep \
        /opt/recovery/bin/grsync \
        /usr/share/applications/grsync.desktop
}
recipe_main "$@"
