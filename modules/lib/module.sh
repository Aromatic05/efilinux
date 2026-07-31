#!/usr/bin/env bash

set -euo pipefail

MODULE_LIBRARY_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
EFILINUX_ROOT=$(cd -- "$MODULE_LIBRARY_DIR/../.." && pwd)
source "$EFILINUX_ROOT/config.sh"
source "$EFILINUX_ROOT/lib/common.sh"
source "$EFILINUX_ROOT/lib/package.sh"
source "$EFILINUX_ROOT/lib/composer.sh"

module_validate_name() {
    local name=$1
    [[ $name =~ ^[0-9]{3}-[a-z0-9][a-z0-9-]*$ ]] ||
        die "module directory must use the 00x-name convention: $name"
}

module_validate_id() {
    local id=$1
    [[ $id =~ ^[a-z0-9][a-z0-9._-]*$ && ${#id} -le 64 ]] ||
        die "invalid module id: $id"
}

module_resolve_profile() {
    local profile=$1

    declare -gA COMPOSE_VISIT_STATE=()
    declare -gA COMPOSE_ARCHIVES=()
    declare -ga COMPOSE_ORDER=()
    compose_read_profile "$profile"
}

module_archive_version() {
    local archive=$1
    tar --extract --to-stdout --file "$archive" .PKGINFO |
        sed -n 's/^version=//p' |
        head -n 1
}

module_validate_base_path() {
    local package=$1
    local subset=$2
    local install_path=$3
    local source target source_type target_type

    compose_validate_path "$install_path"
    case $install_path in
        /usr|/usr/*|/opt|/opt/*) ;;
        *) die "module package $package installs outside /usr or /opt: $install_path" ;;
    esac
    case $install_path in
        */gschemas.compiled|*/giomodule.cache|*/loaders.cache|*/mimeinfo.cache|*/icon-theme.cache)
            die "module package $package ships a generated cache: $install_path"
            ;;
    esac

    source="$subset$install_path"
    target="$EFILINUX_ROOTFS$install_path"
    [[ -e "$source" || -L "$source" ]] ||
        die "module package $package is missing its install path: $install_path"
    [[ -e "$target" || -L "$target" ]] || return 0

    source_type=$(compose_path_type "$source")
    target_type=$(compose_path_type "$target")
    if [[ $source_type == directory && $target_type == directory ]]; then
        return 0
    fi
    die "module package $package conflicts with the base system at $install_path"
}

module_compose() {
    local module_directory=$1
    local module_name base_profile work stage owners package archive subset list
    local package_version output temporary size included=0
    local -a module_order=()
    local -A base_packages=() module_archives=()

    module_name=$(basename -- "$module_directory")
    module_validate_name "$module_name"
    module_validate_id "$module_id"
    [[ -n ${module_version:-} ]] || die "module version is empty: $module_name"
    [[ -f "$module_profile" ]] || die "module package profile is missing: $module_profile"
    [[ -d "$EFILINUX_ROOTFS" ]] || die "base rootfs is missing; build EFI Linux before modules"
    [[ -f "$EFILINUX_ROOTFS_OWNERS" ]] || die "base rootfs ownership manifest is missing"

    base_profile="$EFILINUX_ROOT/profiles/efilinux.packages"
    module_resolve_profile "$base_profile"
    for package in "${COMPOSE_ORDER[@]}"; do
        base_packages[$package]=1
    done

    module_resolve_profile "$module_profile"
    module_order=("${COMPOSE_ORDER[@]}")
    for package in "${module_order[@]}"; do
        module_archives[$package]=${COMPOSE_ARCHIVES[$package]}
    done

    work="$EFILINUX_BUILD/modules/$module_name"
    stage="$work/root"
    owners="$work/owners.tsv"
    reset_directory "$work"
    mkdir -p "$stage"
    printf 'path\ttype\towner\n' > "$owners"

    for package in "${module_order[@]}"; do
        [[ -z ${base_packages[$package]:-} ]] || continue
        archive=${module_archives[$package]}
        subset="$work/packages/$package"
        list="$work/$package.install"
        package_materialize "$package" "$subset"
        tar --extract --to-stdout --file "$archive" .INSTALL > "$list"
        while IFS= read -r install_path; do
            [[ -n "$install_path" ]] || continue
            module_validate_base_path "$package" "$subset" "$install_path"
        done < "$list"
        compose_validate_package_subset "$package" "$subset" "$stage" "$owners" "$list"
        compose_merge_subset "$subset" "$stage"
        included=$((included + 1))
    done
    (( included > 0 )) || die "module $module_name contains no packages outside the base EFI"

    install -d -m0755 "$stage/opt/efilinux/modules/$module_id"
    {
        printf 'package\tversion\n'
        for package in "${module_order[@]}"; do
            [[ -z ${base_packages[$package]:-} ]] || continue
            package_version=$(module_archive_version "${module_archives[$package]}")
            printf '%s\t%s\n' "$package" "$package_version"
        done
    } > "$stage/opt/efilinux/modules/$module_id/packages.tsv"

    mkdir -p "$EFILINUX_TARGET/modules"
    output="$EFILINUX_TARGET/modules/$module_name.zxm"
    temporary="$EFILINUX_TARGET/modules/$module_name.tmp.$$.zxm"
    rm -f -- "$temporary"
    "$EFILINUX_ROOT/005-utils/zxmod/files/usr/bin/zxmod-build" \
        --id "$module_id" \
        --version "$module_version" \
        --arch "$EFILINUX_ARCH" \
        --description "$module_description" \
        "$stage" "$temporary"
    mv -f -- "$temporary" "$output"

    size=$(stat -c %s "$output")
    if [[ -n ${module_max_size:-} ]] && (( size > module_max_size )); then
        die "module $module_name exceeds its size budget: $size > $module_max_size"
    fi
    log "Built $module_name.zxm ($size bytes, $included module-only packages)"
}

module_main() {
    local module_directory

    module_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[1]}")" && pwd)
    module_profile=${module_profile:-$module_directory/module.packages}
    case ${1:-} in
        '')
            for component in "${module_components[@]:-}"; do
                run_component "$module_directory/$component"
            done
            ;;
        --module-only)
            [[ $# == 1 ]] || die "usage: ${BASH_SOURCE[1]} [--module-only]"
            ;;
        *) die "usage: ${BASH_SOURCE[1]} [--module-only]" ;;
    esac
    module_compose "$module_directory"
}
