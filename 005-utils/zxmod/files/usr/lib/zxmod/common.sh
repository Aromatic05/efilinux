#!/bin/sh

ZXMOD_RUN_ROOT=${ZXMOD_RUN_ROOT:-/run/zxmod}
ZXMOD_USR_TARGET=${ZXMOD_USR_TARGET:-/usr}
ZXMOD_OPT_TARGET=${ZXMOD_OPT_TARGET:-/opt}
ZXMOD_TAB=$(printf '\t')
ZXMOD_LOCK_HELD=

zxmod_die() {
    printf 'zxmod: %s\n' "$*" >&2
    exit 1
}

zxmod_require_root() {
    [ "$(id -u)" -eq 0 ] || zxmod_die 'must be run as root'
}

zxmod_path_exists() {
    [ -e "$1" ] || [ -L "$1" ]
}

zxmod_validate_id() {
    case ${1:-} in
        ''|[!a-z0-9]*|*[!a-z0-9._-]*) zxmod_die "invalid module id: ${1:-}" ;;
    esac
    [ ${#1} -le 64 ] || zxmod_die "module id is too long: $1"
}

zxmod_require_module_file() {
    case $1 in
        *.zxm) ;;
        *) zxmod_die "module filename must end in .zxm: $1" ;;
    esac
    [ -f "$1" ] && [ ! -L "$1" ] || zxmod_die "module file is not a regular file: $1"
    zxmod_module_path=$1
    case $zxmod_module_path in
        -*) zxmod_module_path=./$zxmod_module_path ;;
    esac
    realpath "$zxmod_module_path" || zxmod_die "cannot resolve module path: $1"
}

zxmod_read_id() {
    zxmod_source=$1
    zxmod_id=$(LC_ALL=C unsquashfs -cat "$zxmod_source" metadata/manifest 2>/dev/null |
        sed -n 's/^id=//p' | sed -n '1p')
}

zxmod_acquire_lock() {
    mkdir -p "$ZXMOD_RUN_ROOT"
    zxmod_lock="$ZXMOD_RUN_ROOT/lock"
    if ! mkdir "$zxmod_lock" 2>/dev/null; then
        zxmod_lock_pid=
        [ -f "$zxmod_lock/pid" ] && IFS= read -r zxmod_lock_pid < "$zxmod_lock/pid"
        case $zxmod_lock_pid in
            ''|*[!0-9]*) zxmod_lock_pid= ;;
        esac
        if [ -n "$zxmod_lock_pid" ] && kill -0 "$zxmod_lock_pid" 2>/dev/null; then
            zxmod_die "another module operation is active (pid $zxmod_lock_pid)"
        fi
        rm -rf -- "$zxmod_lock"
        mkdir "$zxmod_lock" 2>/dev/null || zxmod_die 'cannot acquire module operation lock'
    fi
    printf '%s\n' "$$" > "$zxmod_lock/pid"
    ZXMOD_LOCK_HELD=1
}

zxmod_release_lock() {
    if [ -n "$ZXMOD_LOCK_HELD" ]; then
        rm -rf -- "$ZXMOD_RUN_ROOT/lock"
        ZXMOD_LOCK_HELD=
    fi
}

zxmod_bind_base() {
    zxmod_target=$1
    zxmod_anchor=$2
    mkdir -p "$zxmod_anchor"
    if ! mountpoint -q "$zxmod_anchor"; then
        mount --bind "$zxmod_target" "$zxmod_anchor" ||
            zxmod_die "cannot retain base view: $zxmod_target"
        mount -o remount,bind,ro,nodev,nosuid "$zxmod_anchor" || {
            umount "$zxmod_anchor" 2>/dev/null || :
            zxmod_die "cannot protect retained base view: $zxmod_target"
        }
    fi
}

zxmod_ensure_target_mount() {
    zxmod_target=$1
    zxmod_anchor=$2
    mountpoint -q "$zxmod_target" && return
    mount --bind "$zxmod_anchor" "$zxmod_target" ||
        zxmod_die "cannot establish module target mount: $zxmod_target"
    mount -o remount,bind,ro,nodev,nosuid "$zxmod_target" || {
        umount "$zxmod_target" 2>/dev/null || :
        zxmod_die "cannot protect module target mount: $zxmod_target"
    }
}

zxmod_prepare_runtime() {
    mkdir -p "$ZXMOD_RUN_ROOT/modules" "$ZXMOD_RUN_ROOT/loops" \
        "$ZXMOD_RUN_ROOT/generations" "$ZXMOD_RUN_ROOT/base"
    [ -e "$ZXMOD_RUN_ROOT/active" ] || : > "$ZXMOD_RUN_ROOT/active"
    if [ ! -e /dev/loop-control ]; then
        [ -x /usr/bin/modprobe ] || zxmod_die 'modprobe is unavailable'
        /usr/bin/modprobe loop || zxmod_die 'cannot load the loop kernel module'
        zxmod_loop_wait=0
        while [ ! -e /dev/loop-control ] && [ "$zxmod_loop_wait" -lt 5 ]; do
            sleep 1
            zxmod_loop_wait=$((zxmod_loop_wait + 1))
        done
    fi
    [ -e /dev/loop-control ] || zxmod_die 'loop devices are unavailable'
    zxmod_bind_base "$ZXMOD_USR_TARGET" "$ZXMOD_RUN_ROOT/base/usr"
    zxmod_bind_base "$ZXMOD_OPT_TARGET" "$ZXMOD_RUN_ROOT/base/opt"
    zxmod_ensure_target_mount "$ZXMOD_USR_TARGET" "$ZXMOD_RUN_ROOT/base/usr"
    zxmod_ensure_target_mount "$ZXMOD_OPT_TARGET" "$ZXMOD_RUN_ROOT/base/opt"
}

zxmod_active_has_id() {
    awk -F '\t' -v id="$2" '$1 == id { found=1 } END { exit !found }' "$1"
}

zxmod_run_hook() {
    zxmod_hook_root=$1
    zxmod_hook_name=$2
    zxmod_hook="$zxmod_hook_root/metadata/hooks/$zxmod_hook_name"
    zxmod_path_exists "$zxmod_hook" || return 0
    if [ ! -f "$zxmod_hook" ] || [ -L "$zxmod_hook" ] || [ ! -x "$zxmod_hook" ]; then
        printf 'zxmod: ignoring invalid %s hook for %s\n' \
            "$zxmod_hook_name" "${zxmod_hook_root##*/}" >&2
        return 0
    fi
    if ! "$zxmod_hook"; then
        printf 'zxmod: %s hook failed for %s\n' \
            "$zxmod_hook_name" "${zxmod_hook_root##*/}" >&2
    fi
    return 0
}

zxmod_next_generation() {
    zxmod_generation=0
    for zxmod_path in "$ZXMOD_RUN_ROOT/generations"/*; do
        [ -d "$zxmod_path" ] || continue
        zxmod_number=${zxmod_path##*/}
        case $zxmod_number in *[!0-9]*|'') continue ;; esac
        [ "$zxmod_number" -gt "$zxmod_generation" ] && zxmod_generation=$zxmod_number
    done
    zxmod_generation=$((zxmod_generation + 1))
}

zxmod_generation_lowerdir() {
    zxmod_active_file=$1
    zxmod_subtree=$2
    zxmod_lower="$ZXMOD_RUN_ROOT/base/$zxmod_subtree"
    while IFS="$ZXMOD_TAB" read -r zxmod_active_id zxmod_active_source; do
        [ -n "$zxmod_active_id" ] || continue
        zxmod_module_tree="$ZXMOD_RUN_ROOT/modules/$zxmod_active_id/root/$zxmod_subtree"
        if [ -d "$zxmod_module_tree" ]; then
            zxmod_lower="$zxmod_module_tree:$zxmod_lower"
        fi
    done < "$zxmod_active_file"
    return 0
}

zxmod_mount_generation_tree() {
    zxmod_generation_lower=$1
    zxmod_generation_target=$2
    case $zxmod_generation_lower in
        *:*)
            mount -t overlay overlay -o "ro,lowerdir=$zxmod_generation_lower" \
                "$zxmod_generation_target"
            ;;
        *)
            mount --bind "$zxmod_generation_lower" "$zxmod_generation_target" || return
            mount -o remount,bind,ro,nodev,nosuid "$zxmod_generation_target" || {
                umount "$zxmod_generation_target" 2>/dev/null || :
                return 1
            }
            ;;
    esac
}

zxmod_remove_failed_generation() {
    zxmod_failed_root=$1
    umount -l "$zxmod_failed_root/opt" 2>/dev/null || :
    umount -l "$zxmod_failed_root/usr" 2>/dev/null || :
    rm -rf -- "$zxmod_failed_root"
}

zxmod_remove_generation_directory() {
    zxmod_old_generation=$1
    case $zxmod_old_generation in ''|0|*[!0-9]*) return 0 ;; esac
    zxmod_old_root="$ZXMOD_RUN_ROOT/generations/$zxmod_old_generation"
    [ -d "$zxmod_old_root" ] || return 0
    rmdir "$zxmod_old_root/opt" "$zxmod_old_root/usr" 2>/dev/null || :
    rmdir "$zxmod_old_root" 2>/dev/null || :
}

zxmod_move_generation_target() {
    zxmod_staged_target=$1
    zxmod_live_target=$2
    zxmod_retired_target=$3

    mount --move "$zxmod_live_target" "$zxmod_retired_target" || return 1
    if mount --move "$zxmod_staged_target" "$zxmod_live_target"; then
        return 0
    fi

    mount --move "$zxmod_retired_target" "$zxmod_live_target" ||
        zxmod_die "cannot restore module target after failed switch: $zxmod_live_target"
    return 1
}

zxmod_restore_generation_target() {
    zxmod_staged_target=$1
    zxmod_live_target=$2
    zxmod_retired_target=$3

    mount --move "$zxmod_live_target" "$zxmod_staged_target" ||
        zxmod_die "cannot return failed module generation to staging: $zxmod_live_target"
    mount --move "$zxmod_retired_target" "$zxmod_live_target" ||
        zxmod_die "cannot restore previous module generation: $zxmod_live_target"
}

zxmod_discard_retired_generation() {
    zxmod_retired_root=$1
    umount -l "$zxmod_retired_root/opt" ||
        zxmod_die 'cannot detach previous /opt module generation'
    umount -l "$zxmod_retired_root/usr" ||
        zxmod_die 'cannot detach previous /usr module generation'
    rmdir "$zxmod_retired_root/opt" "$zxmod_retired_root/usr"
    rmdir "$zxmod_retired_root"
}

zxmod_switch_generation() {
    zxmod_candidate=$1
    zxmod_old_generation=0
    if [ -f "$ZXMOD_RUN_ROOT/current-generation" ]; then
        IFS= read -r zxmod_old_generation < "$ZXMOD_RUN_ROOT/current-generation"
        case $zxmod_old_generation in ''|*[!0-9]*)
            zxmod_die 'current module generation is invalid'
            ;;
        esac
    fi

    zxmod_next_generation
    zxmod_generation_root="$ZXMOD_RUN_ROOT/generations/$zxmod_generation"
    zxmod_retired_root="$ZXMOD_RUN_ROOT/retired/$zxmod_generation"
    mkdir -p \
        "$zxmod_generation_root/usr" \
        "$zxmod_generation_root/opt" \
        "$zxmod_retired_root/usr" \
        "$zxmod_retired_root/opt"

    zxmod_generation_lowerdir "$zxmod_candidate" usr
    zxmod_usr_lower=$zxmod_lower
    zxmod_generation_lowerdir "$zxmod_candidate" opt
    zxmod_opt_lower=$zxmod_lower

    zxmod_mount_generation_tree "$zxmod_usr_lower" "$zxmod_generation_root/usr" || {
        zxmod_remove_failed_generation "$zxmod_generation_root"
        rm -rf -- "$zxmod_retired_root"
        zxmod_die 'cannot construct /usr module generation'
    }
    zxmod_mount_generation_tree "$zxmod_opt_lower" "$zxmod_generation_root/opt" || {
        zxmod_remove_failed_generation "$zxmod_generation_root"
        rm -rf -- "$zxmod_retired_root"
        zxmod_die 'cannot construct /opt module generation'
    }

    zxmod_generation_next="$ZXMOD_RUN_ROOT/current-generation.next.$$"
    zxmod_active_backup="$ZXMOD_RUN_ROOT/active.rollback.$$"
    zxmod_track_temp "$zxmod_generation_next"
    zxmod_track_temp "$zxmod_active_backup"
    printf '%s\n' "$zxmod_generation" > "$zxmod_generation_next" || {
        zxmod_remove_failed_generation "$zxmod_generation_root"
        rm -rf -- "$zxmod_retired_root"
        zxmod_die 'cannot record module generation'
    }
    cp -- "$ZXMOD_RUN_ROOT/active" "$zxmod_active_backup" || {
        zxmod_remove_failed_generation "$zxmod_generation_root"
        rm -rf -- "$zxmod_retired_root"
        zxmod_die 'cannot preserve active module state'
    }

    if ! zxmod_move_generation_target \
        "$zxmod_generation_root/usr" \
        "$ZXMOD_USR_TARGET" \
        "$zxmod_retired_root/usr"; then
        zxmod_remove_failed_generation "$zxmod_generation_root"
        rm -rf -- "$zxmod_retired_root"
        zxmod_die 'cannot switch /usr module generation'
    fi
    if ! zxmod_move_generation_target \
        "$zxmod_generation_root/opt" \
        "$ZXMOD_OPT_TARGET" \
        "$zxmod_retired_root/opt"; then
        zxmod_restore_generation_target \
            "$zxmod_generation_root/usr" \
            "$ZXMOD_USR_TARGET" \
            "$zxmod_retired_root/usr"
        zxmod_remove_failed_generation "$zxmod_generation_root"
        rm -rf -- "$zxmod_retired_root"
        zxmod_die 'cannot switch /opt module generation'
    fi

    if ! mv -- "$zxmod_candidate" "$ZXMOD_RUN_ROOT/active"; then
        zxmod_restore_generation_target \
            "$zxmod_generation_root/opt" \
            "$ZXMOD_OPT_TARGET" \
            "$zxmod_retired_root/opt"
        zxmod_restore_generation_target \
            "$zxmod_generation_root/usr" \
            "$ZXMOD_USR_TARGET" \
            "$zxmod_retired_root/usr"
        zxmod_remove_failed_generation "$zxmod_generation_root"
        rm -rf -- "$zxmod_retired_root"
        zxmod_die 'cannot commit active module state'
    fi
    if ! mv -- "$zxmod_generation_next" "$ZXMOD_RUN_ROOT/current-generation"; then
        mv -- "$zxmod_active_backup" "$ZXMOD_RUN_ROOT/active" ||
            zxmod_die 'cannot restore active module state after failed generation commit'
        zxmod_restore_generation_target \
            "$zxmod_generation_root/opt" \
            "$ZXMOD_OPT_TARGET" \
            "$zxmod_retired_root/opt"
        zxmod_restore_generation_target \
            "$zxmod_generation_root/usr" \
            "$ZXMOD_USR_TARGET" \
            "$zxmod_retired_root/usr"
        zxmod_remove_failed_generation "$zxmod_generation_root"
        rm -rf -- "$zxmod_retired_root"
        zxmod_die 'cannot commit module generation number'
    fi

    rm -f -- "$zxmod_active_backup"
    zxmod_discard_retired_generation "$zxmod_retired_root"
    zxmod_remove_generation_directory "$zxmod_old_generation"
}

zxmod_refresh_desktop_sessions() {
    zxmod_session=
    for zxmod_session in /proc/[0-9]*; do
        [ -r "$zxmod_session/comm" ] && [ -r "$zxmod_session/status" ] && \
            [ -r "$zxmod_session/environ" ] || continue
        IFS= read -r zxmod_session_command < "$zxmod_session/comm" || continue
        [ "$zxmod_session_command" = xfce4-session ] || continue

        zxmod_session_uid=$(awk '/^Uid:/ { print $2; exit }' "$zxmod_session/status")
        case $zxmod_session_uid in ''|0|*[!0-9]*) continue ;; esac
        zxmod_session_user=$(awk -F: -v uid="$zxmod_session_uid" '$3 == uid { print $1; exit }' /etc/passwd)
        zxmod_session_home=$(awk -F: -v uid="$zxmod_session_uid" '$3 == uid { print $6; exit }' /etc/passwd)
        [ -n "$zxmod_session_user" ] && [ -n "$zxmod_session_home" ] || continue

        zxmod_session_display=$(tr '\0' '\n' < "$zxmod_session/environ" | sed -n 's/^DISPLAY=//p' | sed -n '1p')
        zxmod_session_dbus=$(tr '\0' '\n' < "$zxmod_session/environ" | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p' | sed -n '1p')
        zxmod_session_runtime=$(tr '\0' '\n' < "$zxmod_session/environ" | sed -n 's/^XDG_RUNTIME_DIR=//p' | sed -n '1p')
        zxmod_session_xauthority=$(tr '\0' '\n' < "$zxmod_session/environ" | sed -n 's/^XAUTHORITY=//p' | sed -n '1p')
        [ -n "$zxmod_session_display" ] && [ -n "$zxmod_session_dbus" ] && \
            [ -n "$zxmod_session_runtime" ] || continue

        DISPLAY="$zxmod_session_display" \
        DBUS_SESSION_BUS_ADDRESS="$zxmod_session_dbus" \
        XDG_RUNTIME_DIR="$zxmod_session_runtime" \
        XAUTHORITY="${zxmod_session_xauthority:-$zxmod_session_home/.Xauthority}" \
        HOME="$zxmod_session_home" USER="$zxmod_session_user" LOGNAME="$zxmod_session_user" \
            /usr/bin/su -p -s /usr/bin/sh "$zxmod_session_user" -c \
            '/usr/bin/xfce4-panel --restart >/dev/null 2>&1' >/dev/null 2>&1 || :
    done
    return 0
}
