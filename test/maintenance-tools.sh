#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command awk readelf tar zstd
ensure_directories

rootfs="$EFILINUX_ROOTFS"
owners="$EFILINUX_ROOTFS_OWNERS"
work="$EFILINUX_TEST/maintenance-tools"

[[ -f "$owners" ]] || die "rootfs ownership manifest is missing"
reset_directory "$work"

assert_program() {
    local name=$1
    local owner=$2
    local path="$rootfs/usr/bin/$name"

    [[ -x "$path" ]] || die "maintenance command is missing: $name"
    awk -F '\t' -v path="/usr/bin/$name" -v owner="$owner" \
        '$1 == path && $3 == owner { found=1 } END { exit !found }' "$owners" ||
        die "maintenance command has the wrong owner: $name"
}

assert_program efivar efivar
assert_program efisecdb efivar
assert_program efibootmgr efibootmgr
assert_program efibootdump efibootmgr
assert_program gdisk gptfdisk
assert_program cgdisk gptfdisk
assert_program sgdisk gptfdisk
assert_program fixparts gptfdisk
assert_program smartctl smartmontools
assert_program nvme nvme-cli
assert_program lsusb usbutils
assert_program usb-devices usbutils
assert_program usbhid-dump usbutils
assert_program sensors lm-sensors
assert_program hdparm hdparm

for library in \
    libefivar.so.1 \
    libefiboot.so.1 \
    libusb-1.0.so.0 \
    libsensors.so.5; do
    [[ -e "$rootfs/usr/lib/$library" ]] || die "maintenance runtime library is missing: $library"
done

while IFS= read -r binary; do
    while IFS= read -r needed; do
        [[ -e "$rootfs/usr/lib/$needed" ]] ||
            die "maintenance ELF dependency is outside rootfs: $binary needs $needed"
    done < <(LC_ALL=C readelf -d "$binary" |
        awk '/NEEDED/ { gsub(/\[|\]/, "", $NF); print $NF }')
done < <(find "$rootfs/usr/bin" -maxdepth 1 -type f -perm -u+x \( \
    -name efivar -o -name efisecdb -o -name efibootmgr -o -name efibootdump -o \
    -name gdisk -o -name cgdisk -o -name sgdisk -o -name fixparts -o \
    -name smartctl -o -name nvme -o -name lsusb -o -name usbhid-dump -o \
    -name sensors -o -name hdparm \) -print)

if awk -F '\t' \
    '$3 ~ /^(efivar|efibootmgr|gptfdisk|smartmontools|nvme-cli|libusb|usbutils|lm-sensors|hdparm)$/ &&
     $1 ~ /^\/usr\/share\/(man|doc|info|locale)\// { print; exit }' \
    "$owners" | grep -q .; then
    die "maintenance tools installed documentation or locale payload"
fi

package_payload_size() {
    local package=$1
    local list="$work/$package.list"

    awk -F '\t' -v package="$package" \
        '$3 == package && $2 != "directory" { sub(/^\//, "", $1); print $1 }' \
        "$owners" | LC_ALL=C sort -u > "$list"
    [[ -s "$list" ]] || die "rootfs contains no payload owned by $package"
    tar -C "$rootfs" -cf - -T "$list" | zstd -q -19 -c | wc -c
}

declare -A limits=(
    [efivar]=180000
    [efibootmgr]=50000
    [gptfdisk]=250000
    [smartmontools]=500000
    [nvme-cli]=420000
    [libusb]=70000
    [usbutils]=120000
    [lm-sensors]=70000
    [hdparm]=90000
)

total=0
for package in efivar efibootmgr gptfdisk smartmontools nvme-cli libusb usbutils lm-sensors hdparm; do
    size=$(package_payload_size "$package")
    printf '%-14s %8d bytes (limit %d)\n' "$package" "$size" "${limits[$package]}"
    (( size <= limits[$package] )) || die "$package runtime payload exceeds its size budget"
    total=$((total + size))
done
(( total <= 1600000 )) || die "maintenance runtime exceeds the 1.6 MB aggregate budget"
printf 'Maintenance runtime payload total: %d bytes\n' "$total"

log "EFI, storage, USB, sensor, and drive maintenance tools passed"
