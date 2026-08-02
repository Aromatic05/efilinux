#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=linux-firmware
pkgver=20260622
sysroot=false

depends=(linux)
builddepends=()
makedepends=(awk find modinfo python3 sed sort tar xargs zstd)

prepare() {
    local archive="$downloaddir/linux-firmware-$pkgver.tar.xz"

    download \
        "https://www.kernel.org/pub/linux/kernel/firmware/linux-firmware-$pkgver.tar.xz" \
        "$archive"
    checksum \
        sha256 \
        2b9d8a358e76eb766588609135e53fa548b902c551daae33ee32f26f25e60dbb \
        "$archive"
    input_file "$recipedir/families.list" "$srcdir/families.list"
    input_file "$recipedir/exclude.list" "$srcdir/exclude.list"
    input_file "$recipedir/select_members.py" "$srcdir/select_members.py"
    input_file "$recipedir/materialize_links.py" "$srcdir/materialize_links.py"
    input_file "$recipedir/deduplicate_firmware.py" "$srcdir/deduplicate_firmware.py"
    input_file "$recipedir/verify_firmware_tree.py" "$srcdir/verify_firmware_tree.py"
}

build() {
    local archive="$downloaddir/linux-firmware-$pkgver.tar.xz"
    local archive_prefix="linux-firmware-$pkgver"
    local firmware_staging="$develdir/usr/lib/firmware"
    local request_manifest="$builddir/requests.list"
    local module_firmware_list="$builddir/module-firmware.list"
    local member_list="$builddir/members.list"
    local selection_report="$builddir/selection-report.tsv"
    local dedup_report="$builddir/dedup-report.tsv"
    local whence_file="$builddir/WHENCE"
    local module_root kernel_version firmware_path module_file
    local fallback_count unresolved_count deduplicated_count deduplicated_bytes
    local firmware_compression_level=${EFILINUX_FIRMWARE_COMPRESSION_LEVEL:-19}
    local -a module_roots=()

    mapfile -t module_roots < <(
        find "$EFILINUX_SYSROOT/usr/lib/modules" -mindepth 1 -maxdepth 1 -type d -print | LC_ALL=C sort
    )
    ((${#module_roots[@]} == 1)) || \
        die "linux-firmware requires exactly one kernel module tree in the sysroot"
    module_root=${module_roots[0]}
    kernel_version=$(basename -- "$module_root")
    [[ $firmware_compression_level =~ ^([1-9]|1[0-9])$ ]] || \
        die "invalid firmware compression level: $firmware_compression_level"

    mkdir -p "$builddir" "$firmware_staging"
    cp "$srcdir/families.list" "$request_manifest"
    find "$module_root" -type f -name '*.ko*' -print0 |
        while IFS= read -r -d '' module_file; do
            modinfo -b "$EFILINUX_SYSROOT" -k "$kernel_version" -F firmware "$module_file"
        done |
        sed '/^$/d' |
        sort -u > "$module_firmware_list"

    while IFS= read -r firmware_path; do
        [[ -n "$firmware_path" ]] || continue
        [[ "$firmware_path" != /* && "$firmware_path" != *..* ]] || \
            die "unsafe module firmware path: $firmware_path"
        if [[ "$firmware_path" == *'*'* || "$firmware_path" == *'?'* || \
              "$firmware_path" == *'['* ]]; then
            printf 'glob %s\n' "$firmware_path"
        else
            printf 'file %s\n' "$firmware_path"
        fi
    done < "$module_firmware_list" >> "$request_manifest"

    tar --extract --to-stdout \
        --file "$archive" \
        "$archive_prefix/WHENCE" > "$whence_file"
    tar --list --file "$archive" |
        python3 "$srcdir/select_members.py" \
            "$request_manifest" \
            "$srcdir/exclude.list" \
            "$archive_prefix" \
            "$whence_file" \
            "$selection_report" > "$member_list"
    [[ -s "$member_list" ]] || die "firmware selection produced an empty member list"
    read -r fallback_count unresolved_count < <(
        awk -F '\t' '
            $1 == "fallback" { fallback++ }
            $1 == "unresolved" { unresolved++ }
            END { printf "%d %d\n", fallback, unresolved }
        ' "$selection_report"
    )
    log "Firmware selection: $fallback_count compatible fallbacks, $unresolved_count unresolved declarations"

    tar --extract \
        --file "$archive" \
        --directory "$firmware_staging" \
        --strip-components=1 \
        --no-recursion \
        --files-from "$member_list"

    find "$firmware_staging" -depth -name '*[[:space:]]*' -delete
    find "$firmware_staging" -type l -delete
    find "$firmware_staging" -type f \
        ! -name 'WHENCE' \
        ! -name '*.zst' \
        ! -name 'README*' \
        ! -name 'LICENSE*' \
        -print0 |
        xargs -0 -r zstd \
            --quiet \
            "-$firmware_compression_level" \
            --threads="${EFILINUX_COMPRESSION_JOBS:-16}" \
            --rm
    find "$firmware_staging" -type f \
        \( -name 'README*' -o -name 'LICENSE*' \) -delete

    python3 "$srcdir/deduplicate_firmware.py" "$firmware_staging" "$dedup_report"
    python3 "$srcdir/materialize_links.py" "$whence_file" "$firmware_staging"
    rm -f "$firmware_staging/WHENCE"
    python3 "$srcdir/verify_firmware_tree.py" \
        "$firmware_staging" \
        "$selection_report" \
        "$dedup_report"
    read -r deduplicated_count deduplicated_bytes < <(
        awk -F '\t' '
            NF == 4 { count++; bytes += $4 }
            END { printf "%d %d\n", count, bytes }
        ' "$dedup_report"
    )
    log "Firmware compression level: $firmware_compression_level"
    log "Firmware deduplication: $deduplicated_count paths, $deduplicated_bytes bytes"
}

check() {
    local status request selected path

    while IFS=$'\t' read -r status request selected; do
        case $status in
            exact|fallback) ;;
            *) continue ;;
        esac
        path="$develdir/usr/lib/firmware/$selected.zst"
        [[ -e "$path" || -L "$path" ]] || \
            die "selected firmware is absent from the package tree: $request -> $selected"
    done < "$builddir/selection-report.tsv"
    python3 "$srcdir/verify_firmware_tree.py" \
        "$develdir/usr/lib/firmware" \
        "$builddir/selection-report.tsv" \
        "$builddir/dedup-report.tsv"
    find "$develdir/usr/lib/firmware" -type f -name '*.zst' -print0 |
        xargs -0 -r zstd --quiet --test
}

package() {
    :
}

recipe_main "$@"
