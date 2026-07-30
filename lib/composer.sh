#!/usr/bin/env bash

set -euo pipefail

compose_validate_package_name() {
    local name=$1
    [[ $name =~ ^[a-z0-9][a-z0-9+._-]*$ ]] || die "invalid package name: $name"
}

compose_validate_path() {
    local path=$1
    [[ $path == /* && $path != / ]] || die "invalid package install path: $path"
    [[ $path != *//* && $path != */./* && $path != */. && \
       $path != */../* && $path != */.. && $path != *[$'\t\r\n']* ]] || \
        die "unsafe package install path: $path"
}

compose_archive_dependencies() {
    local archive=$1
    tar --extract --to-stdout --file "$archive" .PKGINFO | \
        sed -n 's/^depends=//p'
}

compose_resolve_package() {
    local name=$1
    local state archive dependency

    compose_validate_package_name "$name"
    state=${COMPOSE_VISIT_STATE[$name]:-unseen}
    case $state in
        done) return ;;
        visiting) die "runtime dependency cycle detected at $name" ;;
    esac

    COMPOSE_VISIT_STATE[$name]=visiting
    archive=$(package_current_archive "$name")
    COMPOSE_ARCHIVES[$name]=$archive
    while IFS= read -r dependency; do
        [[ -n "$dependency" ]] || continue
        compose_resolve_package "$dependency"
    done < <(compose_archive_dependencies "$archive")
    COMPOSE_VISIT_STATE[$name]=done
    COMPOSE_ORDER+=("$name")
}

compose_read_profile() {
    local profile=$1
    local line package extra

    [[ -f "$profile" ]] || die "package profile is missing: $profile"
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=${line%%#*}
        read -r package extra <<<"$line"
        [[ -n ${package:-} ]] || continue
        [[ -z ${extra:-} ]] || die "profile line contains multiple fields: $line"
        compose_resolve_package "$package"
    done < "$profile"
    ((${#COMPOSE_ORDER[@]} > 0)) || die "package profile is empty: $profile"
}

compose_path_type() {
    local path=$1
    if [[ -L "$path" ]]; then
        printf symlink
    elif [[ -d "$path" ]]; then
        printf directory
    elif [[ -f "$path" ]]; then
        printf file
    elif [[ -b "$path" ]]; then
        printf block
    elif [[ -c "$path" ]]; then
        printf character
    elif [[ -p "$path" ]]; then
        printf fifo
    elif [[ -S "$path" ]]; then
        printf socket
    else
        die "unsupported package path type: $path"
    fi
}

compose_validate_ancestors() {
    local rootfs=$1
    local install_path=$2
    local relative=${install_path#/}
    local component current=
    local -a components=()

    IFS=/ read -r -a components <<<"$relative"
    for component in "${components[@]:0:${#components[@]}-1}"; do
        current=${current:+$current/}$component
        if [[ -L "$rootfs/$current" ]]; then
            die "package path traverses an installed symbolic link: /$current"
        fi
        if [[ -e "$rootfs/$current" && ! -d "$rootfs/$current" ]]; then
            die "package path traverses a non-directory: /$current"
        fi
    done
}

compose_validate_package_subset() {
    local package=$1
    local subset=$2
    local rootfs=$3
    local owners=$4
    local list=$5
    local install_path source target source_type target_type source_stat target_stat

    while IFS= read -r install_path; do
        [[ -n "$install_path" ]] || continue
        compose_validate_path "$install_path"
        source="$subset${install_path}"
        target="$rootfs${install_path}"
        [[ -e "$source" || -L "$source" ]] || \
            die "$package install path is absent from materialized package: $install_path"
        compose_validate_ancestors "$rootfs" "$install_path"
        source_type=$(compose_path_type "$source")

        if [[ -e "$target" || -L "$target" ]]; then
            target_type=$(compose_path_type "$target")
            if [[ "$source_type" != directory || "$target_type" != directory ]]; then
                die "package file conflict at $install_path: $package conflicts with an existing $target_type"
            fi
            source_stat=$(LC_ALL=C stat -c '%a|%u|%g' -- "$source")
            target_stat=$(LC_ALL=C stat -c '%a|%u|%g' -- "$target")
            [[ "$source_stat" == "$target_stat" ]] || \
                die "shared directory metadata conflict at $install_path: $source_stat != $target_stat"
        fi
        printf '%s\t%s\t%s\n' "$install_path" "$source_type" "$package" >> "$owners"
    done < "$list"
}

compose_merge_subset() {
    local subset=$1
    local rootfs=$2
    tar --create --file - --numeric-owner --directory "$subset" . | \
        tar --extract --file - --numeric-owner --same-owner --directory "$rootfs"
}

compose_run_target() {
    local rootfs=$1
    shift
    local loader="$rootfs/usr/lib/ld-linux-x86-64.so.2"

    [[ -x "$loader" ]] || die "target dynamic loader is missing: /usr/lib/ld-linux-x86-64.so.2"
    env -u LD_PRELOAD -u LD_LIBRARY_PATH \
        "$loader" --library-path "$rootfs/usr/lib" "$@"
}

compose_finalize_rootfs() {
    local rootfs=$1
    local owners=$2
    local schemas="$rootfs/usr/share/glib-2.0/schemas"
    local modules="$rootfs/usr/lib/gio/modules"

    if [[ -d "$schemas" ]]; then
        [[ -x "$rootfs/usr/bin/glib-compile-schemas" ]] || \
            die "GSettings schemas are installed without glib-compile-schemas"
        compose_run_target "$rootfs" \
            "$rootfs/usr/bin/glib-compile-schemas" "$schemas"
        [[ -f "$schemas/gschemas.compiled" ]] || die "GSettings schema cache was not generated"
        chown 0:0 "$schemas/gschemas.compiled"
        chmod 0644 "$schemas/gschemas.compiled"
        printf '/usr/share/glib-2.0/schemas/gschemas.compiled\tfile\t@composer\n' >> "$owners"
    fi

    if [[ -d "$modules" ]]; then
        [[ -x "$rootfs/usr/bin/gio-querymodules" ]] || \
            die "GIO modules are installed without gio-querymodules"
        compose_run_target "$rootfs" "$rootfs/usr/bin/gio-querymodules" "$modules"
        if [[ -f "$modules/giomodule.cache" ]]; then
            chown 0:0 "$modules/giomodule.cache"
            chmod 0644 "$modules/giomodule.cache"
            printf '/usr/lib/gio/modules/giomodule.cache\tfile\t@composer\n' >> "$owners"
        fi
    fi
}

compose_profile() {
    local profile=$1
    local work rootfs owners sorted_owners package archive subset list

    declare -gA COMPOSE_VISIT_STATE=()
    declare -gA COMPOSE_ARCHIVES=()
    declare -ga COMPOSE_ORDER=()
    compose_read_profile "$profile"

    work="$EFILINUX_BUILD/compose-$(basename -- "$profile")-$$"
    rootfs="$work/rootfs"
    owners="$work/owners.tsv"
    sorted_owners="$work/owners.sorted.tsv"
    reset_directory "$work"
    mkdir -p "$rootfs"
    printf 'path\ttype\towner\n' > "$owners"

    for package in "${COMPOSE_ORDER[@]}"; do
        archive=${COMPOSE_ARCHIVES[$package]}
        subset="$work/packages/$package"
        list="$work/$package.install"
        package_materialize "$package" "$subset"
        tar --extract --to-stdout --file "$archive" .INSTALL > "$list"
        compose_validate_package_subset "$package" "$subset" "$rootfs" "$owners" "$list"
        compose_merge_subset "$subset" "$rootfs"
    done

    compose_finalize_rootfs "$rootfs" "$owners"
    {
        printf 'path\ttype\towner\n'
        tail -n +2 "$owners" | LC_ALL=C sort -t $'\t' -k1,1 -k3,3
    } > "$sorted_owners"
    mv -- "$sorted_owners" "$owners"

    rm -rf -- "$EFILINUX_ROOTFS"
    mkdir -p "$(dirname -- "$EFILINUX_ROOTFS")" "$(dirname -- "$EFILINUX_ROOTFS_OWNERS")"
    mv -- "$rootfs" "$EFILINUX_ROOTFS"
    mv -- "$owners" "$EFILINUX_ROOTFS_OWNERS"
    rm -rf -- "$work"
    log "Composed $(basename -- "$profile") into $EFILINUX_ROOTFS"
}
