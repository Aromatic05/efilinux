#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/001-runtime/config.sh"
source "$ROOT/001-runtime/desktop-libraries/config.sh"
source "$ROOT/002-system/desktop-services/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command curl gcc meson ninja pkg-config sha256sum tar
ensure_directories

recipe_inputs=(
    "$ROOT/001-runtime/config.sh"
    "$ROOT/002-system/desktop-services/config.sh"
)

restore_package() {
    binary_package_restore_sysroot \
        "$1" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"
}

publish_package() {
    binary_package_publish_sysroot \
        "$1" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"
}

prepare_tar_package() {
    local package=$1 archive_name=$2 digest=$3 url=$4
    local archive="$EFILINUX_DOWNLOADS/$archive_name"

    prepare_package "$package"
    download "$url" "$archive"
    verify_sha256 "$digest" "$archive"
    extract_source "$archive" "$PACKAGE_SOURCE"
}

meson_target() {
    local source=$1
    shift
    CC=gcc \
    CFLAGS="$(target_cflags)" \
    LDFLAGS="$(target_ldflags)" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    meson setup "$PACKAGE_BUILD" "$source" \
            --prefix=/usr \
            --libdir=lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --buildtype=release \
            --wrap-mode=nodownload \
            "$@"
    meson compile -C "$PACKAGE_BUILD" -j "$EFILINUX_JOBS"
    DESTDIR="$PACKAGE_STAGING" \
        meson install -C "$PACKAGE_BUILD"
}

package="elogind-$ELOGIND_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.gz" "$ELOGIND_SHA256" \
        "https://github.com/elogind/elogind/archive/refs/tags/v$ELOGIND_VERSION.tar.gz"
    meson_target "$PACKAGE_SOURCE" \
        -Dmode=release \
        -Dsplit-bin=true \
        -Dstatic-libelogind=false \
        -Dsysvinit-path=/etc/rc.d/init.d \
        -Dsysvrcnd-path=/etc/rc.d \
        -Dudevrulesdir=/usr/lib/udev/rules.d \
        -Ddbuspolicydir=/usr/share/dbus-1/system.d \
        -Ddbussystemservicedir=/usr/share/dbus-1/system-services \
        -Dpkgconfiglibdir=/usr/lib/pkgconfig \
        -Dpamlibdir=/usr/lib/security \
        -Dpamconfdir=/etc/pam.d \
        -Dhalt-path=/usr/bin/halt \
        -Dpoweroff-path=/usr/bin/poweroff \
        -Dreboot-path=/usr/bin/reboot \
        -Dnss-elogind=true \
        -Duserdb=false \
        -Dvarlink=true \
        -Defi=false \
        -Dman=disabled \
        -Dhtml=disabled \
        -Dtranslations=false \
        -Dselinux=disabled \
        -Dsmack=false \
        -Dpolkit=disabled \
        -Dacl=enabled \
        -Daudit=disabled \
        -Dpam=enabled \
        -Ddbus=enabled \
        -Dutmp=true \
        -Ddefault-hierarchy=unified
    publish_package "$package"
fi

package="polkit-$POLKIT_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.gz" "$POLKIT_SHA256" \
        "https://github.com/polkit-org/polkit/archive/refs/tags/$POLKIT_VERSION.tar.gz"
    python3 - "$PACKAGE_SOURCE/meson.build" <<'PATCH'
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
    meson_target "$PACKAGE_SOURCE" \
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
    rm -rf \
        "$PACKAGE_STAGING/usr/lib/systemd" \
        "$PACKAGE_STAGING/usr/lib/sysusers.d" \
        "$PACKAGE_STAGING/usr/lib/tmpfiles.d"
    publish_package "$package"
fi

package="upower-$UPOWER_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.gz" "$UPOWER_SHA256" \
        "https://gitlab.freedesktop.org/upower/upower/-/archive/v$UPOWER_VERSION/upower-v$UPOWER_VERSION.tar.gz"
    meson_target "$PACKAGE_SOURCE" \
        -Dman=false \
        -Dgtk-doc=false \
        -Dintrospection=disabled \
        -Didevice=disabled \
        -Dpolkit=enabled \
        -Dinstalled_tests=false \
        -Dudevrulesdir=/usr/lib/udev/rules.d \
        -Dudevhwdbdir=/usr/lib/udev/hwdb.d \
        -Dsystemdsystemunitdir=no
    publish_package "$package"
fi
