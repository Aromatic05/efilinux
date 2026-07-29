#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command awk curl find modinfo python3 sed sha256sum sort tar xargs zstd
ensure_directories

package="linux-firmware-$LINUX_FIRMWARE_VERSION"
producer=${BASH_SOURCE[0]}
archive="$EFILINUX_DOWNLOADS/$package.tar.xz"
module_root="$EFILINUX_ROOTFS/usr/lib/modules/$LINUX_VERSION"
supplement_manifest="$ROOT/000-kernel/linux-firmware/families.list"
exclude_manifest="$ROOT/000-kernel/linux-firmware/exclude.list"
selector="$ROOT/000-kernel/linux-firmware/select_members.py"
request_manifest="$EFILINUX_TEST/linux-firmware-requests.list"
module_firmware_list="$EFILINUX_TEST/module-firmware.list"
archive_prefix="$package"
member_list="$EFILINUX_TEST/linux-firmware-members.list"
whence_file="$EFILINUX_TEST/linux-firmware-WHENCE"

[[ -d "$module_root" ]] || die "kernel modules must be built before firmware selection"
set_package_paths "$package"

log "Collecting firmware declarations from the packaged kernel modules"
cp "$supplement_manifest" "$request_manifest"
find "$module_root" -type f -name '*.ko*' -print0 |
    while IFS= read -r -d '' module_file; do
        modinfo -F firmware "$module_file"
    done |
    sed '/^$/d' |
    sort -u \
    > "$module_firmware_list"

while IFS= read -r firmware_path; do
    [[ -z "$firmware_path" ]] && continue
    [[ "$firmware_path" != /* && "$firmware_path" != *..* ]] || \
        die "unsafe module firmware path: $firmware_path"

    if [[ "$firmware_path" == *'*'* || \
          "$firmware_path" == *'?'* || \
          "$firmware_path" == *'['* ]]; then
        printf 'glob %s\n' "$firmware_path"
    else
        printf 'file %s\n' "$firmware_path"
    fi
done < "$module_firmware_list" >> "$request_manifest"

recipe_inputs=(
    "$supplement_manifest"
    "$exclude_manifest"
    "$selector"
    "$request_manifest"
)

if binary_package_extract \
    "$package" "$PACKAGE_STAGING" "$producer" "${recipe_inputs[@]}"; then
    log "Using binary package $(basename -- "$PACKAGE_ARCHIVE")"
else
    download \
        "https://www.kernel.org/pub/linux/kernel/firmware/$package.tar.xz" \
        "$archive"
    verify_sha256 "$LINUX_FIRMWARE_SHA256" "$archive"
    reset_directory "$PACKAGE_STAGING"
    firmware_staging="$PACKAGE_STAGING/usr/lib/firmware"
    mkdir -p "$firmware_staging"

    tar --extract --to-stdout \
        --file "$archive" \
        "$archive_prefix/WHENCE" \
        > "$whence_file"

    log "Selecting common PC firmware from linux-firmware $LINUX_FIRMWARE_VERSION"
    tar --list --file "$archive" |
    python3 "$selector" \
        "$request_manifest" \
        "$exclude_manifest" \
        "$archive_prefix" \
        "$whence_file" \
        > "$member_list"

    [[ -s "$member_list" ]] || die "firmware selection produced an empty archive member list"
    tar --extract \
        --file "$archive" \
        --directory "$firmware_staging" \
        --strip-components=1 \
        --no-recursion \
        --files-from "$member_list"

    # The kernel's directory-based initramfs generator cannot represent paths
    # with whitespace. These are uncommon board-specific Broadcom NVRAM files.
    find "$firmware_staging" -depth -name '*[[:space:]]*' -delete
    find "$firmware_staging" -type l -delete
    find "$firmware_staging" -type f \
        ! -name 'WHENCE' \
        ! -name '*.zst' \
        ! -name 'README*' \
        ! -name 'LICENSE*' \
        -print0 |
        xargs -0 -r zstd --quiet --threads="${EFILINUX_COMPRESSION_JOBS:-16}" --rm
    find "$firmware_staging" -type f \
        \( -name 'README*' -o -name 'LICENSE*' \) -delete

    while IFS=$'\t' read -r link_path target_path; do
        [[ -n "$link_path" && -f "$firmware_staging/$target_path.zst" ]] || continue
        mkdir -p "$firmware_staging/$(dirname -- "$link_path")"
        ln -s "/usr/lib/firmware/$target_path.zst" "$firmware_staging/$link_path.zst"
    done < <(
        awk '
            /^Link: / {
                sub(/^Link: /, "")
                split($0, parts, " -> ")
                if (length(parts[1]) && length(parts[2]))
                    printf "%s\t%s\n", parts[1], parts[2]
            }
        ' "$whence_file"
    )
    rm -f "$firmware_staging/WHENCE"

    binary_package_create \
        "$package" "$PACKAGE_STAGING" "$producer" "${recipe_inputs[@]}"
fi

install_rootfs_tree \
    "$package" "$PACKAGE_STAGING/usr/lib/firmware" /usr/lib/firmware
rm -rf -- "$PACKAGE_SOURCE" "$PACKAGE_BUILD" "$PACKAGE_STAGING"
