#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=xfce
pkgver=4.18

depends=(
    at-spi2-core dbus dbus-glib elogind exfatprogs gdk-pixbuf glib glibc gtk3
    iso-codes libexif libgudev libinput libnotify libwnck libxklavier linux-pam
    networkmanager pango pcre2 polkit pulseaudio sqlite startup-notification upower
    util-linux vte xorg xorg-server
)
builddepends=()
makedepends=(
    autoreconf cmake gcc g++ intltool-extract intltool-merge intltool-update
    make meson ninja pkg-config python3
)

xfce_input() {
    local name=$1 version=$2 checksum_value=$3 url=$4
    local archive="$downloaddir/$name-$version.source"
    download "$url" "$archive"
    checksum sha256 "$checksum_value" "$archive"
    extract "$archive" "$srcdir/$name"
}

prepare() {

    xfce_input 'libxfce4util' '4.18.2' 'd9a329182b78f7e2520cd4aafcbb276bbbf162f6a89191676539ad2e3889c353' 'https://archive.xfce.org/src/xfce/libxfce4util/4.18/libxfce4util-4.18.2.tar.bz2'
    xfce_input 'xfconf' '4.18.3' 'c56cc69056f6947b2c60b165ec1e4c2b0acf26a778da5f86c89ffce24d5ebd98' 'https://archive.xfce.org/src/xfce/xfconf/4.18/xfconf-4.18.3.tar.bz2'
    xfce_input 'libxfce4ui' '4.18.6' '77dd99206cc8c6c7f69c269c83c7ee6a037bca9d4a89b1a6d9765e5a09ce30cd' 'https://archive.xfce.org/src/xfce/libxfce4ui/4.18/libxfce4ui-4.18.6.tar.bz2'
    xfce_input 'exo' '4.18.0' '4f2c61d045a888cdb64297fd0ae20cc23da9b97ffb82562ed12806ed21da7d55' 'https://archive.xfce.org/src/xfce/exo/4.18/exo-4.18.0.tar.bz2'
    xfce_input 'garcon' '4.18.2' '1b8c9292e131968fbfc8987bbc62c5ba47186dd45ef4e47c5d8c5088bb2d434d' 'https://archive.xfce.org/src/xfce/garcon/4.18/garcon-4.18.2.tar.bz2'
    xfce_input 'thunar' '4.18.11' '7d0bdae2076a568c137d403ab5600e06a7a4f7a02514d486da7b8414aa75d612' 'https://archive.xfce.org/src/xfce/thunar/4.18/thunar-4.18.11.tar.bz2'
    xfce_input 'tumbler' '4.18.2' 'b530eec635eac7f898c0d8d3a3ff79d76a145d3bed3e786d54b1ec058132be7a' 'https://archive.xfce.org/src/xfce/tumbler/4.18/tumbler-4.18.2.tar.bz2'
    xfce_input 'xfce4-appfinder' '4.18.1' '9854ea653981be544ad545850477716c4c92d0c43eb47b75f78534837c0893f9' 'https://archive.xfce.org/src/xfce/xfce4-appfinder/4.18/xfce4-appfinder-4.18.1.tar.bz2'
    xfce_input 'xfce4-panel' '4.18.6' '21337161f58bb9b6e42760cb6883bc79beea27882aa6272b61f0e09d750d7c62' 'https://archive.xfce.org/src/xfce/xfce4-panel/4.18/xfce4-panel-4.18.6.tar.bz2'
    xfce_input 'xfce4-session' '4.18.4' '9a9c5074c7338b881a5259d3b643619bf84901360c03478e1a697938ece06516' 'https://archive.xfce.org/src/xfce/xfce4-session/4.18/xfce4-session-4.18.4.tar.bz2'
    xfce_input 'xfce4-settings' '4.18.6' 'd9a9051b6026edd6766c64bb403b51e9167e4d31e7f1c7f843d3aed19f667bfe' 'https://archive.xfce.org/src/xfce/xfce4-settings/4.18/xfce4-settings-4.18.6.tar.bz2'
    xfce_input 'xfdesktop' '4.18.1' 'ef9268190c25877e22a9ff5aa31cc8ede120239cb0dfca080c174e7eed4ff756' 'https://archive.xfce.org/src/xfce/xfdesktop/4.18/xfdesktop-4.18.1.tar.bz2'
    xfce_input 'xfwm4' '4.18.0' '92cd1b889bb25cb4bc06c1c6736c238d96e79c1e706b9f77fad0a89d6e5fc13f' 'https://archive.xfce.org/src/xfce/xfwm4/4.18/xfwm4-4.18.0.tar.bz2'
    xfce_input 'xfce4-terminal' '1.1.5' '3c5b1d3a01a9a113852ac0f77d1c85bf3a356b43de33ec805b21ceca7d6f0a63' 'https://archive.xfce.org/src/apps/xfce4-terminal/1.1/xfce4-terminal-1.1.5.tar.xz'
    xfce_input 'xfce4-notifyd' '0.8.2' 'e3a28adb08daa1411135142a0d421e4d6050c4035a4e513a673a59460ff2ae84' 'https://archive.xfce.org/src/apps/xfce4-notifyd/0.8/xfce4-notifyd-0.8.2.tar.bz2'
    xfce_input 'xfce4-power-manager' '4.18.4' '76918f7bdcd936dbbf20efd9221a33be0cd504c7d7ffce792bace3c720f3d874' 'https://archive.xfce.org/src/xfce/xfce4-power-manager/4.18/xfce4-power-manager-4.18.4.tar.bz2'
    xfce_input 'xfce4-screensaver' '4.18.4' 'cf717d032d2d0555978c479299da992af6dc3363ae7e758af9515c7166eac170' 'https://archive.xfce.org/src/apps/xfce4-screensaver/4.18/xfce4-screensaver-4.18.4.tar.bz2'
    xfce_input 'xfce4-pulseaudio-plugin' '0.4.9' 'a0807615fb2848d0361b7e4568a44f26d189fda48011c7ba074986c8bfddc99a' 'https://archive.xfce.org/src/panel-plugins/xfce4-pulseaudio-plugin/0.4/xfce4-pulseaudio-plugin-0.4.9.tar.bz2'
    xfce_input 'thunar-volman' '4.18.0' '93b75c7ffbe246a21f4190295acc148e184be8df397e431b258d0d676e87fc65' 'https://archive.xfce.org/src/xfce/thunar-volman/4.18/thunar-volman-4.18.0.tar.bz2'
    xfce_input 'xfce4-whiskermenu-plugin' '2.8.4' 'ed918950e01dc97fe831e01c698b44247f1537992999b1262ab61c799272b3b7' 'https://archive.xfce.org/src/panel-plugins/xfce4-whiskermenu-plugin/2.8/xfce4-whiskermenu-plugin-2.8.4.tar.bz2'
    xfce_input 'xfce-polkit' '0.3.0' 'a26f1ad54d310246e63ed5d0deffdcea36abe49cc8603470e401d46084f093ce' 'https://github.com/ncopa/xfce-polkit/archive/b8aa9564db5267bbe161bac3a3df52c1c53231d6.tar.gz'
    input_file "$recipedir/files/xfce4-settings-logical-scale.patch" \
        "$srcdir/xfce4-settings-logical-scale.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/xfce4-settings" -Np1 \
        -i "$srcdir/xfce4-settings-logical-scale.patch"
}


xfce_merge_stage() {
    local stage=$1
    cp -a --reflink=auto "$stage/." "$develdir/"
    cp -a --reflink=auto "$stage/." "$EFILINUX_SYSROOT/"
}

xfce_build_release() {
    local name=$1
    shift
    local component_build="$builddir/components/$name"
    local component_stage="$builddir/stages/$name"
    reset_directory "$component_build"
    reset_directory "$component_stage"
    target_release_configure "$srcdir/$name" "$component_build"         --disable-static         --disable-silent-rules         --sysconfdir=/etc         "$@"
    target_make_install "$component_build" "$component_stage"
    prune_translations "$component_stage"
    xfce_merge_stage "$component_stage"
}

xfce_build_meson() {
    local name=$1
    shift
    local component_build="$builddir/components/$name"
    local component_stage="$builddir/stages/$name"
    reset_directory "$component_build"
    reset_directory "$component_stage"
    target_meson_setup "$srcdir/$name" "$component_build" "$@"
    target_meson_install "$component_build" "$component_stage"
    prune_translations "$component_stage"
    xfce_merge_stage "$component_stage"
}

xfce_build_cmake() {
    local name=$1
    shift
    local component_build="$builddir/components/$name"
    local component_stage="$builddir/stages/$name"
    reset_directory "$component_build"
    reset_directory "$component_stage"
    target_cmake_setup "$srcdir/$name" "$component_build" "$@"
    target_cmake_install "$component_build" "$component_stage"
    prune_translations "$component_stage"
    xfce_merge_stage "$component_stage"
}

build() {
    local original_sysroot=$EFILINUX_SYSROOT
    local internal_sysroot="$builddir/sysroot"
    reset_directory "$internal_sysroot"
    cp -a --reflink=auto "$original_sysroot/." "$internal_sysroot/"
    target_rebind_sysroot "$internal_sysroot"
    export ICEAUTH=/usr/bin/iceauth
    mkdir -p "$develdir"

    local screensaver_configure
    for screensaver_configure in configure.ac configure; do
        sed -i \
            "s|^DBUS_SESSION_SERVICE_DIR=.*|DBUS_SESSION_SERVICE_DIR='\${datarootdir}/dbus-1/services'|" \
            "$srcdir/xfce4-screensaver/$screensaver_configure"
        grep -Fqx \
            "DBUS_SESSION_SERVICE_DIR='\${datarootdir}/dbus-1/services'" \
            "$srcdir/xfce4-screensaver/$screensaver_configure" || \
            die "failed to normalize the XFCE screensaver D-Bus service directory in $screensaver_configure"
    done

    xfce_build_release 'libxfce4util' '--disable-gtk-doc' '--disable-introspection' '--disable-debug'
    xfce_build_release 'xfconf' '--disable-gtk-doc' '--disable-introspection' '--disable-debug'
    xfce_build_release 'libxfce4ui' '--enable-gudev' '--enable-startup-notification' '--disable-introspection' '--disable-gtk-doc' '--disable-debug'
    xfce_build_release 'exo' '--enable-gio-unix' '--disable-gtk-doc' '--disable-debug'
    xfce_build_release 'garcon' '--disable-introspection' '--disable-gtk-doc' '--disable-debug'
    xfce_build_release 'thunar' '--disable-introspection' '--disable-gtk-doc' '--enable-gio-unix' '--enable-gudev' '--enable-notifications' '--enable-exif' '--enable-pcre2' '--disable-debug'
    xfce_build_release 'tumbler' '--disable-gtk-doc' '--disable-cover-thumbnailer' '--disable-ffmpeg-thumbnailer' '--disable-gstreamer-thumbnailer' '--disable-odf-thumbnailer' '--disable-poppler-thumbnailer' '--disable-raw-thumbnailer' '--disable-gepub-thumbnailer' '--disable-debug'
    xfce_build_release 'xfce4-appfinder' '--disable-debug'
    xfce_build_release 'xfce4-panel' '--disable-dbusmenu-gtk3' '--enable-gio-unix' '--disable-introspection' '--disable-vala' '--disable-gtk-doc' '--disable-debug'
    xfce_build_release 'xfce4-session' '--enable-polkit' '--disable-debug'
    xfce_build_release 'xfce4-settings' '--enable-xrandr' '--enable-upower-glib' '--enable-libnotify' '--disable-colord' '--enable-gio-unix' '--enable-libxklavier' '--disable-sound-settings' '--disable-debug'
    xfce_build_release 'xfdesktop' '--enable-thunarx' '--enable-notifications' '--disable-debug'
    xfce_build_release 'xfwm4' '--enable-startup-notification' '--enable-xpresent' '--enable-compositor' '--disable-debug'
    xfce_build_meson 'xfce4-terminal' '--sysconfdir=../etc' '-Dx11=enabled' '-Dwayland=disabled' '-Dgtk-layer-shell=disabled' '-Dlibutempter=disabled'
    xfce_build_release 'xfce4-notifyd' '--enable-gdk-x11' '--disable-gdk-wayland' '--disable-gtk-layer-shell' '--disable-sound' '--disable-canberra' '--disable-dbus-start-daemon' '--disable-debug'
    xfce_build_release 'xfce4-power-manager' '--enable-polkit' '--enable-network-manager' '--enable-panel-plugins' '--with-backend=linux' '--disable-debug'
    xfce_build_release 'xfce4-screensaver' '--enable-locking' '--enable-pam' '--with-pam-prefix=/etc' '--with-pam-auth-type=system-auth' '--without-console-kit' '--without-systemd' '--with-elogind' '--without-kbd-layout-indicator' '--without-xscreensaverdir' '--without-xscreensaverhackdir' '--without-libgl' '--disable-docbook-docs'
    xfce_build_release 'xfce4-pulseaudio-plugin' '--disable-keybinder' '--enable-libnotify' '--disable-libcanberra' '--disable-mpris2' '--disable-libxfce4windowing' '--enable-wnck' '--with-mixer-command=/usr/bin/efilinux-volume-control' '--disable-debug'
    xfce_build_release 'thunar-volman' '--enable-notifications' '--disable-debug'
    xfce_build_cmake 'xfce4-whiskermenu-plugin' '-DENABLE_ACCOUNTS_SERVICE=OFF' '-DENABLE_GTK_LAYER_SHELL=OFF' '-DENABLE_STRIP=OFF' '-DENABLE_DEVELOPER_MODE=OFF'
    sed -i "s/sysconfdir = join_paths(prefix, get_option('sysconfdir'))/sysconfdir = get_option('sysconfdir')/" "$srcdir/xfce-polkit/meson.build"
    xfce_build_meson 'xfce-polkit' '--sysconfdir=/etc' '--libexecdir=lib/xfce-polkit'

    unset ICEAUTH
    target_rebind_sysroot "$original_sysroot"
}

devel() {
    local source target

    if [[ -d "$develdir/usr/sbin" ]]; then
        install -d -m0755 "$develdir/usr/bin"
        while IFS= read -r -d '' source; do
            target="$develdir/usr/bin/$(basename -- "$source")"
            [[ ! -e $target && ! -L $target ]] || \
                die "XFCE merged-/usr path already exists: ${target#"$develdir"}"
            mv -- "$source" "$target"
        done < <(find "$develdir/usr/sbin" -mindepth 1 -maxdepth 1 -print0)
        rmdir "$develdir/usr/sbin"
    fi

    find "$develdir" -type f -name '*.la' -delete 2>/dev/null || true
    strip_all "$develdir/usr/bin" "$develdir/usr/lib" "$develdir/usr/libexec"
}

package() {
    rm -rf \
        "$pkgdir/usr/include" \
        "$pkgdir/usr/lib/pkgconfig" \
        "$pkgdir/usr/lib/cmake" \
        "$pkgdir/usr/share/aclocal" \
        "$pkgdir/usr/share/doc" \
        "$pkgdir/usr/share/gtk-doc" \
        "$pkgdir/usr/share/man" \
        "$pkgdir/usr/share/metainfo"
    find "$pkgdir/usr/lib" -type f \
        \( -name '*.a' -o -name '*.la' -o -name '*.pc' \) \
        -delete 2>/dev/null || true
    find "$pkgdir/usr/lib" -maxdepth 1 -type l -name 'lib*.so' -delete
    rm -f \
        "$pkgdir/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml" \
        "$pkgdir/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml" \
        "$pkgdir/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" \
        "$pkgdir/etc/xdg/xfce4/xinitrc" \
        "$pkgdir/etc/xdg/autostart/xscreensaver.desktop" \
        "$pkgdir/usr/bin/xfce4-screensaver-configure.py" \
        "$pkgdir/usr/lib/xfce4/xfce4-compose-mail"
    if [[ -d "$pkgdir/usr/share/xfce4/helpers" ]]; then
        while IFS= read -r -d '' helper; do
            if grep -Fq '/usr/lib/xfce4/xfce4-compose-mail' "$helper"; then
                rm -f "$helper"
            fi
        done < <(find "$pkgdir/usr/share/xfce4/helpers" -type f -name '*.desktop' -print0)
    fi
    return 0
}

recipe_main "$@"
