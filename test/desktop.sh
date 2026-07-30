#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

ensure_directories
rootfs="$EFILINUX_ROOTFS"

[[ -f "$EFILINUX_ROOTFS_FAKEROOT_STATE" ]] || \
    die "rootfs fakeroot metadata is missing"

rootfs_stat() {
    fakeroot -i "$EFILINUX_ROOTFS_FAKEROOT_STATE" -- \
        stat -c "$1" "$rootfs$2"
}

top_level_build="$ROOT/build.sh"
graphical_stage_line=$(grep -nF 'run_component "$ROOT/003-graphical"' \
    "$top_level_build" | cut -d: -f1 || true)
desktop_stage_line=$(grep -nF 'run_component "$ROOT/004-desktop"' \
    "$top_level_build" | cut -d: -f1 || true)
kernel_stage_line=$(grep -nF 'run_component "$ROOT/000-kernel"' \
    "$top_level_build" | cut -d: -f1 || true)
[[ -n "$graphical_stage_line" && -n "$desktop_stage_line" && -n "$kernel_stage_line" ]] || \
    die "top-level build does not include the complete desktop image pipeline"
((graphical_stage_line < desktop_stage_line && desktop_stage_line < kernel_stage_line)) || \
    die "top-level build does not assemble the desktop before the final kernel image"

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

session_config="$rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml"
grep -Fq '<property name="FailsafeSessionName" type="string" value="Failsafe"/>' \
    "$session_config" || \
    die "XFCE failsafe session name is missing"
grep -Fq '<property name="IsFailsafe" type="bool" value="true"/>' \
    "$session_config" || \
    die "XFCE failsafe session definition is missing"
for failsafe_program in xfwm4 xfsettingsd xfce4-panel Thunar xfdesktop; do
    grep -Fq "value=\"$failsafe_program\"" "$session_config" || \
        die "XFCE failsafe session is missing $failsafe_program"
done

system_xfconf="$rootfs/etc/xdg/xfce4/xfconf/xfce-perchannel-xml"
for channel in \
    xsettings xfwm4 xfce4-panel xfce4-session keyboards thunar \
    xfce4-notifyd xfce4-power-manager xfce4-screensaver \
    xfce4-terminal xfce4-keyboard-shortcuts; do
    [[ -f "$system_xfconf/$channel.xml" ]] || \
        die "system XFCE profile is missing channel defaults: $channel"
done
[[ ! -d "$rootfs/root/.config/xfce4" ]] || \
    die "root desktop profile must not be seeded"
[[ $(rootfs_stat '%u:%g' /home/user) == 1000:1000 ]] || \
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

python3 - "$rootfs" <<'PY'
from pathlib import Path
import os
import re
import subprocess
import sys

root = Path(sys.argv[1])
artifacts = (
    root / "usr/bin/xfce4-notifyd-config",
    root / "usr/lib/xfce4/panel/plugins/libnotification-plugin.so",
    root / "usr/lib/xfce4/notifyd/xfce4-notifyd",
)
library_directories = (root / "usr/lib", root / "lib")
missing: list[tuple[str, str]] = []
sqlite_contract_errors: list[str] = []

for artifact in artifacts:
    result = subprocess.run(
        ["readelf", "-d", str(artifact)],
        text=True,
        capture_output=True,
        check=True,
        env={**os.environ, "LC_ALL": "C"},
    )
    needed = re.findall(r"Shared library: \[(.*?)\]", result.stdout)
    if "libsqlite3.so" in needed:
        sqlite_contract_errors.append(
            f"{artifact.relative_to(root)}: depends on unversioned libsqlite3.so"
        )
    if "libsqlite3.so.0" not in needed:
        sqlite_contract_errors.append(
            f"{artifact.relative_to(root)}: does not depend on libsqlite3.so.0"
        )
    for soname in needed:
        if not any((directory / soname).exists() for directory in library_directories):
            missing.append((str(artifact.relative_to(root)), soname))

if missing:
    for artifact, soname in missing:
        print(f"{artifact}: missing {soname}", file=sys.stderr)
    raise SystemExit(1)
if sqlite_contract_errors:
    for error in sqlite_contract_errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)

tumbler_jpeg = root / "usr/lib/tumbler-1/plugins/tumbler-jpeg-thumbnailer.so"
result = subprocess.run(
    ["readelf", "-d", str(tumbler_jpeg)],
    text=True,
    capture_output=True,
    check=True,
    env={**os.environ, "LC_ALL": "C"},
)
tumbler_needed = re.findall(r"Shared library: \[(.*?)\]", result.stdout)
if "libjpeg.so.62" not in tumbler_needed:
    print(
        "Tumbler JPEG thumbnailer does not use the target libjpeg.so.62 ABI",
        file=sys.stderr,
    )
    raise SystemExit(1)
if "libjpeg.so.8" in tumbler_needed:
    print(
        "Tumbler JPEG thumbnailer links against the host libjpeg.so.8 ABI",
        file=sys.stderr,
    )
    raise SystemExit(1)
PY

for profile_root in "$rootfs/etc/skel" "$rootfs/home/user"; do
    gtk2_settings="$profile_root/.gtkrc-2.0"
    gtk3_settings="$profile_root/.config/gtk-3.0/settings.ini"
    gtk4_settings="$profile_root/.config/gtk-4.0/settings.ini"
    cursor_settings="$profile_root/.icons/default/index.theme"

    [[ -f "$gtk2_settings" ]] || die "GTK 2 user theme defaults are missing: $gtk2_settings"
    [[ -f "$gtk3_settings" ]] || die "GTK 3 user theme defaults are missing: $gtk3_settings"
    [[ -f "$gtk4_settings" ]] || die "GTK 4 user theme defaults are missing: $gtk4_settings"
    [[ -f "$cursor_settings" ]] || die "cursor theme defaults are missing: $cursor_settings"
    grep -Fq 'gtk-theme-name="Qogir"' "$gtk2_settings" || \
        die "GTK 2 user defaults do not select Qogir"
    grep -Fq 'gtk-icon-theme-name="Qogir"' "$gtk2_settings" || \
        die "GTK 2 user defaults do not select Qogir icons"
    grep -Fq 'gtk-theme-name=Qogir' "$gtk3_settings" || \
        die "GTK 3 user defaults do not select Qogir"
    grep -Fq 'gtk-icon-theme-name=Qogir' "$gtk3_settings" || \
        die "GTK 3 user defaults do not select Qogir icons"
    grep -Fq 'gtk-theme-name=Qogir' "$gtk4_settings" || \
        die "GTK 4 user defaults do not select Qogir"
    grep -Fq 'gtk-icon-theme-name=Qogir' "$gtk4_settings" || \
        die "GTK 4 user defaults do not select Qogir icons"
    grep -Fq 'Inherits=Qogir' "$cursor_settings" || \
        die "user cursor defaults do not select Qogir"
done

for required_theme_path in \
    gtk-2.0/gtkrc gtk-3.0/gtk.css gtk-4.0/gtk.css \
    xfwm4/themerc xfce-notify-4.0/gtk.css; do
    [[ -f "$rootfs/usr/share/themes/Qogir/$required_theme_path" ]] || \
        die "Qogir desktop theme file is missing: $required_theme_path"
done
for excluded_theme_path in \
    cinnamon gnome-shell labwc metacity-1 plank unity; do
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
