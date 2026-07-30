#!/bin/sh

ZXMOD_RUN_ROOT=${ZXMOD_RUN_ROOT:-/run/zxmod}
ZXMOD_USR_TARGET=${ZXMOD_USR_TARGET:-/usr}
ZXMOD_OPT_TARGET=${ZXMOD_OPT_TARGET:-/opt}
ZXMOD_CONFIG=${ZXMOD_CONFIG:-/etc/zxmod.conf}

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

zxmod_source_identity() {
    stat -c '%d:%i:%s:%Y' -- "$1"
}

zxmod_validate_id() {
    case $1 in
        [a-z0-9][a-z0-9._-]* )
            [ ${#1} -le 64 ] || zxmod_die "module id is too long: $1"
            ;;
        *) zxmod_die "invalid module id: $1" ;;
    esac
}

zxmod_manifest_value() {
    sed -n "s/^$1=//p" "$2"
}

zxmod_read_manifest() {
    zxmod_source=$1
    zxmod_manifest=$2

    unsquashfs -cat "$zxmod_source" metadata/manifest > "$zxmod_manifest" 2>/dev/null ||
        zxmod_die 'module does not contain metadata/manifest'
    grep -q '^format=1$' "$zxmod_manifest" ||
        zxmod_die 'unsupported module format'
    zxmod_id=$(zxmod_manifest_value id "$zxmod_manifest")
    zxmod_arch=$(zxmod_manifest_value arch "$zxmod_manifest")
    zxmod_version=$(zxmod_manifest_value version "$zxmod_manifest")
    [ "$(grep -c '^id=' "$zxmod_manifest")" -eq 1 ] || zxmod_die 'manifest has duplicate or missing id'
    [ "$(grep -c '^arch=' "$zxmod_manifest")" -eq 1 ] || zxmod_die 'manifest has duplicate or missing arch'
    [ "$(grep -c '^version=' "$zxmod_manifest")" -eq 1 ] || zxmod_die 'manifest has duplicate or missing version'
    zxmod_validate_id "$zxmod_id"
    [ "$zxmod_arch" = "$(uname -m)" ] ||
        zxmod_die "module architecture $zxmod_arch does not match $(uname -m)"
    case $zxmod_version in
        ''|*[!A-Za-z0-9._+:-]*) zxmod_die 'invalid module version' ;;
    esac
    unsquashfs -s "$zxmod_source" 2>/dev/null | grep -Eq '^Compression[[:space:]]+zstd$' ||
        zxmod_die 'module payload is not Zstd-compressed SquashFS'
}

zxmod_prepare_runtime() {
    mkdir -p "$ZXMOD_RUN_ROOT/modules" "$ZXMOD_RUN_ROOT/generations" "$ZXMOD_RUN_ROOT/base"
    [ -e "$ZXMOD_RUN_ROOT/active" ] || : > "$ZXMOD_RUN_ROOT/active"
    if ! mountpoint -q "$ZXMOD_RUN_ROOT/base/usr"; then
        mkdir -p "$ZXMOD_RUN_ROOT/base/usr" "$ZXMOD_RUN_ROOT/base/opt"
        mount --bind "$ZXMOD_USR_TARGET" "$ZXMOD_RUN_ROOT/base/usr"
        mount --bind "$ZXMOD_OPT_TARGET" "$ZXMOD_RUN_ROOT/base/opt"
    fi
}

zxmod_validate_payload_tree() {
    zxmod_root=$1
    for zxmod_top in "$zxmod_root"/*; do
        [ -e "$zxmod_top" ] || [ -L "$zxmod_top" ] || continue
        case $(basename -- "$zxmod_top") in
            metadata|root) ;;
            *) zxmod_die "unexpected top-level module path: $(basename -- "$zxmod_top")" ;;
        esac
    done
    [ -d "$zxmod_root/root" ] || zxmod_die 'module payload root is missing'
    for zxmod_top in "$zxmod_root/root"/*; do
        [ -e "$zxmod_top" ] || [ -L "$zxmod_top" ] || continue
        case $(basename -- "$zxmod_top") in
            usr|opt) [ -d "$zxmod_top" ] && [ ! -L "$zxmod_top" ] || zxmod_die 'payload /usr or /opt is not a directory' ;;
            *) zxmod_die "payload is outside /usr and /opt: $(basename -- "$zxmod_top")" ;;
        esac
    done
}

zxmod_validate_paths() {
    zxmod_root=$1
    zxmod_id=$2
    find "$zxmod_root/root" -mindepth 1 -print | while IFS= read -r zxmod_path; do
        zxmod_relative=${zxmod_path#"$zxmod_root/root/"}
        case $zxmod_relative in
            usr|opt) continue ;;
            usr/*|opt/*) ;;
            *) zxmod_die "unsafe payload path: $zxmod_relative" ;;
        esac
        case $zxmod_relative in
            *'//'|*'/./'*|*'/../'*|*'/..'|*'/'|*"$(printf '\n')"*)
                zxmod_die "unsafe payload path: $zxmod_relative" ;;
        esac
        zxmod_base="$ZXMOD_RUN_ROOT/base/$zxmod_relative"
        if [ -d "$zxmod_path" ] && [ ! -L "$zxmod_path" ]; then
            if zxmod_path_exists "$zxmod_base" && { [ ! -d "$zxmod_base" ] || [ -L "$zxmod_base" ]; }; then
                zxmod_die "module directory conflicts with base system: /$zxmod_relative"
            fi
            continue
        fi
        zxmod_path_exists "$zxmod_base" && zxmod_die "module path conflicts with base system: /$zxmod_relative"
        while IFS='\t' read -r zxmod_active_id zxmod_active_source zxmod_active_identity; do
            [ -n "$zxmod_active_id" ] || continue
            zxmod_path_exists "$ZXMOD_RUN_ROOT/modules/$zxmod_active_id/root/$zxmod_relative" &&
                zxmod_die "module path conflicts with active module $zxmod_active_id: /$zxmod_relative"
        done < "$ZXMOD_RUN_ROOT/active"
    done
}

zxmod_next_generation() {
    zxmod_generation=0
    for zxmod_path in "$ZXMOD_RUN_ROOT/generations"/*; do
        [ -d "$zxmod_path" ] || continue
        zxmod_number=${zxmod_path##*/}
        [ "$zxmod_number" -gt "$zxmod_generation" ] 2>/dev/null && zxmod_generation=$zxmod_number
    done
    zxmod_generation=$((zxmod_generation + 1))
}

zxmod_switch_generation() {
    zxmod_next_generation
    zxmod_generation_root="$ZXMOD_RUN_ROOT/generations/$zxmod_generation"
    mkdir -p "$zxmod_generation_root/usr/upper" "$zxmod_generation_root/usr/work" \
        "$zxmod_generation_root/opt/upper" "$zxmod_generation_root/opt/work"
    zxmod_usr_lower="$ZXMOD_RUN_ROOT/base/usr"
    zxmod_opt_lower="$ZXMOD_RUN_ROOT/base/opt"
    while IFS='\t' read -r zxmod_active_id zxmod_active_source zxmod_active_identity; do
        [ -n "$zxmod_active_id" ] || continue
        [ "$(zxmod_source_identity "$zxmod_active_source")" = "$zxmod_active_identity" ] ||
            zxmod_die "active module source changed: $zxmod_active_id"
        [ -d "$ZXMOD_RUN_ROOT/modules/$zxmod_active_id/root/usr" ] &&
            zxmod_usr_lower="$ZXMOD_RUN_ROOT/modules/$zxmod_active_id/root/usr:$zxmod_usr_lower"
        [ -d "$ZXMOD_RUN_ROOT/modules/$zxmod_active_id/root/opt" ] &&
            zxmod_opt_lower="$ZXMOD_RUN_ROOT/modules/$zxmod_active_id/root/opt:$zxmod_opt_lower"
    done < "$ZXMOD_RUN_ROOT/active"
    mount -t overlay overlay -o "lowerdir=$zxmod_usr_lower,upperdir=$zxmod_generation_root/usr/upper,workdir=$zxmod_generation_root/usr/work" "$zxmod_generation_root/usr"
    mount -t overlay overlay -o "lowerdir=$zxmod_opt_lower,upperdir=$zxmod_generation_root/opt/upper,workdir=$zxmod_generation_root/opt/work" "$zxmod_generation_root/opt"
    mount --bind "$zxmod_generation_root/usr" "$ZXMOD_USR_TARGET"
    mount --bind "$zxmod_generation_root/opt" "$ZXMOD_OPT_TARGET"
    printf '%s\n' "$zxmod_generation" > "$ZXMOD_RUN_ROOT/current-generation"
}

zxmod_persist_root() {
    [ -f "$ZXMOD_CONFIG" ] || zxmod_die "persistent store is not configured; set persist_root in $ZXMOD_CONFIG"
    zxmod_persist_root=$(sed -n 's/^persist_root=//p' "$ZXMOD_CONFIG")
    [ "$(grep -c '^persist_root=' "$ZXMOD_CONFIG")" -eq 1 ] || zxmod_die 'persistent store configuration is invalid'
    [ -n "$zxmod_persist_root" ] && [ -d "$zxmod_persist_root" ] && [ -w "$zxmod_persist_root" ] ||
        zxmod_die "persistent store is unavailable: $zxmod_persist_root"
    mountpoint -q "$zxmod_persist_root" || zxmod_die "persistent store is not a mount point: $zxmod_persist_root"
    case $(findmnt -no FSTYPE --target "$zxmod_persist_root") in
        tmpfs|ramfs|rootfs|'') zxmod_die "persistent store is not external writable media: $zxmod_persist_root" ;;
    esac
}
