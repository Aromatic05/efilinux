#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/004-desktop/config.sh"
source "$ROOT/004-desktop/extras/config.sh"
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
        find "$directory/usr/lib" -type f \
            \( -name '*.a' -o -name '*.la' \) -delete 2>/dev/null || true
        rm -f \
            "$directory/usr/share/glib-2.0/schemas/gschemas.compiled" \
            "$directory/usr/lib/gio/modules/giomodule.cache"
        find "$directory/usr/share/icons" -type f -name icon-theme.cache -delete 2>/dev/null || true
        if [[ "$package" == "libnma-$LIBNMA_VERSION" ]]; then
            rm -f "$directory/usr/share/glib-2.0/schemas/org.gnome.nm-applet.gschema.xml"
        fi
    fi
    printf '%s' "$directory"
}

remove_runtime_owner() {
    local owner=$1
    local path

    [[ -f "$EFILINUX_ROOTFS_OWNERS" ]] || return 0
    while IFS= read -r path; do
        rm -f -- "$EFILINUX_ROOTFS$path"
    done < <(awk -F '\t' -v owner="$owner" '$2 == owner { print $1 }' \
        "$EFILINUX_ROOTFS_OWNERS" | LC_ALL=C sort -r)
    awk -F '\t' -v owner="$owner" '$2 != owner' "$EFILINUX_ROOTFS_OWNERS" \
        > "$EFILINUX_ROOTFS_OWNERS.tmp"
    mv "$EFILINUX_ROOTFS_OWNERS.tmp" "$EFILINUX_ROOTFS_OWNERS"
}

runtime_package_complete() {
    local owner=$1
    local package=$2
    local source_root relative destination

    source_root=$(runtime_stage "$package")
    while IFS= read -r -d '' relative; do
        relative=${relative#"$source_root"}
        destination="$EFILINUX_ROOTFS$relative"
        [[ -e "$destination" || -L "$destination" ]] || return 1
        [[ $(rootfs_owner "$relative") == "$owner" ]] || return 1
    done < <(find "$source_root/usr/bin" "$source_root/usr/lib" \
        "$source_root/usr/libexec" "$source_root/usr/share" "$source_root/etc" \
        -mindepth 1 ! -type d -print0 2>/dev/null)
    return 0
}

install_rootfs_overlay() {
    local package=$1
    local source_root=$2
    local destination_root=$3
    local entry relative relative_path owner

    [[ -d "$source_root" ]] || die "$package overlay tree is missing: $source_root"
    while IFS= read -r -d '' entry; do
        relative=${entry#"$source_root"/}
        relative_path="$destination_root/$relative"
        if [[ -d "$entry" && ! -L "$entry" ]]; then
            mkdir -p "$EFILINUX_ROOTFS$relative_path"
            continue
        fi
        owner=$(rootfs_owner "$relative_path")
        if [[ -e "$EFILINUX_ROOTFS$relative_path" || -L "$EFILINUX_ROOTFS$relative_path" ]]; then
            rm -f -- "$EFILINUX_ROOTFS$relative_path"
            remove_rootfs_owner "$relative_path"
        fi
        install_rootfs_file "$package" "$entry" "$relative_path"
    done < <(find "$source_root" -mindepth 1 -print0)
}

install_runtime_package() {
    local owner=$1
    local package=$2
    local source_root
    local relative

    if runtime_package_complete "$owner" "$package"; then
        log "Keeping complete XFCE runtime package $owner"
        return 0
    fi
    remove_runtime_owner "$owner"

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
    if [[ "$owner" == network-manager-applet ]] && \
       [[ $(rootfs_owner /usr/share/glib-2.0/schemas/org.gnome.nm-applet.gschema.xml) == libnma ]]; then
        rm -f "$EFILINUX_ROOTFS/usr/share/glib-2.0/schemas/org.gnome.nm-applet.gschema.xml"
        remove_rootfs_owner /usr/share/glib-2.0/schemas/org.gnome.nm-applet.gschema.xml
    fi
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
xfce4-terminal xfce4-terminal-$XFCE4_TERMINAL_VERSION
xfce4-notifyd xfce4-notifyd-$XFCE4_NOTIFYD_VERSION
xfce4-power-manager xfce4-power-manager-$XFCE4_POWER_MANAGER_VERSION
xfce4-screensaver xfce4-screensaver-$XFCE4_SCREENSAVER_VERSION
xfce4-whiskermenu-plugin xfce4-whiskermenu-plugin-$XFCE4_WHISKERMENU_VERSION
xfce4-pulseaudio-plugin xfce4-pulseaudio-plugin-$XFCE4_PULSEAUDIO_PLUGIN_VERSION
thunar-volman thunar-volman-$THUNAR_VOLMAN_VERSION
xfce-polkit xfce-polkit-$XFCE_POLKIT_VERSION
libnma libnma-$LIBNMA_VERSION
network-manager-applet network-manager-applet-$NM_APPLET_VERSION
EOF

[[ -f "$EFILINUX_ROOTFS/etc/xdg/menus/xfce-applications.menu" ]] || \
    die "Garcon did not install /etc/xdg/menus/xfce-applications.menu"

log "Installing XFCE session defaults"
rm -f "$EFILINUX_ROOTFS/etc/X11/xinit/xinitrc"
remove_rootfs_owner /etc/X11/xinit/xinitrc
install_rootfs_file \
    desktop-config "$files_root/etc/X11/xinit/xinitrc" \
    /etc/X11/xinit/xinitrc
install_rootfs_overlay \
    desktop-config "$files_root/etc/xdg" /etc/xdg
install_rootfs_overlay \
    desktop-config "$files_root/usr" /usr
chmod 0755 \
    "$EFILINUX_ROOTFS/etc/X11/xinit/xinitrc" \
    "$EFILINUX_ROOTFS/usr/bin/efilinux-volume-control"

log "Seeding CatOS-style defaults for the normal desktop user"
profile_source="$assembly/user-profile"
mkdir -p "$profile_source/.config/xfce4/xfconf/xfce-perchannel-xml"
cp -a \
    "$files_root/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/." \
    "$profile_source/.config/xfce4/xfconf/xfce-perchannel-xml/"
if [[ -d "$files_root/etc/skel" ]]; then
    cp -a "$files_root/etc/skel/." "$profile_source/"
fi
install_rootfs_overlay desktop-config "$profile_source" /etc/skel
install_rootfs_overlay desktop-config "$profile_source" /home/user
mkdir -p \
    "$EFILINUX_ROOTFS/home/user/Desktop" \
    "$EFILINUX_ROOTFS/home/user/.cache"
chown -R 1000:1000 "$EFILINUX_ROOTFS/home/user"
chmod 0750 "$EFILINUX_ROOTFS/home/user"

schema_directory="$EFILINUX_ROOTFS/usr/share/glib-2.0/schemas"
if [[ -d "$schema_directory" ]]; then
    schema_assembly="$assembly/schemas"
    mkdir -p "$schema_assembly"
    find "$schema_directory" -maxdepth 1 -type f -name '*.xml' \
        -exec cp -a -t "$schema_assembly" {} +
    glib-compile-schemas "$schema_assembly"
    rm -f "$EFILINUX_ROOTFS/usr/share/glib-2.0/schemas/gschemas.compiled"
    remove_rootfs_owner /usr/share/glib-2.0/schemas/gschemas.compiled
    install_rootfs_file \
        desktop-config "$schema_assembly/gschemas.compiled" \
        /usr/share/glib-2.0/schemas/gschemas.compiled
fi

locale_directory="$EFILINUX_ROOTFS/usr/share/locale"
if [[ -d "$locale_directory" ]]; then
    while IFS= read -r -d '' locale_path; do
        case $(basename -- "$locale_path") in
            en|en_US|zh_CN|zh_Hans) continue ;;
        esac
        relative_path=${locale_path#"$EFILINUX_ROOTFS"}
        rm -rf -- "$locale_path"
        remove_rootfs_owner_prefix "$relative_path"
    done < <(find "$locale_directory" -mindepth 1 -maxdepth 1 -type d -print0)
fi

gio_module_directory="$EFILINUX_ROOTFS/usr/lib/gio/modules"
if [[ -d "$gio_module_directory" ]]; then
    rm -f "$gio_module_directory/giomodule.cache"
    remove_rootfs_owner /usr/lib/gio/modules/giomodule.cache
    "$EFILINUX_ROOTFS/usr/lib/ld-linux-x86-64.so.2" \
        --library-path "$EFILINUX_ROOTFS/usr/lib" \
        "$EFILINUX_ROOTFS/usr/bin/gio-querymodules" \
        "$gio_module_directory"
    record_rootfs_owner desktop-gio /usr/lib/gio/modules/giomodule.cache
fi

strip_rootfs_elf
log "XFCE desktop rootfs assembly complete"
