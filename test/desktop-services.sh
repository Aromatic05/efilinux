#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

rootfs="$EFILINUX_ROOTFS"
loader="$rootfs/usr/lib/ld-linux-x86-64.so.2"
library_path="$rootfs/usr/lib:$rootfs/usr/lib/gvfs"

require_file() {
    [[ -f "$rootfs$1" ]] || die "desktop service file is missing: $1"
}

require_directory() {
    [[ -d "$rootfs$1" ]] || die "desktop service directory is missing: $1"
}

require_program() {
    local path=$1
    [[ -x "$rootfs$path" ]] || die "desktop service program is missing: $path"
}

for path in \
    /usr/bin/loginctl \
    /usr/libexec/elogind \
    /usr/lib/polkit-1/polkitd \
    /usr/bin/pkcheck \
    /usr/bin/dmsetup \
    /usr/bin/cryptsetup \
    /usr/bin/mdadm \
    /usr/bin/udisksctl \
    /usr/lib/udisks2/udisksd \
    /usr/lib/gvfsd \
    /usr/lib/gvfsd-fuse \
    /usr/lib/gvfs-udisks2-volume-monitor \
    /usr/bin/upower \
    /usr/libexec/upowerd \
    /usr/bin/NetworkManager \
    /usr/bin/nmcli \
    /usr/lib/iwd \
    /usr/bin/iwctl \
    /usr/bin/pipewire \
    /usr/bin/pipewire-pulse \
    /usr/bin/wireplumber \
    /usr/bin/pw-cli; do
    require_program "$path"
done

for path in \
    /usr/lib/libelogind.so.0 \
    /usr/lib/libpolkit-gobject-1.so.0 \
    /usr/lib/libdevmapper.so.1.02 \
    /usr/lib/libcryptsetup.so.12 \
    /usr/lib/libbytesize.so.1 \
    /usr/lib/libnvme.so.1 \
    /usr/lib/libblockdev.so.3 \
    /usr/lib/libbd_crypto.so.3 \
    /usr/lib/libbd_mdraid.so.3 \
    /usr/lib/libbd_nvme.so.3 \
    /usr/lib/libudisks2.so.0 \
    /usr/lib/libupower-glib.so.3 \
    /usr/lib/libnm.so.0 \
    /usr/lib/libpipewire-0.3.so.0 \
    /usr/lib/libwireplumber-0.5.so.0 \
    /usr/lib/libpulse.so.0 \
    /usr/lib/libpulse-mainloop-glib.so.0; do
    [[ -e "$rootfs$path" ]] || die "desktop service library is missing: $path"
done

for path in \
    /usr/share/dbus-1/system-services/org.freedesktop.login1.service \
    /usr/share/dbus-1/system-services/org.freedesktop.PolicyKit1.service \
    /usr/share/dbus-1/system-services/org.freedesktop.UDisks2.service \
    /usr/share/dbus-1/system-services/org.freedesktop.UPower.service \
    /usr/share/dbus-1/system.d/org.freedesktop.NetworkManager.conf \
    /usr/share/dbus-1/system-services/org.freedesktop.nm_dispatcher.service \
    /usr/share/dbus-1/services/org.gtk.vfs.Daemon.service \
    /usr/share/polkit-1/actions/org.gtk.vfs.file-operations.policy \
    /usr/share/polkit-1/rules.d/org.gtk.vfs.file-operations.rules \
    /usr/share/pipewire/pipewire.conf \
    /usr/share/wireplumber/wireplumber.conf; do
    require_file "$path"
done

require_file /usr/lib/gio/modules/libgvfsdbus.so
require_file /usr/lib/gio/modules/libgioremote-volume-monitor.so
require_file /usr/lib/gio/modules/giomodule.cache
require_file /usr/share/glib-2.0/schemas/org.gnome.system.gvfs.enums.xml
require_file /usr/share/glib-2.0/schemas/gschemas.compiled

grep -Fq 'libgvfsdbus.so' "$rootfs/usr/lib/gio/modules/giomodule.cache" || \
    die "GVfs GIO module cache does not contain libgvfsdbus"
grep -Fq 'libgioremote-volume-monitor.so' "$rootfs/usr/lib/gio/modules/giomodule.cache" || \
    die "GVfs GIO module cache does not contain the remote volume monitor"

for service in elogind polkit udisks2 upower iwd networkmanager; do
    require_file "/etc/rc.d/init.d/$service"
    [[ -x "$rootfs/etc/rc.d/init.d/$service" ]] || \
        die "desktop service script is not executable: $service"
done

require_file /etc/pam.d/system-auth
grep -Eq '^session[[:space:]]+optional[[:space:]]+pam_elogind\.so$' \
    "$rootfs/etc/pam.d/system-auth" || die "PAM does not open elogind sessions"

grep -Eq '^wheel:x:10:.*user' "$rootfs/etc/group" || \
    die "desktop user is not in wheel"

for runlevel in 2 3 4 5; do
    [[ -L "$rootfs/etc/rc.d/rc${runlevel}.d/S25elogind" ]] || \
        die "runlevel $runlevel does not start elogind"
    [[ -L "$rootfs/etc/rc.d/rc${runlevel}.d/S50iwd" ]] || \
        die "runlevel $runlevel does not start iwd"
    [[ -L "$rootfs/etc/rc.d/rc${runlevel}.d/S55networkmanager" ]] || \
        die "runlevel $runlevel does not start NetworkManager"
done

for runlevel in 2 3 4 5; do
    if find "$rootfs/etc/rc.d/rc${runlevel}.d" -maxdepth 1 -name 'S*dhcpcd' -print -quit | grep -q .; then
        die "dhcpcd still races NetworkManager in runlevel $runlevel"
    fi
done

grep -Fq 'wifi.backend=iwd' "$rootfs/etc/NetworkManager/NetworkManager.conf" || \
    die "NetworkManager does not use the iwd Wi-Fi backend"
grep -Fq 'EnableNetworkConfiguration=false' "$rootfs/etc/iwd/main.conf" || \
    die "iwd still competes with NetworkManager for IP configuration"

if [[ -e "$rootfs/usr/bin/systemd" || -e "$rootfs/usr/lib/systemd/systemd" ]]; then
    die "systemd runtime leaked into SysVinit desktop services"
fi
[[ ! -e "$rootfs/home/aromatic" ]] || \
    die "a build-host path leaked into the target rootfs"
if find "$rootfs" -iname '*wpa_supplicant*' -print -quit | grep -q .; then
    die "wpa_supplicant remains after selecting the iwd backend"
fi

grep -Fq '/usr/lib/nm-dispatcher' \
    "$rootfs/usr/share/dbus-1/system-services/org.freedesktop.nm_dispatcher.service" || \
    die "NetworkManager dispatcher activation uses an invalid executable path"
grep -Fq 'org.gtk.vfs.file-operations' \
    "$rootfs/usr/share/polkit-1/actions/org.gtk.vfs.file-operations.policy" || \
    die "GVfs admin backend has no matching polkit action"
grep -Fq 'org.gtk.vfs.file-operations' \
    "$rootfs/usr/share/polkit-1/rules.d/org.gtk.vfs.file-operations.rules" || \
    die "GVfs admin backend has no matching polkit rule"

grep -Fq '/usr/lib/gvfsd' \
    "$rootfs/usr/share/dbus-1/services/org.gtk.vfs.Daemon.service" || \
    die "GVfs D-Bus activation uses an invalid executable path"

"$loader" --library-path "$library_path" "$rootfs/usr/bin/NetworkManager" --version >/dev/null
"$loader" --library-path "$library_path" "$rootfs/usr/bin/nmcli" --version >/dev/null
"$loader" --library-path "$library_path" "$rootfs/usr/bin/iwctl" --help >/dev/null
"$loader" --library-path "$library_path" "$rootfs/usr/bin/mdadm" --version >/dev/null 2>&1
"$loader" --library-path "$library_path" "$rootfs/usr/bin/cryptsetup" --version >/dev/null
"$loader" --library-path "$library_path" "$rootfs/usr/bin/udisksctl" help >/dev/null
"$loader" --library-path "$library_path" "$rootfs/usr/bin/pipewire" --version >/dev/null
"$loader" --library-path "$library_path" "$rootfs/usr/bin/wireplumber" --version >/dev/null

log "002 desktop session, policy, storage, network, and audio service contract passed"
