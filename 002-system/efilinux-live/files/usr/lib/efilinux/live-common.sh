#!/bin/sh

EFILINUX_LIVE_RUN_ROOT=${EFILINUX_LIVE_RUN_ROOT:-/run/efilinux/live}
EFILINUX_LIVE_MEDIA_ROOT=${EFILINUX_LIVE_MEDIA_ROOT:-$EFILINUX_LIVE_RUN_ROOT/media}
EFILINUX_LIVE_MEDIA_FILE=${EFILINUX_LIVE_MEDIA_FILE:-$EFILINUX_LIVE_RUN_ROOT/media.tsv}
EFILINUX_LIVE_DIRECTORY=efilinux
EFILINUX_LIVE_CONFIG=efilinux.conf
EFILINUX_LIVE_TAB=$(printf '\t')

live_log() {
    printf 'efilinux-live: %s\n' "$*" >&2
    if [ "${EFILINUX_LIVE_SERIAL_FD:-}" = 9 ]; then
        printf 'efilinux-live: %s\n' "$*" >&9
    elif [ "${EFILINUX_LIVE_SERIAL_LOG:-0}" = 1 ] && [ -c /dev/ttyS0 ]; then
        printf 'efilinux-live: %s\n' "$*" > /dev/ttyS0 2>/dev/null || :
    fi
}

live_prepare_runtime() {
    mkdir -p "$EFILINUX_LIVE_RUN_ROOT" "$EFILINUX_LIVE_MEDIA_ROOT"
}

live_mount_virtual_filesystems() {
    mkdir -p /proc /sys /dev /dev/pts /dev/shm /run
    mountpoint -q /proc || mount -t proc proc /proc
    mountpoint -q /sys || mount -t sysfs sysfs /sys
    mountpoint -q /dev || mount -t devtmpfs devtmpfs /dev
    mkdir -p /dev/pts /dev/shm
    mountpoint -q /dev/pts || \
        mount -t devpts -o gid=5,mode=0620,nosuid,noexec devpts /dev/pts
    mountpoint -q /dev/shm || \
        mount -t tmpfs -o mode=1777,nosuid,nodev tmpfs /dev/shm
    mountpoint -q /run || mount -t tmpfs -o mode=0755,nosuid,nodev tmpfs /run
    mkdir -p /run/lock /run/efilinux /run/dbus /run/sshd /run/user
}

live_validate_relative_path() {
    live_path=$1
    case $live_path in
        ''|/*|.|..|*/.|*/..|./*|../*|*/../*|*/./*|*//*|*[[:space:]]*) return 1 ;;
    esac
    return 0
}

live_resolve_managed_path() {
    live_base=$(readlink -f -- "$1") || return 1
    live_resolved=$(readlink -f -- "$1/$2") || return 1
    case $live_resolved in
        "$live_base"/*) printf '%s\n' "$live_resolved" ;;
        *) return 1 ;;
    esac
}

live_device_key() {
    printf '%s' "$1" | cksum | awk '{ print $1 }'
}

live_try_filesystem_module() {
    case $1 in
        iso9660) modprobe isofs 2>/dev/null || : ;;
        udf|exfat|ntfs3|btrfs|xfs) modprobe "$1" 2>/dev/null || : ;;
    esac
}

live_existing_mount() {
    findmnt -rn -S "$1" -o TARGET 2>/dev/null | head -n 1
}

live_scan_media() {
    live_prepare_runtime
    live_next="$EFILINUX_LIVE_MEDIA_FILE.next.$$"
    : > "$live_next"
    live_inventory=$(lsblk -nrpo NAME,TYPE,FSTYPE | LC_ALL=C sort)

    while read -r live_device live_type live_fstype; do
        case $live_type in
            disk|part|rom|crypt|lvm|md|mpath|raid*) ;;
            *) continue ;;
        esac
        [ -b "$live_device" ] || continue
        if [ -z "$live_fstype" ]; then
            live_fstype=$(blkid -p -s TYPE -o value "$live_device" 2>/dev/null || :)
        fi
        [ -n "$live_fstype" ] || continue
        live_try_filesystem_module "$live_fstype"

        live_mount=$(live_existing_mount "$live_device")
        live_owned=0
        if [ -z "$live_mount" ]; then
            live_key=$(live_device_key "$live_device")
            live_mount="$EFILINUX_LIVE_MEDIA_ROOT/$live_key"
            mkdir -p "$live_mount"
            if ! mount -t "$live_fstype" -o ro,nosuid,nodev,noexec \
                    "$live_device" "$live_mount" 2>/dev/null; then
                rmdir "$live_mount" 2>/dev/null || :
                live_log "cannot inspect $live_device ($live_fstype)"
                continue
            fi
            live_owned=1
        fi

        if [ -d "$live_mount/$EFILINUX_LIVE_DIRECTORY" ] && \
           [ ! -L "$live_mount/$EFILINUX_LIVE_DIRECTORY" ]; then
            case "$live_device$live_mount" in
                *"$EFILINUX_LIVE_TAB"*)
                    live_log "ignoring media path containing a tab: $live_device"
                    ;;
                *)
                    printf '%s\t%s\t%s\t%s\n' \
                        "$live_device" "$live_mount" "$live_owned" "$live_fstype" \
                        >> "$live_next"
                    ;;
            esac
        elif [ "$live_owned" -eq 1 ]; then
            umount "$live_mount" 2>/dev/null || :
            rmdir "$live_mount" 2>/dev/null || :
        fi
    done <<EOF
$live_inventory
EOF

    LC_ALL=C sort -u "$live_next" > "$EFILINUX_LIVE_MEDIA_FILE"
    rm -f "$live_next"
}

live_config_records() {
    [ -f "$EFILINUX_LIVE_MEDIA_FILE" ] || return 0
    while IFS="$EFILINUX_LIVE_TAB" read -r live_device live_mount live_owned live_fstype; do
        [ -n "$live_device" ] || continue
        live_config="$live_mount/$EFILINUX_LIVE_DIRECTORY/$EFILINUX_LIVE_CONFIG"
        [ -f "$live_config" ] && [ ! -L "$live_config" ] || continue
        printf '%s\t%s\t%s\t%s\t%s\n' \
            "$live_config" "$live_device" "$live_mount" "$live_owned" "$live_fstype"
    done < "$EFILINUX_LIVE_MEDIA_FILE"
}

live_parse_config() {
    live_config=$1
    live_line_number=0
    while IFS= read -r live_line || [ -n "$live_line" ]; do
        live_line_number=$((live_line_number + 1))
        live_line=${live_line%%#*}
        set -f
        # Intentional tokenization: the format is exactly two whitespace-free fields.
        # shellcheck disable=SC2086
        set -- $live_line
        set +f
        [ $# -eq 0 ] && continue
        if [ $# -ne 2 ]; then
            live_log "$live_config:$live_line_number: expected a directive and one path"
            continue
        fi
        case $1 in
            module)
                if ! live_validate_relative_path "$2"; then
                    live_log "$live_config:$live_line_number: invalid module path: $2"
                    continue
                fi
                case $2 in
                    *.zxm) ;;
                    *)
                        live_log "$live_config:$live_line_number: invalid module path: $2"
                        continue
                        ;;
                esac
                ;;
            persistence)
                if ! live_validate_relative_path "$2"; then
                    live_log "$live_config:$live_line_number: invalid persistence path: $2"
                    continue
                fi
                case $2 in
                    *.img) ;;
                    *)
                        live_log "$live_config:$live_line_number: invalid persistence path: $2"
                        continue
                        ;;
                esac
                ;;
            *)
                live_log "$live_config:$live_line_number: unknown directive: $1"
                continue
                ;;
        esac
        printf '%s\t%s\n' "$1" "$2"
    done < "$live_config"
}

live_mount_is_read_write() {
    live_options=$(findmnt -rn -T "$1" -o OPTIONS 2>/dev/null || :)
    case ,$live_options, in *,rw,*) return 0 ;; esac
    return 1
}

live_enable_media_writes() {
    live_mount=$1
    live_device=${2:-}
    if live_mount_is_read_write "$live_mount"; then
        return 0
    fi
    if [ -n "$live_device" ]; then
        mount -o remount,rw "$live_device" "$live_mount" 2>/dev/null || return 1
    else
        mount -o remount,rw "$live_mount" 2>/dev/null || return 1
    fi
    live_mount_is_read_write "$live_mount"
}
