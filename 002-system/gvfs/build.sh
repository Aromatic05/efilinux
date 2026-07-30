#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=gvfs
pkgver=1.60.1

depends=(elogind fuse glib glibc libarchive libgcrypt libgudev libsecret polkit udisks)
builddepends=()
makedepends=(gcc meson ninja pkg-config)

prepare() {
    local archive="$downloaddir/gvfs-$pkgver.tar.gz"
    download \
        "https://gitlab.gnome.org/GNOME/gvfs/-/archive/$pkgver/gvfs-$pkgver.tar.gz" \
        "$archive"
    checksum sha256 cfd4ae68d6f68e3ddc611181238f666dd59dd14390d97c7576b4132823db429a "$archive"
    extract "$archive" "$srcdir/gvfs"
}

build() {
    sed -i \
        -e "/^dbus_session_bus_services_dir = dependency/,/^)/c\dbus_session_bus_services_dir = gvfs_datadir / 'dbus-1' / 'services'" \
        -e "/^gio_giomoduledir = gio_dep.get_variable/,/^)/c\gio_giomoduledir = gvfs_libdir / 'gio' / 'modules'" \
        -e "/^gio_schemasdir = gio_dep.get_variable/,/^)/c\gio_schemasdir = gvfs_datadir / 'glib-2.0' / 'schemas'" \
        "$srcdir/gvfs/meson.build"

    CC="$CC" \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        meson setup "$builddir" "$srcdir/gvfs" \
            --prefix=/usr \
            --libdir=lib \
            --libexecdir=lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --buildtype=release \
            --wrap-mode=nodownload \
            -Dsystemduserunitdir=no \
            -Dtmpfilesdir=no \
            -Dprivileged_group=wheel \
            -Dadmin=true \
            -Darchive=true \
            -Dsftp=true \
            -Dudisks2=true \
            -Dfuse=true \
            -Dgcrypt=true \
            -Dgudev=true \
            -Dkeyring=true \
            -Dlogind=true \
            -Dafc=false \
            -Dafp=false \
            -Dburn=false \
            -Dcdda=false \
            -Ddnssd=false \
            -Dgoa=false \
            -Dgoogle=false \
            -Dgphoto2=false \
            -Dhttp=false \
            -Dmtp=false \
            -Dnfs=false \
            -Donedrive=false \
            -Dsmb=false \
            -Dwsdd=false \
            -Dbluray=false \
            -Dgcr=false \
            -Dlibusb=false \
            -Ddevel_utils=false \
            -Dinstalled_tests=false \
            -Dunit_tests=false \
            -Dman=false
    meson compile -C "$builddir" -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" meson install -C "$builddir"
}

devel() {
    strip_all "$develdir/usr/lib"
}

package() {
    local helper
    local -a keep=(
        /usr/lib/gvfs/
        /usr/lib/gio/modules/
        /usr/share/dbus-1/
        /usr/share/glib-2.0/schemas/
        /usr/share/gvfs/
        /usr/share/polkit-1/actions/org.gtk.vfs.file-operations.policy
        /usr/share/polkit-1/rules.d/org.gtk.vfs.file-operations.rules
    )

    shopt -s nullglob
    for helper in "$pkgdir/usr/lib"/gvfsd* "$pkgdir/usr/lib"/gvfs-*-volume-monitor; do
        keep+=("/${helper#"$pkgdir/"}")
    done
    shopt -u nullglob
    package_keep "${keep[@]}"
}

recipe_main "$@"
