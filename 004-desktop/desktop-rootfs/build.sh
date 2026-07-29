#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/004-desktop/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command find glib-compile-schemas readelf sha256sum strip tar
ensure_directories

files_root="$ROOT/004-desktop/desktop-rootfs/files"
assembly="$EFILINUX_BUILD/assembly/desktop-rootfs"
reset_directory "$assembly"
package_materialization="$assembly/packages"
runtime_materialization="$assembly/runtime"
mkdir -p "$package_materialization" "$runtime_materialization"

stage() {
    local package=$1
    local directory="$package_materialization/$package"
    if [[ ! -d "$directory" ]]; then
        binary_package_materialize "$package" "$directory"
    fi
    printf '%s' "$directory"
}

runtime_stage() {
    local package=$1
    local directory="$runtime_materialization/$package"
    if [[ ! -d "$directory" ]]; then
        cp -a "$(stage "$package")" "$directory"
        rm -rf \
            "$directory/usr/include" \
            "$directory/usr/lib/pkgconfig" \
            "$directory/usr/lib/cmake" \
            "$directory/usr/share/aclocal" \
            "$directory/usr/share/doc" \
            "$directory/usr/share/gtk-doc" \
            "$directory/usr/share/man"
        find "$directory/usr/lib" -maxdepth 1 \
            \( -name '*.a' -o -name '*.la' \) -delete 2>/dev/null || true
    fi
    printf '%s' "$directory"
}

install_runtime_package() {
    local owner=$1
    local package=$2
    local source_root
    local relative

    source_root=$(runtime_stage "$package")
    [[ ! -d "$source_root/usr/etc" ]] || \
        die "$package was built with the invalid /usr/etc sysconfdir"
    for relative in usr/bin usr/lib usr/libexec usr/share etc; do
        [[ -d "$source_root/$relative" ]] || continue
        install_rootfs_tree "$owner" "$source_root/$relative" "/$relative"
    done
}

log "Installing XFCE 4.18 runtime packages"
while read -r owner package; do
    [[ -n "$owner" ]] || continue
    install_runtime_package "$owner" "$package"
done <<EOF
libxfce4util libxfce4util-$LIBXFCE4UTIL_VERSION
xfconf xfconf-$XFCONF_VERSION
libxfce4ui libxfce4ui-$LIBXFCE4UI_VERSION
exo exo-$EXO_VERSION
garcon garcon-$GARCON_VERSION
thunar thunar-$THUNAR_VERSION
tumbler tumbler-$TUMBLER_VERSION
xfce4-appfinder xfce4-appfinder-$XFCE4_APPFINDER_VERSION
xfce4-panel xfce4-panel-$XFCE4_PANEL_VERSION
xfce4-session xfce4-session-$XFCE4_SESSION_VERSION
xfce4-settings xfce4-settings-$XFCE4_SETTINGS_VERSION
xfdesktop xfdesktop-$XFDESKTOP_VERSION
xfwm4 xfwm4-$XFWM4_VERSION
EOF

[[ -f "$EFILINUX_ROOTFS/etc/xdg/menus/xfce-applications.menu" ]] || \
    die "Garcon did not install /etc/xdg/menus/xfce-applications.menu"

log "Installing XFCE session defaults"
replace_rootfs_file \
    desktop-config graphical-config \
    "$files_root/etc/X11/xinit/xinitrc" \
    /etc/X11/xinit/xinitrc
install_rootfs_tree \
    desktop-config "$files_root/etc/xdg" /etc/xdg
chmod 0755 "$EFILINUX_ROOTFS/etc/X11/xinit/xinitrc"
mkdir -p \
    "$EFILINUX_ROOTFS/root/Desktop" \
    "$EFILINUX_ROOTFS/root/.cache" \
    "$EFILINUX_ROOTFS/root/.config"

log "Seeding the root XFCE profile from CatOS-style user defaults"
install_rootfs_tree \
    desktop-config \
    "$files_root/etc/xdg/xfce4/xfconf/xfce-perchannel-xml" \
    /root/.config/xfce4/xfconf/xfce-perchannel-xml

schema_directory="$EFILINUX_ROOTFS/usr/share/glib-2.0/schemas"
if [[ -d "$schema_directory" ]]; then
    schema_assembly="$assembly/schemas"
    mkdir -p "$schema_assembly"
    find "$schema_directory" -maxdepth 1 -type f -name '*.xml' \
        -exec cp -a -t "$schema_assembly" {} +
    glib-compile-schemas "$schema_assembly"
    replace_rootfs_file \
        desktop-config gtk3 \
        "$schema_assembly/gschemas.compiled" \
        /usr/share/glib-2.0/schemas/gschemas.compiled
fi

strip_rootfs_elf
log "XFCE desktop rootfs assembly complete"
