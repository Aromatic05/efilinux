#!/bin/sh

ZXMOD_RUN_ROOT=${ZXMOD_RUN_ROOT:-/run/zxmod}
ZXMOD_USR_TARGET=${ZXMOD_USR_TARGET:-/usr}
ZXMOD_OPT_TARGET=${ZXMOD_OPT_TARGET:-/opt}
ZXMOD_CONFIG=${ZXMOD_CONFIG:-/etc/zxmod.conf}
ZXMOD_TAB=$(printf '\t')
ZXMOD_NEWLINE='
'
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

zxmod_validate_arch() {
    case ${1:-} in
        ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*) zxmod_die "invalid architecture: ${1:-}" ;;
    esac
}

zxmod_source_identity() {
    zxmod_digest_output=$(LC_ALL=C openssl dgst -sha256 -r "$1") ||
        zxmod_die "cannot hash module source: $1"
    zxmod_digest=${zxmod_digest_output%% *}
    [ ${#zxmod_digest} -eq 64 ] || zxmod_die "invalid module source digest: $1"
    case $zxmod_digest in
        *[!0-9a-f]*) zxmod_die "invalid module source digest: $1" ;;
    esac
    printf '%s\n' "$zxmod_digest"
}

zxmod_manifest_count() {
    awk -F= -v key="$1" '$1 == key { count++ } END { print count + 0 }' "$2"
}

zxmod_manifest_value() {
    awk -F= -v key="$1" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$2"
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

zxmod_read_manifest() {
    zxmod_source=$1
    zxmod_manifest=$2

    LC_ALL=C unsquashfs -cat "$zxmod_source" metadata/manifest > "$zxmod_manifest" 2>/dev/null ||
        zxmod_die 'module does not contain metadata/manifest'
    if ! awk -F= '
        NF < 2 { exit 1 }
        $1 !~ /^(format|id|arch|version|description)$/ { exit 1 }
        { next }
    ' "$zxmod_manifest"; then
        zxmod_die 'manifest contains malformed or unknown fields'
    fi
    for zxmod_key in format id arch version; do
        [ "$(zxmod_manifest_count "$zxmod_key" "$zxmod_manifest")" -eq 1 ] ||
            zxmod_die "manifest has duplicate or missing $zxmod_key"
    done
    [ "$(zxmod_manifest_count description "$zxmod_manifest")" -le 1 ] ||
        zxmod_die 'manifest has duplicate description'

    [ "$(zxmod_manifest_value format "$zxmod_manifest")" = 1 ] ||
        zxmod_die 'unsupported module format'
    zxmod_id=$(zxmod_manifest_value id "$zxmod_manifest")
    zxmod_arch=$(zxmod_manifest_value arch "$zxmod_manifest")
    zxmod_version=$(zxmod_manifest_value version "$zxmod_manifest")
    zxmod_validate_id "$zxmod_id"
    zxmod_validate_arch "$zxmod_arch"
    [ "$zxmod_arch" = "$(uname -m)" ] ||
        zxmod_die "module architecture $zxmod_arch does not match $(uname -m)"
    case $zxmod_version in
        ''|*[!A-Za-z0-9._+:-]*) zxmod_die 'invalid module version' ;;
    esac
    LC_ALL=C unsquashfs -s "$zxmod_source" 2>/dev/null |
        grep -Eq '^Compression[[:space:]]+zstd$' ||
        zxmod_die 'module payload is not Zstd-compressed SquashFS'
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

zxmod_normalize_link() {
    zxmod_relative=$1
    zxmod_link=$2
    awk -v relative="$zxmod_relative" -v link="$zxmod_link" 'BEGIN {
        if (substr(link, 1, 1) == "/") {
            candidate = substr(link, 2)
        } else {
            slash = 0
            for (i = 1; i <= length(relative); i++) {
                if (substr(relative, i, 1) == "/")
                    slash = i
            }
            if (slash == 0)
                base = ""
            else
                base = substr(relative, 1, slash - 1)
            candidate = base "/" link
        }
        count = split(candidate, part, "/")
        depth = 0
        for (i = 1; i <= count; i++) {
            if (part[i] == "" || part[i] == ".")
                continue
            if (part[i] == "..") {
                if (depth == 0)
                    exit 1
                depth--
                continue
            }
            stack[++depth] = part[i]
        }
        if (depth == 0)
            exit 1
        output = stack[1]
        for (i = 2; i <= depth; i++)
            output = output "/" stack[i]
        print output
    }'
}

zxmod_active_has_id() {
    awk -F '\t' -v id="$2" '$1 == id { found=1 } END { exit !found }' "$1"
}

zxmod_validate_payload_tree() {
    zxmod_root=$1
    for zxmod_top in \
        "$zxmod_root"/* \
        "$zxmod_root"/.[!.]* \
        "$zxmod_root"/..?*; do
        zxmod_path_exists "$zxmod_top" || continue
        case $(basename -- "$zxmod_top") in
            metadata|root) ;;
            *) zxmod_die "unexpected top-level module path: $(basename -- "$zxmod_top")" ;;
        esac
    done
    [ -d "$zxmod_root/root" ] && [ ! -L "$zxmod_root/root" ] ||
        zxmod_die 'module payload root is missing or invalid'
    for zxmod_top in \
        "$zxmod_root/root"/* \
        "$zxmod_root/root"/.[!.]* \
        "$zxmod_root/root"/..?*; do
        zxmod_path_exists "$zxmod_top" || continue
        case $(basename -- "$zxmod_top") in
            usr|opt)
                [ -d "$zxmod_top" ] && [ ! -L "$zxmod_top" ] ||
                    zxmod_die 'payload /usr or /opt is not a directory'
                ;;
            *) zxmod_die "payload is outside /usr and /opt: $(basename -- "$zxmod_top")" ;;
        esac
    done
}

zxmod_validate_one_path() {
    zxmod_path=$1
    zxmod_root=$2
    zxmod_active_file=$3
    zxmod_relative=${zxmod_path#"$zxmod_root/root/"}

    case $zxmod_relative in
        usr|opt) return ;;
        usr/*|opt/*) ;;
        *) zxmod_die "unsafe payload path: $zxmod_relative" ;;
    esac
    case $zxmod_relative in
        *'//'|*'/./'*|*'/../'*|*'/..'|*'/'|*"$ZXMOD_NEWLINE"*)
            zxmod_die "unsafe payload path: $zxmod_relative"
            ;;
    esac
    if [ ! -d "$zxmod_path" ] && [ ! -f "$zxmod_path" ] && [ ! -L "$zxmod_path" ]; then
        zxmod_die "unsupported payload file type: /$zxmod_relative"
    fi
    if [ -L "$zxmod_path" ]; then
        zxmod_link=$(readlink -- "$zxmod_path")
        zxmod_normalized=$(zxmod_normalize_link "$zxmod_relative" "$zxmod_link") ||
            zxmod_die "module link escapes its payload: /$zxmod_relative -> $zxmod_link"
        case $zxmod_normalized in
            usr|usr/*|opt|opt/*) ;;
            *) zxmod_die "module link escapes /usr and /opt: /$zxmod_relative -> $zxmod_link" ;;
        esac
    fi

    zxmod_base="$ZXMOD_RUN_ROOT/base/$zxmod_relative"
    if [ -d "$zxmod_path" ] && [ ! -L "$zxmod_path" ]; then
        if zxmod_path_exists "$zxmod_base" && { [ ! -d "$zxmod_base" ] || [ -L "$zxmod_base" ]; }; then
            zxmod_die "module directory conflicts with base system: /$zxmod_relative"
        fi
        while IFS="$ZXMOD_TAB" read -r zxmod_active_id zxmod_active_source zxmod_active_identity; do
            [ -n "$zxmod_active_id" ] || continue
            zxmod_other="$ZXMOD_RUN_ROOT/modules/$zxmod_active_id/root/$zxmod_relative"
            if zxmod_path_exists "$zxmod_other" && { [ ! -d "$zxmod_other" ] || [ -L "$zxmod_other" ]; }; then
                zxmod_die "module directory conflicts with active module $zxmod_active_id: /$zxmod_relative"
            fi
        done < "$zxmod_active_file"
        return
    fi

    zxmod_path_exists "$zxmod_base" &&
        zxmod_die "module path conflicts with base system: /$zxmod_relative"
    while IFS="$ZXMOD_TAB" read -r zxmod_active_id zxmod_active_source zxmod_active_identity; do
        [ -n "$zxmod_active_id" ] || continue
        zxmod_path_exists "$ZXMOD_RUN_ROOT/modules/$zxmod_active_id/root/$zxmod_relative" &&
            zxmod_die "module path conflicts with active module $zxmod_active_id: /$zxmod_relative"
    done < "$zxmod_active_file"
}

zxmod_validate_path_tree() (
    zxmod_walk_directory=$1
    zxmod_walk_root=$2
    zxmod_walk_active_file=$3

    for zxmod_walk_path in \
        "$zxmod_walk_directory"/* \
        "$zxmod_walk_directory"/.[!.]* \
        "$zxmod_walk_directory"/..?*; do
        zxmod_path_exists "$zxmod_walk_path" || continue
        zxmod_validate_one_path \
            "$zxmod_walk_path" \
            "$zxmod_walk_root" \
            "$zxmod_walk_active_file"
        if [ -d "$zxmod_walk_path" ] && [ ! -L "$zxmod_walk_path" ]; then
            zxmod_validate_path_tree \
                "$zxmod_walk_path" \
                "$zxmod_walk_root" \
                "$zxmod_walk_active_file"
        fi
    done
)

zxmod_validate_paths() {
    zxmod_validate_path_tree "$1/root" "$1" "$2"
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
    while IFS="$ZXMOD_TAB" read -r zxmod_active_id zxmod_active_source zxmod_active_identity; do
        [ -n "$zxmod_active_id" ] || continue
        [ "$(zxmod_source_identity "$zxmod_active_source")" = "$zxmod_active_identity" ] ||
            zxmod_die "active module source changed: $zxmod_active_id"
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

zxmod_persist_root() {
    [ -f "$ZXMOD_CONFIG" ] ||
        zxmod_die "persistent store is not configured; set persist_root in $ZXMOD_CONFIG"
    zxmod_persist_count=$(awk -F= '$1 == "persist_root" { count++ } END { print count + 0 }' "$ZXMOD_CONFIG")
    [ "$zxmod_persist_count" -eq 1 ] || zxmod_die 'persistent store configuration is invalid'
    zxmod_persist_root=$(awk -F= '$1 == "persist_root" { sub(/^[^=]*=/, ""); print; exit }' "$ZXMOD_CONFIG")
    case $zxmod_persist_root in /*) ;; *) zxmod_die 'persistent store must be an absolute path' ;; esac
    [ -d "$zxmod_persist_root" ] && [ -w "$zxmod_persist_root" ] ||
        zxmod_die "persistent store is unavailable: $zxmod_persist_root"
    mountpoint -q "$zxmod_persist_root" ||
        zxmod_die "persistent store is not a mount point: $zxmod_persist_root"
    case $(findmnt -no FSTYPE --target "$zxmod_persist_root") in
        tmpfs|ramfs|rootfs|'')
            zxmod_die "persistent store is not external writable media: $zxmod_persist_root"
            ;;
    esac
}
