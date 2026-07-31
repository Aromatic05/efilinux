#!/usr/bin/env bash

set -euo pipefail

MODULE_LIBRARY_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
EFILINUX_ROOT=$(cd -- "$MODULE_LIBRARY_DIR/../.." && pwd)
source "$EFILINUX_ROOT/config.sh"
source "$EFILINUX_ROOT/lib/common.sh"
source "$EFILINUX_ROOT/lib/package.sh"
source "$EFILINUX_ROOT/lib/composer.sh"

readonly MODULE_BASE_PACKAGES=$EFILINUX_PACKAGES
readonly MODULE_BASE_PACKAGE_INDEX=$EFILINUX_PACKAGE_INDEX
readonly MODULE_BASE_SYSROOT=$EFILINUX_SYSROOT
readonly MODULE_BASE_ROOTFS=$EFILINUX_ROOTFS
readonly MODULE_BASE_ROOTFS_OWNERS=$EFILINUX_ROOTFS_OWNERS

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

module_index_record() {
    local index=$1
    local name=$2

    [[ -f "$index" ]] || return 1
    awk -F '\t' -v name="$name" '
        NR > 1 && $1 == name { print; found=1; exit }
        END { exit(found ? 0 : 1) }
    ' "$index"
}

module_record_archive() {
    local packages=$1
    local record=$2
    local name version recipe_key content_hash archive_name digest archive

    IFS=$'\t' read -r name version recipe_key content_hash archive_name digest <<<"$record"
    [[ -n "$name" && -n "$archive_name" && -n "$digest" ]] ||
        die "incomplete package record for $name"
    archive="$packages/$archive_name"
    package_verify_archive "$archive" "$name" "$version" "$recipe_key" "$digest"
    printf '%s' "$archive"
}

module_lookup_package() {
    local name=$1
    local record

    if record=$(module_index_record "$EFILINUX_PACKAGE_INDEX" "$name"); then
        MODULE_LOOKUP_ORIGIN=module
        MODULE_LOOKUP_ARCHIVE=$(module_record_archive "$EFILINUX_PACKAGES" "$record")
        return
    fi
    if record=$(module_index_record "$MODULE_BASE_PACKAGE_INDEX" "$name"); then
        MODULE_LOOKUP_ORIGIN=base
        MODULE_LOOKUP_ARCHIVE=$(module_record_archive "$MODULE_BASE_PACKAGES" "$record")
        return
    fi
    die "module package dependency is unavailable in this module or the base EFI: $name"
}

module_resolve_package() {
    local name=$1
    local state dependency

    compose_validate_package_name "$name"
    state=${MODULE_VISIT_STATE[$name]:-unseen}
    case $state in
        done) return ;;
        visiting) die "module runtime dependency cycle detected at $name" ;;
    esac

    MODULE_VISIT_STATE[$name]=visiting
    module_lookup_package "$name"
    MODULE_ARCHIVES[$name]=$MODULE_LOOKUP_ARCHIVE
    MODULE_ORIGINS[$name]=$MODULE_LOOKUP_ORIGIN
    while IFS= read -r dependency; do
        [[ -n "$dependency" ]] || continue
        module_resolve_package "$dependency"
    done < <(compose_archive_dependencies "$MODULE_LOOKUP_ARCHIVE")
    MODULE_VISIT_STATE[$name]=done
    MODULE_ORDER+=("$name")
}

module_resolve_profile() {
    local profile=$1
    local line package extra

    [[ -f "$profile" ]] || die "module package profile is missing: $profile"
    declare -gA MODULE_VISIT_STATE=()
    declare -gA MODULE_ARCHIVES=()
    declare -gA MODULE_ORIGINS=()
    declare -ga MODULE_ORDER=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        line=${line%%#*}
        read -r package extra <<<"$line"
        [[ -n ${package:-} ]] || continue
        [[ -z ${extra:-} ]] || die "module profile line contains multiple fields: $line"
        module_resolve_package "$package"
        [[ ${MODULE_ORIGINS[$package]} == module ]] ||
            die "module profile root must be built by this module: $package"
    done < "$profile"
    ((${#MODULE_ORDER[@]} > 0)) || die "module package profile is empty: $profile"
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
    target="$MODULE_BASE_ROOTFS$install_path"
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

module_initialize_workspace() {
    local module_directory=$1
    local module_build="$module_directory/build"

    export EFILINUX_BUILD="$module_build"
    export EFILINUX_PACKAGES="$module_build/packages"
    export EFILINUX_PACKAGE_INDEX="$EFILINUX_PACKAGES/index.tsv"
    export EFILINUX_SYSROOT="$module_build/sysroot"
    export EFILINUX_LOGS="$module_build/logs"
    export EFILINUX_STATE="$module_build/state"
    export EFILINUX_TEST="$module_build/test"
    export EFILINUX_PACKAGE_WORK="$module_build/work/packages"
    export EFILINUX_ROOTFS="$MODULE_BASE_ROOTFS"
    export EFILINUX_ROOTFS_OWNERS="$MODULE_BASE_ROOTFS_OWNERS"

    mkdir -p \
        "$EFILINUX_BUILD/recipes" \
        "$EFILINUX_PACKAGES" \
        "$EFILINUX_LOGS" \
        "$EFILINUX_STATE" \
        "$EFILINUX_TEST" \
        "$EFILINUX_PACKAGE_WORK" \
        "$module_build/output"
    package_assert_current_index

    [[ -d "$MODULE_BASE_SYSROOT" ]] ||
        die "base EFI sysroot is missing; build EFI Linux before modules"
    reset_directory "$EFILINUX_SYSROOT"
    cp -a --reflink=auto "$MODULE_BASE_SYSROOT/." "$EFILINUX_SYSROOT/"
}

module_component_dependencies() {
    local metadata=$1
    python3 -c '
import json, sys
metadata = json.load(sys.stdin)
for kind in ("depends", "builddepends"):
    for dependency in metadata[kind]:
        print(dependency)
' <<<"$metadata"
}

module_validate_component_dependency() {
    local component=$1
    local dependency=$2

    if [[ -n ${MODULE_COMPONENT_SET[$dependency]:-} ]]; then
        [[ -n ${MODULE_COMPONENT_BUILT[$dependency]:-} ]] ||
            die "module component $component depends on later component $dependency"
        return
    fi
    module_index_record "$MODULE_BASE_PACKAGE_INDEX" "$dependency" >/dev/null ||
        die "module component $component depends on unavailable package $dependency; modules cannot depend on other modules"
}

module_build_components() {
    local module_directory=$1
    local component recipe metadata dependency pkgname

    declare -gA MODULE_COMPONENT_SET=()
    declare -gA MODULE_COMPONENT_BUILT=()
    for component in "${module_components[@]:-}"; do
        [[ -z ${MODULE_COMPONENT_SET[$component]:-} ]] ||
            die "duplicate module component: $component"
        MODULE_COMPONENT_SET[$component]=1
    done

    for component in "${module_components[@]:-}"; do
        recipe="$module_directory/$component/build.sh"
        [[ -x "$recipe" ]] || die "module component recipe is missing: $recipe"
        metadata=$("$recipe" --print-metadata)
        pkgname=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["pkgname"])' <<<"$metadata")
        [[ $pkgname == "$component" ]] ||
            die "module component directory and package name differ: $component != $pkgname"
        while IFS= read -r dependency; do
            [[ -n "$dependency" ]] || continue
            module_validate_component_dependency "$component" "$dependency"
        done < <(module_component_dependencies "$metadata")
        run_component "$module_directory/$component" --no-deps
        MODULE_COMPONENT_BUILT[$component]=1
    done
}

module_compose() {
    local module_directory=$1
    local module_name work stage owners package archive subset list
    local package_version output temporary size included=0

    module_name=$(basename -- "$module_directory")
    module_validate_name "$module_name"
    module_validate_id "$module_id"
    [[ -n ${module_version:-} ]] || die "module version is empty: $module_name"
    [[ -d "$MODULE_BASE_ROOTFS" ]] || die "base rootfs is missing; build EFI Linux before modules"
    [[ -f "$MODULE_BASE_ROOTFS_OWNERS" ]] || die "base rootfs ownership manifest is missing"

    module_resolve_profile "$module_profile"
    work="$EFILINUX_BUILD/work/compose"
    stage="$work/root"
    owners="$work/owners.tsv"
    reset_directory "$work"
    mkdir -p "$stage"
    printf 'path\ttype\towner\n' > "$owners"

    for package in "${MODULE_ORDER[@]}"; do
        [[ ${MODULE_ORIGINS[$package]} == module ]] || continue
        archive=${MODULE_ARCHIVES[$package]}
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
        for package in "${MODULE_ORDER[@]}"; do
            [[ ${MODULE_ORIGINS[$package]} == module ]] || continue
            package_version=$(module_archive_version "${MODULE_ARCHIVES[$package]}")
            printf '%s\t%s\n' "$package" "$package_version"
        done
    } > "$stage/opt/efilinux/modules/$module_id/packages.tsv"

    output="$EFILINUX_BUILD/output/$module_name.zxm"
    temporary="$EFILINUX_BUILD/output/$module_name.tmp.$$.zxm"
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
    log "Built $output ($size bytes, $included module-local packages)"
}

module_main() {
    local module_directory

    module_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[1]}")" && pwd)
    module_profile=${module_profile:-$module_directory/module.packages}
    module_initialize_workspace "$module_directory"
    case ${1:-} in
        '')
            module_build_components "$module_directory"
            ;;
        --module-only)
            [[ $# == 1 ]] || die "usage: ${BASH_SOURCE[1]} [--module-only]"
            ;;
        *) die "usage: ${BASH_SOURCE[1]} [--module-only]" ;;
    esac
    module_compose "$module_directory"
}
