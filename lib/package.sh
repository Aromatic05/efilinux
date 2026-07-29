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

set_package_paths() {
    local package=$1

    PACKAGE_SOURCE="$EFILINUX_BUILD/sources/$package"
    PACKAGE_BUILD="$EFILINUX_BUILD/$package"
    PACKAGE_STAGING="$EFILINUX_BUILD/staging/$package"
}

prepare_package() {
    local package=$1

    set_package_paths "$package"
    reset_directory "$PACKAGE_SOURCE"
    reset_directory "$PACKAGE_BUILD"
    reset_directory "$PACKAGE_STAGING"
}

binary_package_recipe_hash() {
    local package=$1
    local producer=$2
    shift 2
    local recipe_file

    [[ -f "$producer" ]] || die "binary package producer is missing: $producer"
    {
        printf 'format=1\n'
        printf 'package=%s\n' "$package"
        printf 'arch=%s\n' "$EFILINUX_ARCH"
        printf 'x86_64_level=%s\n' "$EFILINUX_X86_64_LEVEL"
        printf 'cflags=%s\n' "$(target_cflags)"
        printf 'ldflags=%s\n' "$(target_ldflags)"
        for recipe_file in \
            "$EFILINUX_ROOT/config.sh" \
            "$producer" \
            "$@"; do
            [[ -f "$recipe_file" ]] || \
                die "binary package recipe input is missing: $recipe_file"
            printf 'recipe=%s\n' "${recipe_file#"$EFILINUX_ROOT/"}"
            sha256sum "$recipe_file"
        done
    } | sha256sum | awk '{print $1}'
}

binary_package_archive_path() {
    local package=$1
    local fingerprint=$2

    printf '%s/%s-%s-%s.pkg.tar.zst' \
        "$EFILINUX_PACKAGES" "$package" "$EFILINUX_ARCH" "${fingerprint:0:16}"
}

binary_package_verify_archive() {
    local archive=$1
    local expected_package=$2
    local expected_fingerprint=$3
    local checksum_file="$archive.sha256"
    local metadata

    [[ -f "$archive" ]] || return 1
    [[ -f "$checksum_file" ]] || \
        die "binary package checksum is missing: $checksum_file"
    (cd "$(dirname -- "$archive")" && sha256sum --check --status "$(basename -- "$checksum_file")") || \
        die "binary package checksum verification failed: $archive"
    metadata=$(tar --extract --to-stdout --file "$archive" .PKGINFO)
    grep -Fxq "name=$expected_package" <<<"$metadata" || \
        die "binary package name mismatch: $archive"
    grep -Fxq "fingerprint=$expected_fingerprint" <<<"$metadata" || \
        die "binary package recipe mismatch: $archive"
}

binary_package_extract() {
    local package=$1
    local destination=$2
    local producer=$3
    shift 3
    local fingerprint archive

    fingerprint=$(binary_package_recipe_hash "$package" "$producer" "$@")
    archive=$(binary_package_archive_path "$package" "$fingerprint")
    [[ -f "$archive" ]] || return 1
    binary_package_verify_archive "$archive" "$package" "$fingerprint"
    reset_directory "$destination"
    tar --extract --file "$archive" --directory "$destination" \
        --strip-components=1 pkg
    PACKAGE_ARCHIVE="$archive"
    PACKAGE_FINGERPRINT="$fingerprint"
}

binary_package_restore_sysroot() {
    local package=$1
    local producer=$2
    shift 2

    set_package_paths "$package"
    if ! binary_package_extract \
        "$package" "$PACKAGE_STAGING" "$producer" "$@"; then
        return 1
    fi

    log "Using binary package $(basename -- "$PACKAGE_ARCHIVE")"
    merge_sysroot "$PACKAGE_STAGING"
    rm -rf -- "$PACKAGE_SOURCE" "$PACKAGE_BUILD" "$PACKAGE_STAGING"
}

binary_package_reuse() {
    local package=$1
    local producer=$2
    shift 2
    local fingerprint archive

    fingerprint=$(binary_package_recipe_hash "$package" "$producer" "$@")
    archive=$(binary_package_archive_path "$package" "$fingerprint")
    [[ -f "$archive" ]] || return 1
    binary_package_verify_archive "$archive" "$package" "$fingerprint"

    PACKAGE_ARCHIVE="$archive"
    PACKAGE_FINGERPRINT="$fingerprint"
    set_package_paths "$package"
    rm -rf -- "$PACKAGE_SOURCE" "$PACKAGE_BUILD" "$PACKAGE_STAGING"
    log "Reusing binary package $(basename -- "$archive")"
}

binary_package_update_index() {
    local package=$1
    local fingerprint=$2
    local archive=$3
    local digest=$4
    local temporary="$EFILINUX_PACKAGE_INDEX.tmp.$$"

    mkdir -p "$(dirname -- "$EFILINUX_PACKAGE_INDEX")"
    touch "$EFILINUX_PACKAGE_INDEX"
    awk -F '\t' -v package="$package" '$1 != package' \
        "$EFILINUX_PACKAGE_INDEX" > "$temporary"
    printf '%s\t%s\t%s\t%s\n' \
        "$package" "$fingerprint" "$(basename -- "$archive")" "$digest" \
        >> "$temporary"
    sort -t $'\t' -k1,1 "$temporary" -o "$temporary"
    mv -- "$temporary" "$EFILINUX_PACKAGE_INDEX"
}

binary_package_prune_recipe_variants() {
    local package=$1
    local current_archive=$2
    local archive

    shopt -s nullglob
    for archive in "$EFILINUX_PACKAGES/$package-$EFILINUX_ARCH-"*.pkg.tar.zst; do
        [[ "$archive" == "$current_archive" ]] && continue
        rm -f -- "$archive" "$archive.sha256"
    done
    shopt -u nullglob
}

binary_package_remove() {
    local package=$1
    local temporary="$EFILINUX_PACKAGE_INDEX.tmp.$$"
    local archive

    if [[ -f "$EFILINUX_PACKAGE_INDEX" ]]; then
        awk -F '\t' -v package="$package" '$1 != package' \
            "$EFILINUX_PACKAGE_INDEX" > "$temporary"
        mv -- "$temporary" "$EFILINUX_PACKAGE_INDEX"
    fi

    shopt -s nullglob
    for archive in "$EFILINUX_PACKAGES/$package-$EFILINUX_ARCH-"*.pkg.tar.zst; do
        rm -f -- "$archive" "$archive.sha256"
    done
    shopt -u nullglob
}

binary_package_create() {
    local package=$1
    local staging=$2
    local producer=$3
    shift 3
    local fingerprint archive temporary metadata_dir digest source_epoch

    [[ -d "$staging" ]] || die "binary package staging tree is missing: $staging"
    ensure_directories
    fingerprint=$(binary_package_recipe_hash "$package" "$producer" "$@")
    archive=$(binary_package_archive_path "$package" "$fingerprint")
    temporary="$archive.tmp.$$"
    metadata_dir="$EFILINUX_PACKAGE_WORK/metadata-$package-$$"
    source_epoch=${SOURCE_DATE_EPOCH:-0}
    reset_directory "$metadata_dir"

    cat > "$metadata_dir/.PKGINFO" <<EOF
format=1
name=$package
arch=$EFILINUX_ARCH
x86_64_level=$EFILINUX_X86_64_LEVEL
fingerprint=$fingerprint
producer=${producer#"$EFILINUX_ROOT/"}
EOF
    for recipe_file in "$EFILINUX_ROOT/config.sh" "$producer" "$@"; do
        printf 'recipe=%s\n' "${recipe_file#"$EFILINUX_ROOT/"}" \
            >> "$metadata_dir/.PKGINFO"
    done
    (cd "$staging" && find . -mindepth 1 -printf '%P\n' | LC_ALL=C sort) \
        > "$metadata_dir/.FILELIST"

    tar --create --zstd --file "$temporary" \
        --sort=name \
        --mtime="@$source_epoch" \
        --owner=0 --group=0 --numeric-owner \
        --transform='s#^\./#pkg/#' \
        -C "$staging" . \
        -C "$metadata_dir" .PKGINFO .FILELIST
    digest=$(sha256sum "$temporary" | awk '{print $1}')
    mv -- "$temporary" "$archive"
    printf '%s  %s\n' "$digest" "$(basename -- "$archive")" > "$archive.sha256"
    binary_package_update_index "$package" "$fingerprint" "$archive" "$digest"
    binary_package_prune_recipe_variants "$package" "$archive"
    rm -rf -- "$metadata_dir"

    PACKAGE_ARCHIVE="$archive"
    PACKAGE_FINGERPRINT="$fingerprint"
    log "Created binary package $(basename -- "$archive")"
}

binary_package_publish_sysroot() {
    local package=$1
    local producer=$2
    shift 2

    binary_package_create \
        "$package" "$PACKAGE_STAGING" "$producer" "$@"
    merge_sysroot "$PACKAGE_STAGING"
    rm -rf -- "$PACKAGE_SOURCE" "$PACKAGE_BUILD" "$PACKAGE_STAGING"
}

binary_package_publish_staging() {
    local package=$1
    local producer=$2
    shift 2

    binary_package_create \
        "$package" "$PACKAGE_STAGING" "$producer" "$@"
    rm -rf -- "$PACKAGE_SOURCE" "$PACKAGE_BUILD" "$PACKAGE_STAGING"
}

binary_package_current_archive() {
    local package=$1
    local record indexed_package fingerprint archive digest

    [[ -f "$EFILINUX_PACKAGE_INDEX" ]] || \
        die "binary package index is missing: $EFILINUX_PACKAGE_INDEX"
    record=$(awk -F '\t' -v package="$package" '$1 == package { print; exit }' \
        "$EFILINUX_PACKAGE_INDEX")
    [[ -n "$record" ]] || die "binary package is not indexed: $package"
    IFS=$'\t' read -r indexed_package fingerprint archive digest <<<"$record"
    [[ "$indexed_package" == "$package" ]] || \
        die "binary package index returned the wrong package: $indexed_package"
    archive="$EFILINUX_PACKAGES/$archive"
    [[ -f "$archive" ]] || die "indexed binary package is missing: $archive"
    [[ $(sha256sum "$archive" | awk '{print $1}') == "$digest" ]] || \
        die "indexed binary package checksum mismatch: $archive"
    binary_package_verify_archive "$archive" "$package" "$fingerprint"
    printf '%s' "$archive"
}

binary_package_materialize() {
    local package=$1
    local destination=$2
    local archive

    archive=$(binary_package_current_archive "$package")
    reset_directory "$destination"
    tar --extract --file "$archive" --directory "$destination" \
        --strip-components=1 pkg
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

remove_rootfs_owner_prefix() {
    local relative_prefix=$1
    local temporary="$EFILINUX_ROOTFS_OWNERS.tmp"

    [[ -f "$EFILINUX_ROOTFS_OWNERS" ]] || return
    awk -F '\t' -v prefix="$relative_prefix/" \
        '$1 != substr(prefix, 1, length(prefix) - 1) && index($1, prefix) != 1' \
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

install_new_rootfs_tree() {
    local package=$1
    local source_root=$2
    local destination_root=$3
    local destination="$EFILINUX_ROOTFS$destination_root"

    [[ -d "$source_root" ]] || die "$package runtime tree is missing: $source_root"
    [[ ! -e "$destination" && ! -L "$destination" ]] || \
        die "$package attempted to install an already existing tree: $destination_root"

    if [[ -f "$EFILINUX_ROOTFS_OWNERS" ]] && \
        awk -F '\t' -v root="$destination_root" \
            '$1 == root || index($1, root "/") == 1 { found=1 } END { exit !found }' \
            "$EFILINUX_ROOTFS_OWNERS"; then
        die "$package attempted to install an already owned tree: $destination_root"
    fi

    mkdir -p "$(dirname -- "$destination")" \
        "$(dirname -- "$EFILINUX_ROOTFS_OWNERS")"
    cp -a -- "$source_root" "$destination"
    touch "$EFILINUX_ROOTFS_OWNERS"
    LC_ALL=C find "$source_root" -mindepth 1 -printf '%P\0' |
        awk -v RS='\0' -v prefix="$destination_root/" -v owner="$package" \
            'length($0) { print prefix $0 "\t" owner }' \
        >> "$EFILINUX_ROOTFS_OWNERS"
}

replace_rootfs_tree() {
    local package=$1
    local expected_owner=$2
    local source_root=$3
    local destination_root=$4
    local conflict

    conflict=$(awk -F '\t' \
        -v path="$destination_root" \
        -v prefix="$destination_root/" \
        -v expected="$expected_owner" \
        '($1 == path || index($1, prefix) == 1) && $2 != expected { print $1 " owned by " $2; exit }' \
        "$EFILINUX_ROOTFS_OWNERS" 2>/dev/null || true)
    [[ -z "$conflict" ]] || \
        die "$package cannot replace $destination_root: $conflict"

    rm -rf -- "$EFILINUX_ROOTFS$destination_root"
    remove_rootfs_owner_prefix "$destination_root"
    install_rootfs_tree "$package" "$source_root" "$destination_root"
}

strip_rootfs_elf() {
    local file

    while IFS= read -r -d '' file; do
        if LC_ALL=C readelf --file-header "$file" >/dev/null 2>&1; then
            strip --strip-unneeded "$file" 2>/dev/null || true
        fi
    done < <(find "$EFILINUX_ROOTFS/usr" -type f -print0)
}
