#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=networkmanager-nmtui
pkgver=1.58.0
depends=(
    dbus elogind ethtool glib glibc iwd libndp networkmanager newt polkit readline
    slang udev
)
builddepends=(linux-headers)
makedepends=(gcc meson ninja patch pkg-config)
prepare() {
    local archive="$downloaddir/NetworkManager-$pkgver.tar.gz"
    download \
        "https://gitlab.freedesktop.org/NetworkManager/NetworkManager/-/archive/$pkgver/NetworkManager-$pkgver.tar.gz" \
        "$archive"
    checksum sha256 b564614be46fafe6654a497836c48bdbd411ed14d34a525dbf0cd549e33b4cda "$archive"
    extract "$archive" "$srcdir/networkmanager"
    input_shared_file \
        "$ROOT/002-system/networkmanager/files/target-dbus-install-dirs.patch" \
        "$srcdir/target-dbus-install-dirs.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/networkmanager" -Np1 -i "$srcdir/target-dbus-install-dirs.patch"
}
build() {
    CC="$(target_compiler_wrapper gcc)" \
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
            -Dnmcli=false \
            -Dnmtui=true \
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
    meson compile -C "$builddir" -j"$EFILINUX_JOBS"
    DESTDIR="$develdir" meson install -C "$builddir"
    prune_translations "$develdir"
}
check() { [[ -x "$develdir/usr/bin/nmtui" ]] || die "nmtui binary is missing"; }
devel() { strip_all "$develdir/usr/bin/nmtui"; }
package() {
    package_keep \
        /usr/bin/nmtui \
        /usr/bin/nmtui-connect \
        /usr/bin/nmtui-edit \
        /usr/bin/nmtui-hostname \
        /usr/share/locale/zh_CN/LC_MESSAGES/NetworkManager.mo
}
recipe_main "$@"
