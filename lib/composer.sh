#!/usr/bin/env bash

set -euo pipefail

readonly COMPOSE_RESOLUTION_CACHE_HEADER='# efilinux-compose-resolution-cache-v1'

compose_validate_package_name() {
    local name=$1
    [[ $name =~ ^[a-z0-9][a-z0-9+._-]*$ ]] || die "invalid package name: $name"
}

compose_resolution_cache_path() {
    local profile=$1
    local profile_directory profile_name profile_identity

    profile_directory=$(cd -- "$(dirname -- "$profile")" && pwd -P)
    profile_name=$(basename -- "$profile")
    profile_identity=$(
        printf '%s/%s' "$profile_directory" "$profile_name" |
            sha256sum |
            awk '{print substr($1, 1, 16)}'
    )
    printf '%s/compose-resolution/%s-%s.cache' \
        "$EFILINUX_STATE" "$profile_name" "$profile_identity"
}

compose_resolution_cache_key() {
    local profile=$1
    local profile_directory profile_file

    package_assert_current_index
    profile_directory=$(cd -- "$(dirname -- "$profile")" && pwd -P)
    {
        printf 'cache=%s\n' "$COMPOSE_RESOLUTION_CACHE_HEADER"
        printf 'package-format=%s\n' "$EFILINUX_PACKAGE_FORMAT"
        printf 'arch=%s\n' "$EFILINUX_ARCH"
        printf 'package-index='
        sha256sum "$EFILINUX_PACKAGE_INDEX" | awk '{print $1}'
        while IFS= read -r -d '' profile_file; do
            printf 'profile=%s\n' "${profile_file#"$profile_directory/"}"
            sha256sum "$profile_file"
        done < <(
            find "$profile_directory" -maxdepth 1 -type f -name '*.packages' \
                -print0 |
                LC_ALL=C sort -z
        )
    } | sha256sum | awk '{print $1}'
}

compose_load_resolution_cache() {
    local profile=$1
    local cache expected_key header key_line name archive_name extra archive index
    local valid=true
    local -a names=() archives=()
    local -A seen=()

    cache=$(compose_resolution_cache_path "$profile")
    [[ -f "$cache" ]] || return 1
    expected_key=$(compose_resolution_cache_key "$profile")

    exec 3< "$cache"
    IFS= read -r header <&3 || valid=false
    IFS= read -r key_line <&3 || valid=false
    [[ $valid == false || "$header" == "$COMPOSE_RESOLUTION_CACHE_HEADER" ]] || \
        valid=false
    [[ $valid == false || "$key_line" == "key=$expected_key" ]] || valid=false

    while [[ $valid == true ]] && \
          IFS=$'\t' read -r name archive_name extra <&3; do
        if [[ -z $name || -z $archive_name || -n ${extra:-} || \
              ! $name =~ ^[a-z0-9][a-z0-9+._-]*$ || \
              $archive_name == */* || $archive_name == *[$'\t\r\n']* || \
              -n ${seen[$name]:-} ]]; then
            valid=false
            break
        fi
        archive="$EFILINUX_PACKAGES/$archive_name"
        if [[ ! -f "$archive" ]]; then
            valid=false
            break
        fi
        seen[$name]=1
        names+=("$name")
        archives+=("$archive")
    done
    exec 3<&-

    if [[ $valid != true ]] || ((${#names[@]} == 0)); then
        rm -f -- "$cache"
        return 1
    fi

    for index in "${!names[@]}"; do
        name=${names[$index]}
        COMPOSE_ARCHIVES[$name]=${archives[$index]}
        COMPOSE_VISIT_STATE[$name]=done
        COMPOSE_ORDER+=("$name")
    done
    log "Using dependency resolution cache for $(basename -- "$profile")"
}

compose_store_resolution_cache() {
    local profile=$1
    local cache temporary key package archive

    cache=$(compose_resolution_cache_path "$profile")
    temporary="$cache.tmp.$$"
    key=$(compose_resolution_cache_key "$profile")
    mkdir -p "$(dirname -- "$cache")"
    {
        printf '%s\n' "$COMPOSE_RESOLUTION_CACHE_HEADER"
        printf 'key=%s\n' "$key"
        for package in "${COMPOSE_ORDER[@]}"; do
            archive=${COMPOSE_ARCHIVES[$package]}
            printf '%s\t%s\n' "$package" "$(basename -- "$archive")"
        done
    } > "$temporary"
    mv -- "$temporary" "$cache"
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

compose_read_profile_file() {
    local profile=$1
    local state line package argument extra include

    [[ -f "$profile" ]] || die "package profile is missing: $profile"
    state=${COMPOSE_PROFILE_STATE[$profile]:-unseen}
    case $state in
        done) return ;;
        visiting) die "package profile include cycle detected at $profile" ;;
    esac
    COMPOSE_PROFILE_STATE[$profile]=visiting

    while IFS= read -r line || [[ -n "$line" ]]; do
        line=${line%%#*}
        read -r package argument extra <<<"$line"
        [[ -n ${package:-} ]] || continue
        if [[ $package == @include ]]; then
            [[ -n ${argument:-} && -z ${extra:-} ]] || \
                die "invalid profile include: $line"
            [[ $argument =~ ^[a-z0-9][a-z0-9._-]*\.packages$ ]] || \
                die "unsafe profile include name: $argument"
            include="$COMPOSE_PROFILE_ROOT/$argument"
            compose_read_profile_file "$include"
            continue
        fi
        [[ -z ${argument:-} && -z ${extra:-} ]] || \
            die "profile line contains multiple fields: $line"
        compose_resolve_package "$package"
    done < "$profile"
    COMPOSE_PROFILE_STATE[$profile]=done
}

compose_read_profile() {
    local profile=$1

    COMPOSE_PROFILE_ROOT=$(cd -- "$(dirname -- "$profile")" && pwd)
    declare -gA COMPOSE_PROFILE_STATE=()
    if compose_load_resolution_cache "$profile"; then
        return
    fi
    compose_read_profile_file "$profile"
    ((${#COMPOSE_ORDER[@]} > 0)) || die "package profile is empty: $profile"
    compose_store_resolution_cache "$profile"
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

compose_package_is_installed() {
    local package=$1
    local owners=$2

    awk -F '\t' -v package="$package" \
        'NR > 1 && $3 == package { found = 1; exit }
         END { exit !found }' "$owners"
}

compose_remove_generated_paths() {
    local rootfs=$1
    local owners=$2
    local filtered="$owners.filtered.$$"
    local depth install_path target

    while IFS=$'\t' read -r depth install_path; do
        [[ -n "$install_path" ]] || continue
        target="$rootfs$install_path"
        if [[ -d "$target" && ! -L "$target" ]]; then
            rmdir -- "$target" 2>/dev/null || true
        else
            rm -f -- "$target"
        fi
    done < <(
        awk -F '\t' 'NR > 1 && $3 == "@composer" {
            depth = gsub(/\//, "/", $1)
            print depth "\t" $1
        }' "$owners" | LC_ALL=C sort -t $'\t' -k1,1nr -k2,2r
    )

    awk -F '\t' 'NR == 1 || $3 != "@composer"' "$owners" > "$filtered"
    mv -- "$filtered" "$owners"
}

compose_write_ownership() {
    local rootfs=$1
    local owners=$2
    local ownership="$rootfs/etc/filemeta/ownership.tsv"

    [[ ! -e "$ownership" && ! -L "$ownership" ]] || \
        die "package content conflicts with composer ownership metadata"
    install -d -m0755 "$rootfs/etc/filemeta"
    {
        printf 'path\ttype\towner\n'
        tail -n +2 "$owners" | LC_ALL=C sort -t $'\t' -k1,1 -k3,3
    } > "$ownership"
    chown 0:0 "$ownership"
    chmod 0644 "$ownership"
    printf '/etc/filemeta/ownership.tsv\tfile\t@composer\n' >> "$owners"
}

compose_record_generated_path() {
    local rootfs=$1
    local owners=$2
    local install_path=$3
    local target="$rootfs$install_path"
    local type

    compose_validate_path "$install_path"
    [[ -e "$target" || -L "$target" ]] || \
        die "composer-generated path is missing: $install_path"
    if awk -F '\t' -v path="$install_path" \
        'NR > 1 && $1 == path { found = 1; exit } END { exit !found }' \
        "$owners"; then
        die "composer-generated path was already owned by a package: $install_path"
    fi
    type=$(compose_path_type "$target")
    printf '%s\t%s\t@composer\n' "$install_path" "$type" >> "$owners"
}

compose_record_unowned_tree() {
    local rootfs=$1
    local owners=$2
    local install_root=$3
    local target_root="$rootfs$install_root"
    local records="$owners.generated.$$"
    local entry install_path type

    compose_validate_path "$install_root"
    [[ -d "$target_root" ]] || die "composer-generated tree is missing: $install_root"
    : > "$records"
    while IFS= read -r -d '' entry; do
        install_path=/${entry#"$rootfs/"}
        type=$(compose_path_type "$entry")
        printf '%s\t%s\n' "$install_path" "$type" >> "$records"
    done < <(find "$target_root" -mindepth 1 -print0 | LC_ALL=C sort -z)

    awk -F '\t' \
        'NR == FNR { if (NR > 1) owned[$1] = 1; next }
         !($1 in owned) { print $1 "\t" $2 "\t@composer" }' \
        "$owners" "$records" >> "$owners"
    rm -f -- "$records"
}

compose_finalize_rootfs() {
    local rootfs=$1
    local owners=$2
    local schemas="$rootfs/usr/share/glib-2.0/schemas"
    local modules="$rootfs/usr/lib/gio/modules"
    local pixbuf_root="$rootfs/usr/lib/gdk-pixbuf-2.0"
    local mime_root="$rootfs/usr/share/mime"
    local applications="$rootfs/usr/share/applications"
    local icons_root="$rootfs/usr/share/icons"
    local loader cache cache_relative theme icon_cache
    local -a loaders=() icon_themes=()

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

    if [[ -d "$pixbuf_root" ]]; then
        mapfile -t loaders < <(
            find "$pixbuf_root" -type f -path '*/loaders/*.so' -print | LC_ALL=C sort
        )
        if ((${#loaders[@]} > 0)); then
            [[ -x "$rootfs/usr/bin/gdk-pixbuf-query-loaders" ]] || \
                die "GdkPixbuf loaders are installed without gdk-pixbuf-query-loaders"
            loader=${loaders[0]}
            cache="$(dirname -- "$(dirname -- "$loader")")/loaders.cache"
            compose_run_target "$rootfs" \
                "$rootfs/usr/bin/gdk-pixbuf-query-loaders" \
                "${loaders[@]}" > "$cache"
            sed -i "s#$rootfs##g" "$cache"
            chown 0:0 "$cache"
            chmod 0644 "$cache"
            cache_relative=${cache#"$rootfs"}
            printf '%s\tfile\t@composer\n' "$cache_relative" >> "$owners"
        fi
    fi

    if [[ -d "$mime_root/packages" ]]; then
        [[ -x "$rootfs/usr/bin/update-mime-database" ]] || \
            die "MIME packages are installed without update-mime-database"
        [[ ! -e "$mime_root/mime.cache" ]] || \
            die "a package shipped the generated MIME cache"
        compose_run_target "$rootfs" \
            "$rootfs/usr/bin/update-mime-database" "$mime_root"
        [[ -s "$mime_root/mime.cache" ]] || die "MIME cache was not generated"
        compose_record_unowned_tree "$rootfs" "$owners" /usr/share/mime
    fi

    if [[ -d "$applications" ]] && \
       find "$applications" -maxdepth 1 -type f -name '*.desktop' -print -quit | grep -q .; then
        [[ -x "$rootfs/usr/bin/update-desktop-database" ]] || \
            die "desktop entries are installed without update-desktop-database"
        [[ ! -e "$applications/mimeinfo.cache" ]] || \
            die "a package shipped the generated desktop MIME cache"
        compose_run_target "$rootfs" \
            "$rootfs/usr/bin/update-desktop-database" "$applications"
        [[ -f "$applications/mimeinfo.cache" ]] || \
            die "desktop MIME cache was not generated"
        compose_record_generated_path \
            "$rootfs" "$owners" /usr/share/applications/mimeinfo.cache
    fi

    if [[ -d "$icons_root" ]]; then
        mapfile -t icon_themes < <(
            find "$icons_root" -mindepth 2 -maxdepth 2 \
                -type f -name index.theme -printf '%h\n' | LC_ALL=C sort
        )
        if ((${#icon_themes[@]} > 0)); then
            [[ -x "$rootfs/usr/bin/gtk-update-icon-cache" ]] || \
                die "icon themes are installed without gtk-update-icon-cache"
            for theme in "${icon_themes[@]}"; do
                if ! grep -Eq '^[[:space:]]*Directories=' "$theme/index.theme"; then
                    continue
                fi
                icon_cache="$theme/icon-theme.cache"
                [[ ! -e "$icon_cache" ]] || \
                    die "a package shipped a generated icon cache: ${theme#"$rootfs"}"
                compose_run_target "$rootfs" \
                    "$rootfs/usr/bin/gtk-update-icon-cache" --force "$theme"
                if [[ -s "$icon_cache" ]]; then
                    compose_record_generated_path \
                        "$rootfs" "$owners" "${icon_cache#"$rootfs"}"
                elif find "$theme" -mindepth 1 \
                        \( -type f -o -type l \) ! -name index.theme \
                        -print -quit | grep -q .; then
                    die "icon cache was not generated: ${theme#"$rootfs"}"
                fi
            done
        fi
    fi

    compose_write_ownership "$rootfs" "$owners"
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

compose_extend_profile() {
    local profile=$1
    local work rootfs owners sorted_owners package archive subset list

    [[ -d "$EFILINUX_ROOTFS" ]] || die "rootfs has not been composed"
    [[ -f "$EFILINUX_ROOTFS_OWNERS" ]] || die "rootfs ownership manifest is missing"
    [[ $(head -n 1 "$EFILINUX_ROOTFS_OWNERS") == $'path\ttype\towner' ]] || \
        die "rootfs ownership manifest has an invalid header"

    declare -gA COMPOSE_VISIT_STATE=()
    declare -gA COMPOSE_ARCHIVES=()
    declare -ga COMPOSE_ORDER=()
    compose_read_profile "$profile"

    work="$EFILINUX_BUILD/extend-$(basename -- "$profile")-$$"
    rootfs="$work/rootfs"
    owners="$work/owners.tsv"
    sorted_owners="$work/owners.sorted.tsv"
    reset_directory "$work"
    package_clone_tree "$EFILINUX_ROOTFS" "$rootfs"
    cp "$EFILINUX_ROOTFS_OWNERS" "$owners"
    compose_remove_generated_paths "$rootfs" "$owners"

    for package in "${COMPOSE_ORDER[@]}"; do
        if compose_package_is_installed "$package" "$owners"; then
            continue
        fi
        archive=${COMPOSE_ARCHIVES[$package]}
        subset="$work/packages/$package"
        list="$work/$package.install"
        package_materialize "$package" "$subset"
        tar --extract --to-stdout --file "$archive" .INSTALL > "$list"
        compose_validate_package_subset \
            "$package" "$subset" "$rootfs" "$owners" "$list"
        compose_merge_subset "$subset" "$rootfs"
    done

    compose_finalize_rootfs "$rootfs" "$owners"
    {
        printf 'path\ttype\towner\n'
        tail -n +2 "$owners" | LC_ALL=C sort -t $'\t' -k1,1 -k3,3
    } > "$sorted_owners"
    rm -rf "$EFILINUX_ROOTFS"
    mv "$rootfs" "$EFILINUX_ROOTFS"
    mv "$sorted_owners" "$EFILINUX_ROOTFS_OWNERS"
    rm -rf "$work"
    log "Extended rootfs with $(basename -- "$profile")"
}
