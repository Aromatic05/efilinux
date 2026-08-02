#!/usr/bin/sh

set -eu

boot_number=${1:-${EFILINUX_LIVE_BOOT:-}}
media_file=/run/efilinux/live/media.tsv
persistent_marker=/etc/efilinux-live-persistent-marker

fail() {
    printf 'EFILINUX_LIVE_FAIL:%s\n' "$1"
    /usr/bin/findmnt -R /run/efilinux/live 2>/dev/null || true
    /usr/bin/findmnt -R /run/zxmod 2>/dev/null || true
    /usr/bin/cat "$media_file" 2>/dev/null || true
    /usr/bin/poweroff -f
    exit 1
}

[ "$boot_number" = 1 ] || [ "$boot_number" = 2 ] || fail invalid-boot-number
[ "$(id -u)" = 0 ] || fail not-root
[ -e /run/efilinux/live/root-active ] || fail persistent-root-inactive
[ "$(/usr/bin/findmnt -rn -T / -o FSTYPE)" = overlay ] || fail root-is-not-overlay
[ -s "$media_file" ] || fail media-records-missing

iso_mount=$(/usr/bin/awk -F '\t' '$4 == "iso9660" { print $2; exit }' "$media_file")
ext_mount=$(/usr/bin/awk -F '\t' '$4 == "ext4" { print $2; exit }' "$media_file")
[ -n "$iso_mount" ] || fail iso9660-media-not-enumerated
[ -n "$ext_mount" ] || fail ext4-media-not-enumerated
[ "$(/usr/bin/cat "$iso_mount/efilinux/iso-marker.txt")" = efilinux-iso9660-ok ] ||
    fail iso9660-marker-unreadable
[ -f "$ext_mount/efilinux/persistence.img" ] || fail persistence-container-unavailable

/usr/bin/grep -qw iso9660 /proc/filesystems || fail iso9660-filesystem-unavailable
/usr/bin/grep -qw udf /proc/filesystems || fail udf-filesystem-unavailable

/usr/bin/awk -F '\t' '$1 == "live-sample" { found=1 } END { exit !found }' \
    /run/zxmod/active || fail module-not-autoloaded
[ "$(/usr/bin/live-module-command)" = live-module-autoload-ok ] ||
    fail module-command-failed
/usr/bin/getcap /usr/bin/arping | \
    /usr/bin/grep -Fxq '/usr/bin/arping cap_net_raw=ep' ||
    fail base-capability-not-replayed

udf_device=$(/usr/bin/blkid -t TYPE=udf -o device | /usr/bin/head -n 1)
[ -b "$udf_device" ] || fail udf-device-missing
mkdir -p /mnt/efilinux-udf
/usr/bin/mount -t udf -o ro "$udf_device" /mnt/efilinux-udf || fail udf-mount
[ "$(/usr/bin/findmnt -rn -T /mnt/efilinux-udf -o FSTYPE)" = udf ] ||
    fail udf-mount-type
[ "$(/usr/bin/blkid -s LABEL -o value "$udf_device")" = EFILINUX_UDF ] ||
    fail udf-label
/usr/bin/umount /mnt/efilinux-udf || fail udf-unmount

case $boot_number in
    1)
        [ ! -e "$persistent_marker" ] || fail marker-present-on-first-boot
        printf '%s\n' 'persisted-across-reboot' > "$persistent_marker"
        /usr/bin/sync
        printf 'EFILINUX_LIVE_PERSISTENCE_WRITTEN\n'
        ;;
    2)
        [ "$(/usr/bin/cat "$persistent_marker")" = persisted-across-reboot ] ||
            fail marker-not-restored
        printf 'EFILINUX_LIVE_PERSISTENCE_RESTORED\n'
        ;;
esac

printf 'EFILINUX_LIVE_MEDIA_OK\n'
printf 'EFILINUX_LIVE_MODULE_OK\n'
printf 'EFILINUX_LIVE_BOOT_%s_OK\n' "$boot_number"
/usr/bin/sync
/usr/bin/poweroff -f
