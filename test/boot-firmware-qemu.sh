#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command make mke2fs qemu-system-x86_64 timeout truncate
ensure_directories

qemu_cpu=${QEMU_CPU:-Nehalem}
ovmf_code=${OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}
ovmf_vars_template=${OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}
ovmf_vars="$EFILINUX_TEST/OVMF_VARS.firmware.fd"
boot_log="$EFILINUX_LOGS/qemu-firmware-boot.log"
efi_binary="$EFILINUX_EFI_DIR/EFI/BOOT/BOOTX64.EFI"
probe_source="$ROOT/test/helpers/firmware-request-probe.c"
guest_checks="$ROOT/test/helpers/firmware-guest-checks.sh"
probe_build="$EFILINUX_TEST/firmware-probe-build"
probe_stage="$EFILINUX_TEST/firmware-probe-stage"
probe_disk="$EFILINUX_TEST/firmware-probe.img"
firmware_name=iwlwifi-ty-a0-gf-a0-89.ucode

[[ -f $efi_binary ]] || die "EFI binary is missing: $efi_binary"
[[ -f $ovmf_code ]] || die "OVMF code image is missing: $ovmf_code"
[[ -f $ovmf_vars_template ]] || \
    die "OVMF variables image is missing: $ovmf_vars_template"
[[ -f $probe_source ]] || die "firmware request probe source is missing: $probe_source"
[[ -x $guest_checks ]] || die "firmware guest checks are missing: $guest_checks"

mapfile -t kernel_versions < <(
    find "$EFILINUX_ROOTFS/usr/lib/modules" \
        -mindepth 1 -maxdepth 1 -type d -printf '%f\n' |
        LC_ALL=C sort
)
((${#kernel_versions[@]} == 1)) || \
    die "firmware acceptance requires exactly one target kernel module tree"
kernel_version=${kernel_versions[0]}
kernel_build=
while IFS= read -r generated_header; do
    grep -Fq "\"$kernel_version\"" "$generated_header" || continue
    kernel_build=$(dirname -- "$(dirname -- "$(dirname -- "$generated_header")")")
    break
done < <(
    find "$EFILINUX_BUILD/kernel-state" \
        -path '*/build/include/generated/utsrelease.h' \
        -type f -printf '%T@ %p\n' |
        LC_ALL=C sort -nr |
        cut -d' ' -f2-
)
[[ -n $kernel_build ]] || \
    die "matching kernel build tree is unavailable for $kernel_version"

reset_directory "$probe_build"
reset_directory "$probe_stage"
rm -f -- "$probe_disk"
install -m0644 "$probe_source" "$probe_build/firmware_request_probe.c"
printf '%s\n' 'obj-m += firmware_request_probe.o' > "$probe_build/Makefile"
make -s -C "$kernel_build" M="$probe_build" modules
install -m0644 \
    "$probe_build/firmware_request_probe.ko" \
    "$probe_stage/firmware-request-probe.ko"
install -m0755 "$guest_checks" "$probe_stage/firmware-guest-checks.sh"
truncate -s 8M "$probe_disk"
mke2fs -q -F -t ext2 -L FWPROBE -d "$probe_stage" "$probe_disk"
cp "$ovmf_vars_template" "$ovmf_vars"

log "Booting EFI Linux to load iwlwifi and request $firmware_name"
set +e
{
    sleep 75
    printf '%s\n' 'stty -ixon -ixoff 2>/dev/null || true'
    sleep 1
    printf '%s\n' \
        'modprobe virtio_blk || { echo FAIL:firmware-probe-module; poweroff -f; exit; }'
    printf '%s\n' 'udevadm settle --timeout=10 2>/dev/null || true'
    printf '%s\n' \
        'test -b /dev/vda || { echo FAIL:firmware-probe-device; poweroff -f; exit; }'
    printf '%s\n' 'mkdir -p /mnt/firmware'
    printf '%s\n' \
        'mount -t ext2 -o ro /dev/vda /mnt/firmware || { echo FAIL:firmware-probe-mount; poweroff -f; exit; }'
    printf '%s\n' 'exec /mnt/firmware/firmware-guest-checks.sh'
} | timeout --signal=TERM 180s qemu-system-x86_64 \
    -machine q35,accel=tcg \
    -cpu "$qemu_cpu" \
    -m 2G \
    -drive if=pflash,format=raw,readonly=on,file="$ovmf_code" \
    -drive if=pflash,format=raw,file="$ovmf_vars" \
    -drive format=raw,file=fat:rw:"$EFILINUX_EFI_DIR" \
    -drive if=none,id=firmwareprobe,format=raw,file="$probe_disk" \
    -device virtio-blk-pci,drive=firmwareprobe \
    -display none \
    -serial stdio \
    -monitor none \
    -no-reboot \
    > "$boot_log" 2>&1
qemu_status=$?
set -e

if [[ $qemu_status -ne 0 && $qemu_status -ne 124 ]]; then
    tail -n 120 "$boot_log" >&2
    die "firmware QEMU exited unexpectedly with status $qemu_status"
fi

normalized_log="$EFILINUX_TEST/qemu-firmware-boot.normalized.log"
tr -d '\r' < "$boot_log" > "$normalized_log"
if grep -q 'Kernel panic' "$normalized_log" || grep -q '^FAIL:' "$normalized_log"; then
    tail -n 160 "$boot_log" >&2
    die "firmware acceptance guest reported a boot or setup failure"
fi
if ! grep -Fq \
    "EFILINUX_FIRMWARE_REQUEST_OK name=$firmware_name " \
    "$normalized_log"; then
    tail -n 160 "$boot_log" >&2
    die "kernel firmware loader did not resolve and read $firmware_name"
fi
if ! grep -Fxq 'EFILINUX_FIRMWARE_DRIVER_OK' "$normalized_log"; then
    tail -n 160 "$boot_log" >&2
    die "iwlwifi did not load before the firmware request probe"
fi

log "iwlwifi loaded and the kernel resolved the compressed AX210 firmware path"
printf 'Boot log: %s\n' "$boot_log"
