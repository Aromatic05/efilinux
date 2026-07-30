#!/usr/bin/env bash

set -euo pipefail

readonly EFILINUX_PACKAGE_FORMAT=4
readonly EFILINUX_PACKAGE_INDEX_HEADER='# efilinux-package-index-v4'

package_clone_tree() {
    local source=$1
    local destination=$2

    [[ -d "$source" ]] || die "package tree source is missing: $source"
    reset_directory "$destination"
    tar --create --file - --numeric-owner --directory "$source" . | \
        tar --extract --file - --numeric-owner --same-owner --directory "$destination"
}

package_archive_name() {
    local name=$1
    local version=$2
    local content_hash=$3

    printf '%s-%s-%s-%s.pkg.tar.zst' \
        "$name" "$version" "$EFILINUX_ARCH" "${content_hash:0:16}"
}

package_assert_current_index() {
    local header

    if [[ ! -e "$EFILINUX_PACKAGE_INDEX" ]]; then
        mkdir -p "$(dirname -- "$EFILINUX_PACKAGE_INDEX")"
        printf '%s\n' "$EFILINUX_PACKAGE_INDEX_HEADER" > "$EFILINUX_PACKAGE_INDEX"
        return
    fi

    IFS= read -r header < "$EFILINUX_PACKAGE_INDEX" || true
    [[ "$header" == "$EFILINUX_PACKAGE_INDEX_HEADER" ]] || \
        die "legacy package index detected; remove $EFILINUX_PACKAGES before building format $EFILINUX_PACKAGE_FORMAT packages"
}

package_verify_archive() {
    local archive=$1
    local expected_name=$2
    local expected_version=$3
    local expected_recipe_key=$4
    local expected_digest=$5
    local metadata

    [[ -f "$archive" ]] || die "package archive is missing: $archive"
    [[ $(sha256sum "$archive" | awk '{print $1}') == "$expected_digest" ]] || \
        die "package archive digest mismatch: $archive"

    metadata=$(tar --extract --to-stdout --file "$archive" .PKGINFO)
    grep -Fxq "format=$EFILINUX_PACKAGE_FORMAT" <<<"$metadata" || \
        die "package format mismatch: $archive"
    grep -Fxq "name=$expected_name" <<<"$metadata" || \
        die "package name mismatch: $archive"
    grep -Fxq "version=$expected_version" <<<"$metadata" || \
        die "package version mismatch: $archive"
    grep -Fxq "recipe_key=$expected_recipe_key" <<<"$metadata" || \
        die "package recipe key mismatch: $archive"

    tar --extract --to-stdout --file "$archive" .BUILDINFO >/dev/null
    tar --extract --to-stdout --file "$archive" .FILELIST >/dev/null
    tar --extract --to-stdout --file "$archive" .INSTALL >/dev/null
    tar --list --file "$archive" | \
        awk '$0 ~ /^\// || $0 ~ /(^|\/)\.\.($|\/)/ { exit 1 }' || \
        die "package archive contains an unsafe path: $archive"
}

package_find_archive() {
    local name=$1
    local version=$2
    local recipe_key=$3
    local record indexed_name indexed_version indexed_key content_hash archive_name digest archive

    [[ -f "$EFILINUX_PACKAGE_INDEX" ]] || return 1
    package_assert_current_index
    record=$(awk -F '\t' -v name="$name" -v version="$version" -v key="$recipe_key" \
        'NR > 1 && $1 == name && $2 == version && $3 == key { print; exit }' \
        "$EFILINUX_PACKAGE_INDEX")
    [[ -n "$record" ]] || return 1

    IFS=$'\t' read -r indexed_name indexed_version indexed_key content_hash archive_name digest <<<"$record"
    [[ "$indexed_name" == "$name" && "$indexed_version" == "$version" && "$indexed_key" == "$recipe_key" ]] || \
        die "package index lookup returned inconsistent metadata for $name"
    [[ -n "$digest" ]] || die "incomplete package index record for $name"
    archive="$EFILINUX_PACKAGES/$archive_name"
    package_verify_archive "$archive" "$name" "$version" "$recipe_key" "$digest"
    printf '%s' "$archive"
}

package_current_archive() {
    local name=$1
    local record indexed_name version recipe_key content_hash archive_name digest archive

    package_assert_current_index
    record=$(awk -F '\t' -v name="$name" \
        'NR > 1 && $1 == name { print; exit }' "$EFILINUX_PACKAGE_INDEX")
    [[ -n "$record" ]] || die "package is not indexed: $name"
    IFS=$'\t' read -r indexed_name version recipe_key content_hash archive_name digest <<<"$record"
    [[ "$indexed_name" == "$name" && -n "$digest" ]] || \
        die "incomplete package index record for $name"
    archive="$EFILINUX_PACKAGES/$archive_name"
    package_verify_archive "$archive" "$name" "$version" "$recipe_key" "$digest"
    printf '%s' "$archive"
}

package_update_index() {
    local name=$1
    local version=$2
    local recipe_key=$3
    local content_hash=$4
    local archive=$5
    local digest=$6
    local temporary="$EFILINUX_PACKAGE_INDEX.tmp.$$"

    package_assert_current_index
    {
        printf '%s\n' "$EFILINUX_PACKAGE_INDEX_HEADER"
        awk -F '\t' -v name="$name" 'NR > 1 && $1 != name' "$EFILINUX_PACKAGE_INDEX"
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$name" "$version" "$recipe_key" "$content_hash" \
            "$(basename -- "$archive")" "$digest"
    } > "$temporary"
    {
        head -n 1 "$temporary"
        tail -n +2 "$temporary" | LC_ALL=C sort -t $'\t' -k1,1
    } > "$temporary.sorted"
    mv -- "$temporary.sorted" "$EFILINUX_PACKAGE_INDEX"
    rm -f -- "$temporary"
}

package_write_buildinfo() {
    local output=$1
    local recipe_file=$2
    local source_records=$3
    local dependency tool tool_path tool_digest

    {
        printf 'recipe=%s\n' "${recipe_file#"$EFILINUX_ROOT/"}"
        printf 'arch=%s\n' "$EFILINUX_ARCH"
        printf 'x86_64_level=%s\n' "$EFILINUX_X86_64_LEVEL"
        printf 'cflags=%s\n' "${CFLAGS:-}"
        printf 'cxxflags=%s\n' "${CXXFLAGS:-}"
        printf 'cppflags=%s\n' "${CPPFLAGS:-}"
        printf 'ldflags=%s\n' "${LDFLAGS:-}"
        for dependency in "${depends[@]:-}"; do
            [[ -n "$dependency" ]] && printf 'depends=%s\n' "$dependency"
        done
        for dependency in "${builddepends[@]:-}"; do
            [[ -n "$dependency" ]] && printf 'builddepends=%s\n' "$dependency"
        done
        for dependency in "${makedepends[@]:-}"; do
            [[ -n "$dependency" ]] && printf 'makedepends=%s\n' "$dependency"
        done
        for tool in "${makedepends[@]:-}"; do
            [[ -n "$tool" ]] || continue
            tool_path=$(command -v "$tool")
            if [[ -f "$tool_path" ]]; then
                tool_digest=$(sha256sum "$tool_path" | awk '{print $1}')
            else
                tool_digest=builtin
            fi
            printf 'hosttool=%s|%s|%s\n' "$tool" "$tool_path" "$tool_digest"
        done
        [[ ! -s "$source_records" ]] || cat "$source_records"
    } > "$output"
}

package_create_archive() {
    local name=$1
    local version=$2
    local recipe_key=$3
    local devel_directory=$4
    local package_directory=$5
    local recipe_file=$6
    local source_records=$7
    local source_epoch=${SOURCE_DATE_EPOCH:-0}
    local work archive_root temporary digest content_hash archive

    [[ -d "$devel_directory" ]] || die "devel tree is missing: $devel_directory"
    [[ -d "$package_directory" ]] || die "package tree is missing: $package_directory"

    ensure_directories
    work="$EFILINUX_PACKAGE_WORK/create-$name-$$"
    archive_root="$work/root"
    temporary="$work/package.tar.zst"
    reset_directory "$archive_root"
    package_clone_tree "$devel_directory" "$archive_root/devel"

    cat > "$archive_root/.PKGINFO" <<EOF
format=$EFILINUX_PACKAGE_FORMAT
name=$name
version=$version
arch=$EFILINUX_ARCH
x86_64_level=$EFILINUX_X86_64_LEVEL
recipe_key=$recipe_key
sysroot=$sysroot
EOF
    for dependency in "${depends[@]:-}"; do
        [[ -n "$dependency" ]] && printf 'depends=%s\n' "$dependency" >> "$archive_root/.PKGINFO"
    done
    package_write_buildinfo "$archive_root/.BUILDINFO" "$recipe_file" "$source_records"
    (cd "$devel_directory" && find . -mindepth 1 -printf '/%P\n' | LC_ALL=C sort) \
        > "$archive_root/.FILELIST"
    (cd "$package_directory" && find . -mindepth 1 -printf '/%P\n' | LC_ALL=C sort) \
        > "$archive_root/.INSTALL"

    tar --create \
        --use-compress-program="zstd --threads=${EFILINUX_COMPRESSION_JOBS:-16} --quiet" \
        --file "$temporary" \
        --sort=name \
        --mtime="@$source_epoch" \
        --numeric-owner \
        -C "$archive_root" \
        .PKGINFO .BUILDINFO .FILELIST .INSTALL devel

    digest=$(sha256sum "$temporary" | awk '{print $1}')
    content_hash=$digest
    archive="$EFILINUX_PACKAGES/$(package_archive_name "$name" "$version" "$content_hash")"
    mkdir -p "$EFILINUX_PACKAGES"
    mv -- "$temporary" "$archive"
    printf '%s  %s\n' "$digest" "$(basename -- "$archive")" > "$archive.sha256"
    package_update_index "$name" "$version" "$recipe_key" "$content_hash" "$archive" "$digest"
    rm -rf -- "$work"

    PACKAGE_ARCHIVE=$archive
    PACKAGE_CONTENT_HASH=$content_hash
    log "Created package $(basename -- "$archive")"
}

package_extract_devel() {
    local archive=$1
    local destination=$2

    reset_directory "$destination"
    tar --extract --file "$archive" --directory "$destination" \
        --strip-components=1 devel
}

package_merge_devel_into_sysroot() {
    local devel_directory=$1

    mkdir -p "$EFILINUX_SYSROOT"
    cp -a --remove-destination "$devel_directory/." "$EFILINUX_SYSROOT/"
}

package_restore_recipe_cache() {
    local name=$1
    local version=$2
    local recipe_key=$3
    local install_to_sysroot=$4
    local archive

    archive=$(package_find_archive "$name" "$version" "$recipe_key") || return 1
    if [[ "$install_to_sysroot" == true ]]; then
        package_extract_devel "$archive" "$develdir"
        package_merge_devel_into_sysroot "$develdir"
    fi
    PACKAGE_ARCHIVE=$archive
    log "Using package $(basename -- "$archive")"
}

package_materialize() {
    local name=$1
    local destination=$2
    local record version recipe_key content_hash archive_name digest archive work list
    local -a owner_options=(--numeric-owner --no-same-owner)

    if [[ -n ${FAKEROOTKEY:-} || $EUID -eq 0 ]]; then
        owner_options=(--numeric-owner --same-owner)
    fi

    package_assert_current_index
    record=$(awk -F '\t' -v name="$name" 'NR > 1 && $1 == name { print; exit }' \
        "$EFILINUX_PACKAGE_INDEX")
    [[ -n "$record" ]] || die "package is not indexed: $name"
    IFS=$'\t' read -r name version recipe_key content_hash archive_name digest <<<"$record"
    archive="$EFILINUX_PACKAGES/$archive_name"
    package_verify_archive "$archive" "$name" "$version" "$recipe_key" "$digest"

    work="$EFILINUX_PACKAGE_WORK/materialize-$name-$$"
    list="$work/install.list"
    reset_directory "$work"
    mkdir -p "$work/devel"
    tar --extract --file "$archive" "${owner_options[@]}" \
        --directory "$work/devel" \
        --strip-components=1 devel
    tar --extract --to-stdout --file "$archive" .INSTALL | \
        sed 's#^/##' > "$list"

    reset_directory "$destination"
    if [[ -s "$list" ]]; then
        tar --create --file - --numeric-owner --no-recursion \
            --directory "$work/devel" --files-from "$list" | \
            tar --extract --file - "${owner_options[@]}" \
                --directory "$destination"
    fi
    rm -rf -- "$work"
}
