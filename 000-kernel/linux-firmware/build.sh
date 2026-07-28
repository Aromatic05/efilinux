#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command awk curl find modinfo python3 sed sha256sum sort tar xargs zstd
ensure_directories

archive="$EFILINUX_DOWNLOADS/linux-firmware-$LINUX_FIRMWARE_VERSION.tar.xz"
staging_directory="$EFILINUX_BUILD/staging/linux-firmware"
firmware_root="$EFILINUX_ROOTFS/usr/lib/firmware"
module_root="$EFILINUX_ROOTFS/usr/lib/modules/$LINUX_VERSION"
supplement_manifest="$ROOT/000-kernel/linux-firmware/families.list"
request_manifest="$EFILINUX_TEST/linux-firmware-requests.list"
module_firmware_list="$EFILINUX_TEST/module-firmware.list"
archive_prefix="linux-firmware-$LINUX_FIRMWARE_VERSION"
member_list="$EFILINUX_TEST/linux-firmware-members.list"
whence_file="$EFILINUX_TEST/linux-firmware-WHENCE"

[[ -d "$module_root" ]] || die "kernel modules must be built before firmware selection"

download \
    "https://www.kernel.org/pub/linux/kernel/firmware/linux-firmware-$LINUX_FIRMWARE_VERSION.tar.xz" \
    "$archive"
verify_sha256 "$LINUX_FIRMWARE_SHA256" "$archive"
reset_directory "$staging_directory"

log "Collecting firmware declarations from the built kernel modules"
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

tar --extract --to-stdout \
    --file "$archive" \
    "$archive_prefix/WHENCE" \
    > "$whence_file"

log "Selecting common PC firmware from linux-firmware $LINUX_FIRMWARE_VERSION"
tar --list --file "$archive" |
python3 "$ROOT/000-kernel/linux-firmware/select_members.py" \
    "$request_manifest" \
    "$archive_prefix" \
    "$whence_file" \
    > "$member_list"

[[ -s "$member_list" ]] || die "firmware selection produced an empty archive member list"
tar --extract \
    --file "$archive" \
    --directory "$staging_directory" \
    --strip-components=1 \
    --no-recursion \
    --files-from "$member_list"

# The kernel's directory-based initramfs generator cannot represent paths with
# whitespace. These are board-specific Broadcom NVRAM files for uncommon tablet
# models, not generic firmware required by the selected driver families.
find "$staging_directory" -depth -name '*[[:space:]]*' -delete

find "$staging_directory" -type l -delete
find "$staging_directory" -type f \
    ! -name 'WHENCE' \
    ! -name '*.zst' \
    ! -name 'README*' \
    ! -name 'LICENSE*' \
    -print0 |
    xargs -0 -r zstd --quiet --threads=0 --rm
find "$staging_directory" -type f \( -name 'README*' -o -name 'LICENSE*' \) -delete

while IFS=$'\t' read -r link_path target_path; do
    [[ -n "$link_path" && -f "$staging_directory/$target_path.zst" ]] || continue
    mkdir -p "$staging_directory/$(dirname -- "$link_path")"
    ln -s "/usr/lib/firmware/$target_path.zst" "$staging_directory/$link_path.zst"
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
rm -f "$staging_directory/WHENCE"

reset_directory "$firmware_root"
cp -a "$staging_directory/." "$firmware_root/"
