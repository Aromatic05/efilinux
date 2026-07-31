#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command awk file readelf tar zstd
ensure_directories

work="$EFILINUX_TEST/maintenance-packages"
loader="$EFILINUX_SYSROOT/usr/lib/ld-linux-x86-64.so.2"
library_path="$EFILINUX_SYSROOT/usr/lib"
packages=(efivar efibootmgr gptfdisk smartmontools nvme-cli libusb usbutils lm-sensors hdparm)

[[ -x "$loader" ]] || die "target glibc loader is missing"
reset_directory "$work"

materialize() {
    local package=$1
    local runtime="$work/$package"

    package_materialize "$package" "$runtime"
    printf '%s' "$runtime"
}

assert_program() {
    local runtime=$1
    local path=$2

    [[ -x "$runtime$path" ]] || die "package runtime command is missing: $path"
}

assert_no_development_payload() {
    local package=$1
    local runtime=$2

    if find "$runtime" -type f \( \
        -path '*/include/*' -o -path '*/pkgconfig/*' -o -name '*.a' -o -name '*.la' -o \
        -path '*/man/*' -o -path '*/doc/*' -o -path '*/info/*' -o -path '*/locale/*' \
        \) -print -quit | grep -q .; then
        die "$package contains development, documentation, or locale payload"
    fi
}

assert_elf_closure() {
    local runtime=$1
    local binary needed

    while IFS= read -r binary; do
        file -b "$binary" | grep -q ELF || continue
        while IFS= read -r needed; do
            [[ -e "$runtime/usr/lib/$needed" || -e "$EFILINUX_SYSROOT/usr/lib/$needed" ]] ||
                die "package ELF dependency is unavailable: $binary needs $needed"
        done < <(LC_ALL=C readelf -d "$binary" |
            awk '/NEEDED/ { gsub(/\[|\]/, "", $NF); print $NF }')
    done < <(find "$runtime/usr/bin" -maxdepth 1 -type f -perm -u+x -print 2>/dev/null)
}

target_program() {
    local program=$1
    shift
    "$loader" --library-path "$library_path" "$program" "$@"
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
for package in "${packages[@]}"; do
    runtime=$(materialize "$package")
    assert_no_development_payload "$package" "$runtime"
    assert_elf_closure "$runtime"
    size=$(tar -C "$runtime" -cf - . | zstd -q -19 -c | wc -c)
    printf '%-14s %8d bytes (limit %d)\n' "$package" "$size" "${limits[$package]}"
    (( size <= limits[$package] )) || die "$package runtime payload exceeds its size budget"
    total=$((total + size))
done
(( total <= 1600000 )) || die "maintenance packages exceed the 1.6 MB aggregate budget"

assert_program "$work/efivar" /usr/bin/efivar
assert_program "$work/efivar" /usr/bin/efisecdb
assert_program "$work/efibootmgr" /usr/bin/efibootmgr
assert_program "$work/efibootmgr" /usr/bin/efibootdump
for program in gdisk cgdisk sgdisk fixparts; do
    assert_program "$work/gptfdisk" "/usr/bin/$program"
done
assert_program "$work/smartmontools" /usr/bin/smartctl
assert_program "$work/nvme-cli" /usr/bin/nvme
assert_program "$work/usbutils" /usr/bin/lsusb
assert_program "$work/usbutils" /usr/bin/usb-devices
assert_program "$work/usbutils" /usr/bin/usbhid-dump
assert_program "$work/lm-sensors" /usr/bin/sensors
assert_program "$work/hdparm" /usr/bin/hdparm

for library in \
    "$work/efivar/usr/lib/libefivar.so.1" \
    "$work/efivar/usr/lib/libefiboot.so.1" \
    "$work/efivar/usr/lib/libefisec.so.1" \
    "$work/libusb/usr/lib/libusb-1.0.so.0" \
    "$work/lm-sensors/usr/lib/libsensors.so.5"; do
    [[ -e "$library" ]] || die "maintenance runtime library is missing: $library"
done

target_program "$work/efibootmgr/usr/bin/efibootmgr" --version | grep -Fxq 'version 18'
target_program "$work/gptfdisk/usr/bin/sgdisk" --version | grep -Fq 'version 1.0.10'
target_program "$work/smartmontools/usr/bin/smartctl" --version | grep -Fq 'smartctl 7.5'
target_program "$work/nvme-cli/usr/bin/nvme" version | grep -Fq 'nvme version 2.16'
target_program "$work/usbutils/usr/bin/lsusb" --version | grep -Fq 'usbutils) 019'
target_program "$work/lm-sensors/usr/bin/sensors" --version | grep -Fq 'sensors version 3.6.2'
target_program "$work/hdparm/usr/bin/hdparm" -V | grep -Fxq 'hdparm v9.65'

nvme_help=$(target_program "$work/nvme-cli/usr/bin/nvme" help 2>&1)
for plugin in fdp nbft zns feat ocp sed; do
    grep -Eq "^[[:space:]]+$plugin[[:space:]]" <<<"$nvme_help" ||
        die "standards-oriented NVMe plugin is missing: $plugin"
done
for plugin in intel wdc solidigm micron samsung; do
    if grep -Eq "^[[:space:]]+$plugin[[:space:]]" <<<"$nvme_help"; then
        die "vendor-specific NVMe plugin leaked into the base package: $plugin"
    fi
done

printf 'Maintenance package payload total: %d bytes\n' "$total"
log "Maintenance package payloads, commands, dependencies, and size budgets passed"
