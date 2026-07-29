#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/001-runtime/config.sh"
source "$ROOT/001-runtime/desktop-libraries/config.sh"
source "$ROOT/002-system/desktop-services/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command curl gcc make meson ninja pkg-config sha256sum tar
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
    find "$PACKAGE_STAGING" -type f -name '*.la' -delete 2>/dev/null || true
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

normalize_staged_sysroot_prefix() {
    local leaked_root="$PACKAGE_STAGING$EFILINUX_SYSROOT"

    if [[ -d "$leaked_root" ]]; then
        cp -a "$leaked_root/." "$PACKAGE_STAGING/"
        rm -rf "$PACKAGE_STAGING/home"
    fi

    if find "$PACKAGE_STAGING" -path "*$EFILINUX_SYSROOT*" -print -quit | grep -q .; then
        die "package contains an installation path prefixed by the target sysroot"
    fi
}

package="iwd-$IWD_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.xz" "$IWD_SHA256" \
        "https://mirrors.edge.kernel.org/pub/linux/network/wireless/$package.tar.xz"
    mkdir -p "$PACKAGE_BUILD/pkgconfig"
    cat > "$PACKAGE_BUILD/pkgconfig/tinfo.pc" <<'PC'
prefix=/usr
libdir=${prefix}/lib
Name: tinfo
Description: ncurses wide-character terminfo compatibility
Version: 6.6
Libs: -L${libdir} -lncursesw
PC
    (
        cd "$PACKAGE_BUILD"
        CC=gcc \
        CFLAGS="$(target_cflags)" \
        CPPFLAGS="--sysroot=$EFILINUX_SYSROOT" \
        LDFLAGS="$(target_ldflags)" \
        PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
        PKG_CONFIG_LIBDIR="$PACKAGE_BUILD/pkgconfig:$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        "$PACKAGE_SOURCE/configure" \
                --prefix=/usr \
                --libdir=/usr/lib \
                --libexecdir=/usr/lib \
                --sysconfdir=/etc \
                --localstatedir=/var \
                --enable-daemon \
                --enable-client \
                --disable-monitor \
                --enable-dbus-policy \
                --with-dbus-datadir=/usr/share \
                --disable-systemd-service \
                --disable-manual-pages \
                --enable-external-ell \
                --disable-libedit \
                --disable-wired \
                --disable-hwsim \
                --disable-tools \
                --disable-ofono
    )
    make -C "$PACKAGE_BUILD" -j "$EFILINUX_JOBS"
    make -C "$PACKAGE_BUILD" DESTDIR="$PACKAGE_STAGING" install
    publish_package "$package"
fi

package="NetworkManager-$NETWORKMANAGER_VERSION"
if ! restore_package "$package"; then
    prepare_tar_package "$package" "$package.tar.gz" "$NETWORKMANAGER_SHA256" \
        "https://gitlab.freedesktop.org/NetworkManager/NetworkManager/-/archive/$NETWORKMANAGER_VERSION/$package.tar.gz"
    CC=gcc \
    CFLAGS="$(target_cflags)" \
    LDFLAGS="$(target_ldflags)" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    meson setup "$PACKAGE_BUILD" "$PACKAGE_SOURCE" \
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
            -Ddist_version="$NETWORKMANAGER_VERSION-efilinux" \
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
    meson compile -C "$PACKAGE_BUILD" -j "$EFILINUX_JOBS"
    DESTDIR="$PACKAGE_STAGING" \
        meson install -C "$PACKAGE_BUILD"
    normalize_staged_sysroot_prefix
    [[ -x "$PACKAGE_STAGING/usr/bin/NetworkManager" ]] || \
        die "NetworkManager was not installed into /usr/bin"
    publish_package "$package"
fi
