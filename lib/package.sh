#!/usr/bin/env bash

set -euo pipefail

target_cflags() {
    printf '%s' "-O2 -march=$EFILINUX_X86_64_LEVEL -mtune=generic --sysroot=$EFILINUX_SYSROOT"
}

target_ldflags() {
    printf '%s' "-B$EFILINUX_SYSROOT/usr/lib/ --sysroot=$EFILINUX_SYSROOT -Wl,-rpath-link,$EFILINUX_SYSROOT/usr/lib"
}

target_pkg_config() {
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        pkg-config "$@"
}

prepare_package() {
    local package=$1

    PACKAGE_SOURCE="$EFILINUX_BUILD/sources/$package"
    PACKAGE_BUILD="$EFILINUX_BUILD/$package"
    PACKAGE_STAGING="$EFILINUX_BUILD/staging/$package"
    reset_directory "$PACKAGE_SOURCE"
    reset_directory "$PACKAGE_BUILD"
    reset_directory "$PACKAGE_STAGING"
}

merge_sysroot() {
    local staging=$1
    cp -a --remove-destination "$staging/." "$EFILINUX_SYSROOT/"
}

remove_rootfs_owner() {
    local relative_path=$1
    local temporary="$EFILINUX_ROOTFS_OWNERS.tmp"

    [[ -f "$EFILINUX_ROOTFS_OWNERS" ]] || return
    awk -F '\t' -v path="$relative_path" '$1 != path' \
        "$EFILINUX_ROOTFS_OWNERS" > "$temporary"
    mv "$temporary" "$EFILINUX_ROOTFS_OWNERS"
}

record_rootfs_owner() {
    local package=$1
    local relative_path=$2

    mkdir -p "$(dirname -- "$EFILINUX_ROOTFS_OWNERS")"
    touch "$EFILINUX_ROOTFS_OWNERS"
    remove_rootfs_owner "$relative_path"
    printf '%s\t%s\n' "$relative_path" "$package" >> "$EFILINUX_ROOTFS_OWNERS"
}

rootfs_owner() {
    local relative_path=$1
    awk -F '\t' -v path="$relative_path" '$1 == path { owner=$2 } END { print owner }' \
        "$EFILINUX_ROOTFS_OWNERS" 2>/dev/null || true
}

prepare_rootfs_destination() {
    local package=$1
    local relative_path=$2
    local destination="$EFILINUX_ROOTFS$relative_path"
    local owner

    mkdir -p "$(dirname -- "$destination")"
    if [[ ! -e "$destination" && ! -L "$destination" ]]; then
        return
    fi

    if [[ -L "$destination" ]]; then
        case $(readlink -- "$destination") in
            busybox|/usr/bin/busybox)
                rm -f -- "$destination"
                remove_rootfs_owner "$relative_path"
                return
                ;;
        esac
    fi

    owner=$(rootfs_owner "$relative_path")
    die "$package attempted to overwrite $relative_path${owner:+ owned by $owner}"
}

install_rootfs_file() {
    local package=$1
    local source=$2
    local relative_path=$3
    local destination="$EFILINUX_ROOTFS$relative_path"

    [[ -e "$source" || -L "$source" ]] || \
        die "$package runtime file is missing: $source"
    prepare_rootfs_destination "$package" "$relative_path"
    cp -a -- "$source" "$destination"
    record_rootfs_owner "$package" "$relative_path"
}

replace_rootfs_file() {
    local package=$1
    local expected_owner=$2
    local source=$3
    local relative_path=$4
    local destination="$EFILINUX_ROOTFS$relative_path"
    local owner

    owner=$(rootfs_owner "$relative_path")
    [[ "$owner" == "$expected_owner" ]] || \
        die "$package cannot replace $relative_path owned by ${owner:-an untracked source}"
    rm -f -- "$destination"
    remove_rootfs_owner "$relative_path"
    install_rootfs_file "$package" "$source" "$relative_path"
}

install_rootfs_symlink() {
    local package=$1
    local target=$2
    local relative_path=$3
    local destination="$EFILINUX_ROOTFS$relative_path"

    prepare_rootfs_destination "$package" "$relative_path"
    ln -s -- "$target" "$destination"
    record_rootfs_owner "$package" "$relative_path"
}

install_rootfs_program() {
    local package=$1
    local source=$2
    local name=${3:-$(basename -- "$source")}

    install_rootfs_file "$package" "$source" "/usr/bin/$name"
}

install_rootfs_library_family() {
    local package=$1
    local staging=$2
    local pattern=$3
    local file
    local found=false

    shopt -s nullglob
    for file in "$staging/usr/lib"/$pattern; do
        install_rootfs_file "$package" "$file" "/usr/lib/$(basename -- "$file")"
        found=true
    done
    shopt -u nullglob
    [[ "$found" == true ]] || die "$package library family is missing: $pattern"
}

install_rootfs_tree() {
    local package=$1
    local source_root=$2
    local destination_root=$3
    local entry relative relative_path

    [[ -d "$source_root" ]] || die "$package runtime tree is missing: $source_root"
    while IFS= read -r -d '' entry; do
        relative=${entry#"$source_root"/}
        relative_path="$destination_root/$relative"
        if [[ -d "$entry" && ! -L "$entry" ]]; then
            mkdir -p "$EFILINUX_ROOTFS$relative_path"
        else
            install_rootfs_file "$package" "$entry" "$relative_path"
        fi
    done < <(find "$source_root" -mindepth 1 -print0)
}

strip_rootfs_elf() {
    local file

    while IFS= read -r -d '' file; do
        if LC_ALL=C readelf --file-header "$file" >/dev/null 2>&1; then
            strip --strip-unneeded "$file" 2>/dev/null || true
        fi
    done < <(find "$EFILINUX_ROOTFS/usr" -type f -print0)
}
