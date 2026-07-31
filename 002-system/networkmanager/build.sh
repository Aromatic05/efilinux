#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=networkmanager
pkgver=1.58.0

depends=(dbus elogind ethtool glib glibc iwd libndp polkit readline udev)
builddepends=(linux-headers)
makedepends=(gcc meson ninja pkg-config)

prepare() {
    local archive="$downloaddir/NetworkManager-$pkgver.tar.gz"
    download \
        "https://gitlab.freedesktop.org/NetworkManager/NetworkManager/-/archive/$pkgver/NetworkManager-$pkgver.tar.gz" \
        "$archive"
    checksum sha256 b564614be46fafe6654a497836c48bdbd411ed14d34a525dbf0cd549e33b4cda "$archive"
    extract "$archive" "$srcdir/networkmanager"
    input_file "$recipedir/files/target-dbus-install-dirs.patch" \
        "$srcdir/target-dbus-install-dirs.patch"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/networkmanager" -Np1 -i "$srcdir/target-dbus-install-dirs.patch"
}

build() {
    CC="$CC" \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        meson setup "$builddir" "$srcdir/networkmanager" \
            --prefix=/usr \
            --bindir=/usr/bin \
            --sbindir=/usr/bin \
            --libdir=lib \
            --libexecdir=lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --buildtype=release \
            --wrap-mode=nodownload \
            -Dsystemdsystemunitdir=no \
            -Dsystemdsystemgeneratordir=no \
            -Dudev_dir=/usr/lib/udev \
            -Ddbus_conf_dir=/usr/share/dbus-1/system.d \
            -Druntime_dir=/run \
            -Dmodprobe=/usr/bin/modprobe \
            -Ddist_version="$pkgver-efilinux" \
            -Dsession_tracking_consolekit=false \
            -Dsession_tracking=elogind \
            -Dsuspend_resume=elogind \
            -Dpolkit=true \
            -Dpolkit_noauth_group='' \
            -Dselinux=false \
            -Dsystemd_journal=false \
            -Dconfig_logging_backend_default=syslog \
            -Dconfig_wifi_backend_default=iwd \
            -Dhostname_persist=slackware \
            -Dlibaudit=no \
            -Dwext=false \
            -Dwifi=true \
            -Diwd=true \
            -Dppp=false \
            -Dmodem_manager=false \
            -Dofono=false \
            -Dconcheck=false \
            -Dteamdctl=false \
            -Dovs=false \
            -Dnmcli=true \
            -Dnmtui=false \
            -Dnm_cloud_setup=false \
            -Dbluez5_dun=false \
            -Debpf=false \
            -Dnbft=false \
            -Dclat=false \
            -Dconfig_plugins_default=keyfile \
            -Difcfg_rh=false \
            -Difupdown=false \
            -Dconfig_dns_rc_manager_default=file \
            -Dconfig_dhcp_default=internal \
            -Dintrospection=false \
            -Dvapi=false \
            -Ddocs=false \
            -Dman=false \
            -Dtests=no \
            -Dfirewalld_zone=false \
            -Dmore_asserts=0 \
            -Dmore_logging=false \
            -Dlibpsl=false \
            -Dcrypto=null \
            -Dqt=false \
            -Dreadline=libreadline
    meson compile -C "$builddir" -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" meson install -C "$builddir"
}

check() {
    local install_plan="$recipework/installed.json"

    meson introspect --installed "$builddir" > "$install_plan"
    python3 - "$install_plan" "$EFILINUX_SYSROOT" "$EFILINUX_BUILD" <<'PY'
import json
import sys

plan_path, sysroot, build_root = sys.argv[1:]
plan = json.load(open(plan_path, encoding="utf-8"))
leaks = sorted({
    destination
    for destination in plan.values()
    if sysroot in destination or build_root in destination
})
if leaks:
    for destination in leaks:
        print(destination, file=sys.stderr)
    raise SystemExit("NetworkManager install plan contains build-host paths")
PY
}

devel() {
    find "$develdir" -type f -name '*.la' -delete
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=(
        /etc/NetworkManager/
        /usr/bin/NetworkManager
        /usr/bin/nmcli
        /usr/bin/nm-online
        /usr/lib/nm-daemon-helper
        /usr/lib/nm-dhcp-helper
        /usr/lib/nm-dispatcher
        /usr/lib/nm-libnm-helper
        /usr/lib/nm-priv-helper
        /usr/lib/NetworkManager/
        /usr/lib/udev/rules.d/
        /usr/share/dbus-1/system.d/
        /usr/share/dbus-1/system-services/
        /usr/share/polkit-1/
    )
    package_add_library_family keep 'libnm.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
