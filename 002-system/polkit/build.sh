#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=polkit
pkgver=127

depends=(duktape elogind expat glib glibc linux-pam)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/polkit-$pkgver.tar.gz"
    download \
        "https://github.com/polkit-org/polkit/archive/refs/tags/$pkgver.tar.gz" \
        "$archive"
    checksum sha256 9b7bc16f086479dcc626c575976568ba4a85d34297a750d8ab3d2e57f6d8b988 "$archive"
    extract "$archive" "$srcdir/polkit"
}

build() {
    python3 - "$srcdir/polkit/meson.build" <<'PATCH'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
start = text.index("dbus_dep = dependency('dbus-1', required: false)")
end = text.index(chr(10) + "# check OS", start)
replacement = """dbus_dep = dependency('dbus-1', required: false)
dbus_policydir = pk_prefix / pk_datadir / 'dbus-1/system.d'
dbus_system_bus_services_dir = pk_prefix / pk_datadir / 'dbus-1/system-services'
"""
path.write_text(text[:start] + replacement + text[end:])
PATCH

    CC="$CC" \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        meson setup "$builddir" "$srcdir/polkit" \
            --prefix=/usr \
            --libdir=lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --buildtype=release \
            --wrap-mode=nodownload \
            -Dsession_tracking=elogind \
            -Dsystemdsystemunitdir='' \
            -Dpolkitd_user=polkitd \
            -Dpolkitd_uid=102 \
            -Dprivileged_group=wheel \
            -Dauthfw=pam \
            -Dos_type=lfs \
            -Dpam_include=system-auth \
            -Dpam_prefix=/etc/pam.d \
            -Dexamples=false \
            -Dtests=false \
            -Dintrospection=false \
            -Dgtk_doc=false \
            -Dman=false \
            -Dgettext=true
    meson compile -C "$builddir" -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" meson install -C "$builddir"
}

devel() {
    rm -rf \
        "$develdir/usr/lib/systemd" \
        "$develdir/usr/lib/sysusers.d" \
        "$develdir/usr/lib/tmpfiles.d"
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=(
        /etc/pam.d/
        /usr/bin/pkaction
        /usr/bin/pkcheck
        /usr/bin/pkexec
        /usr/bin/pkttyagent
        /usr/lib/polkit-1/
        /usr/share/dbus-1/
        /usr/share/polkit-1/
    )
    package_add_library_family keep 'libpolkit-agent-1.so.0*'
    package_add_library_family keep 'libpolkit-gobject-1.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
