#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/004-desktop/config.sh"
source "$ROOT/004-desktop/extras/config.sh"
source "$ROOT/lib/common.sh"

ensure_directories
rootfs="$EFILINUX_ROOTFS"

require_program() {
    local program=$1
    local path="$rootfs/usr/bin/$program"
    [[ -x "$path" ]] || die "desktop program is missing: $program"
    [[ ! -L "$path" || $(readlink -- "$path") != busybox ]] || \
        die "desktop program unexpectedly resolves to BusyBox: $program"
}

for program in \
    startxfce4 xfce4-session xfwm4 xfce4-panel xfdesktop \
    xfconf-query thunar xfce4-appfinder xfce4-settings-manager \
    xfce4-terminal xfce4-notifyd-config \
    xfce4-power-manager xfce4-power-manager-settings \
    xfce4-screensaver xfce4-screensaver-command \
    xfce4-popup-whiskermenu thunar-volman nm-applet nm-connection-editor \
    efilinux-volume-control; do
    require_program "$program"
done

[[ -x "$rootfs/usr/lib/xfce4/notifyd/xfce4-notifyd" ]] || \
    die "XFCE notification daemon is missing"
[[ -f "$rootfs/etc/xdg/autostart/xfce4-notifyd.desktop" ]] || \
    die "XFCE notification daemon autostart entry is missing"
[[ -x "$rootfs/usr/lib/xfce4/xfconf/xfconfd" ]] || \
    die "xfconfd is missing from the desktop runtime"
[[ -f "$rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" ]] || \
    die "XFCE xsettings defaults are missing"
[[ -f "$rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml" ]] || \
    die "XFCE panel defaults are missing"
[[ -f "$rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/keyboards.xml" ]] || \
    die "XFCE keyboard defaults are missing"
[[ -f "$rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/thunar.xml" ]] || \
    die "Thunar defaults are missing"
grep -Fq '<property name="Numlock" type="bool" value="false"/>' \
    "$rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/keyboards.xml" || \
    die "XFCE keyboard defaults do not preserve the CatOS NumLock policy"
grep -Fq '<property name="misc-folders-first" type="bool" value="true"/>' \
    "$rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/thunar.xml" || \
    die "Thunar defaults do not keep folders first"
[[ -f "$rootfs/etc/xdg/menus/xfce-applications.menu" ]] || \
    die "XFCE applications menu is missing"
grep -Fq '<Name>Xfce</Name>' \
    "$rootfs/etc/xdg/menus/xfce-applications.menu" || \
    die "XFCE applications menu does not define the Xfce root menu"
grep -Fq '<DefaultAppDirs/>' \
    "$rootfs/etc/xdg/menus/xfce-applications.menu" || \
    die "XFCE applications menu does not scan standard desktop entries"
[[ -f "$rootfs/etc/xdg/xfce4/xinitrc" ]] || \
    die "XFCE system xinitrc is missing from /etc/xdg"
[[ ! -e "$rootfs/usr/etc" ]] || \
    die "desktop configuration leaked into /usr/etc"
grep -Fq '/etc/xdg/xfce4/xinitrc' "$rootfs/usr/bin/startxfce4" || \
    die "startxfce4 does not use the system /etc/xdg xinitrc"
if grep -Fq '/usr/etc/xdg' "$rootfs/usr/bin/startxfce4"; then
    die "startxfce4 still contains the invalid /usr/etc/xdg path"
fi

grep -Fq '<property name="ThemeName" type="string" value="Qogir"/>' \
    "$rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" || \
    die "XFCE does not select the Qogir GTK theme"
grep -Fq '<property name="IconThemeName" type="string" value="Qogir"/>' \
    "$rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" || \
    die "XFCE does not select the Qogir icon theme"
grep -Fq '<property name="CursorThemeName" type="string" value="Qogir"/>' \
    "$rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" || \
    die "XFCE does not select the Qogir cursor theme"
grep -Fq '<property name="theme" type="string" value="Qogir"/>' \
    "$rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml" || \
    die "XFWM does not select the Qogir window theme"

skel_xfconf="$rootfs/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml"
user_xfconf="$rootfs/home/user/.config/xfce4/xfconf/xfce-perchannel-xml"
for channel in \
    xsettings xfwm4 xfce4-panel xfce4-session keyboards thunar \
    xfce4-notifyd xfce4-power-manager xfce4-screensaver \
    xfce4-terminal xfce4-keyboard-shortcuts; do
    [[ -f "$skel_xfconf/$channel.xml" ]] || \
        die "skel XFCE profile is missing channel defaults: $channel"
    [[ -f "$user_xfconf/$channel.xml" ]] || \
        die "user XFCE profile is missing channel defaults: $channel"
    cmp -s "$skel_xfconf/$channel.xml" "$user_xfconf/$channel.xml" || \
        die "user XFCE channel differs from skel default: $channel"
done
cmp -s \
    "$rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" \
    "$user_xfconf/xsettings.xml" || \
    die "user XFCE profile does not preserve the system Qogir xsettings"
cmp -s \
    "$rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml" \
    "$user_xfconf/xfwm4.xml" || \
    die "user XFCE profile does not preserve the system Qogir XFWM settings"
[[ ! -d "$rootfs/root/.config/xfce4" ]] || \
    die "root desktop profile must not be seeded"
[[ $(stat -c '%u:%g' "$rootfs/home/user") == 1000:1000 ]] || \
    die "desktop user home ownership is incorrect"

for autostart in \
    xfce-polkit.desktop efilinux-nm-applet.desktop; do
    [[ -f "$rootfs/etc/xdg/autostart/$autostart" ]] || \
        die "desktop autostart entry is missing: $autostart"
done
[[ -x "$rootfs/usr/lib/xfce-polkit/xfce-polkit" ]] || \
    die "XFCE PolicyKit authentication agent is missing"
[[ -f "$rootfs/etc/skel/.config/xfce4/panel/whiskermenu-1.rc" ]] || \
    die "Whisker menu user defaults are missing"
[[ -f "$rootfs/home/user/.config/xfce4/panel/whiskermenu-1.rc" ]] || \
    die "Whisker menu defaults were not seeded for user"

panel_defaults="$rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
for plugin in whiskermenu pulseaudio power-manager-plugin notification-plugin; do
    grep -Fq "value=\"$plugin\"" "$panel_defaults" || \
        die "required XFCE panel plugin is absent from defaults: $plugin"
done
grep -Fq '<property name="theme" type="string" value="Qogir"/>' \
    "$rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-notifyd.xml" || \
    die "XFCE notifications do not use the Qogir theme"

for plugin_library in \
    libwhiskermenu.so libpulseaudio-plugin.so \
    libxfce4powermanager.so libnotification-plugin.so; do
    if ! find "$rootfs/usr/lib" -type f -name "$plugin_library" -print -quit | grep -q .; then
        die "XFCE panel plugin library is missing: $plugin_library"
    fi
done

for required_theme_path in \
    gtk-3.0/gtk.css xfwm4/themerc xfce-notify-4.0/gtk.css; do
    [[ -f "$rootfs/usr/share/themes/Qogir/$required_theme_path" ]] || \
        die "Qogir desktop theme file is missing: $required_theme_path"
done
for excluded_theme_path in \
    cinnamon gnome-shell gtk-2.0 gtk-4.0 labwc metacity-1 plank unity; do
    [[ ! -e "$rootfs/usr/share/themes/Qogir/$excluded_theme_path" ]] || \
        die "excluded Qogir desktop subtree remains: $excluded_theme_path"
done
grep -Fq '/usr/bin/startxfce4' "$rootfs/etc/X11/xinit/xinitrc" || \
    die "graphical session does not launch XFCE"
if grep -Fq gtk3-demo "$rootfs/etc/X11/xinit/xinitrc"; then
    die "graphical session still launches the GTK demonstration program"
fi

if [[ -d "$rootfs/usr/share/locale" ]]; then
    while IFS= read -r locale_name; do
        case "$locale_name" in
            en|en_US|zh_CN|zh_Hans) ;;
            *) die "unsupported desktop translation remains: $locale_name" ;;
        esac
    done < <(
        find "$rootfs/usr/share/locale" -mindepth 1 -maxdepth 1 \
            -type d -printf '%f\n' | sort
    )
fi

for library in \
    libxfce4util.so.7 libxfconf-0.so.3 libxfce4ui-2.so.0 \
    libexo-2.so.0 libgarcon-1.so.0 libthunarx-3.so.0; do
    [[ -e "$rootfs/usr/lib/$library" ]] || \
        die "XFCE shared library is missing: $library"
done

log "004-desktop XFCE programs, configuration, translations, and libraries passed"
