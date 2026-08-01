#!/usr/bin/env bash

set -euo pipefail

MODULE_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(cd -- "$MODULE_DIR/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command mcopy mkfs.fat qemu-system-x86_64 timeout truncate
ensure_directories

qemu_cpu=${QEMU_CPU:-Nehalem}
ovmf_code=${OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}
ovmf_vars_template=${OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}
ovmf_vars="$EFILINUX_TEST/OVMF_VARS.recovery.fd"
efi_binary="$EFILINUX_EFI_DIR/EFI/BOOT/BOOTX64.EFI"
artifact="$ROOT/modules/output/001-recovery.zxm"
guest_checks="$MODULE_DIR/tests/qemu-guest.sh"
module_disk="$EFILINUX_TEST/recovery-module.img"
boot_log="$EFILINUX_LOGS/qemu-recovery-module.log"
normalized_log="$EFILINUX_TEST/qemu-recovery-module.normalized.log"

[[ -f $efi_binary ]] || die "EFI binary is missing: $efi_binary"
[[ -f $artifact ]] || die "recovery module is missing: $artifact"
[[ -x $guest_checks ]] || die "recovery guest checks are missing: $guest_checks"
[[ -f $ovmf_code ]] || die "OVMF code image is missing: $ovmf_code"
[[ -f $ovmf_vars_template ]] || die "OVMF variables image is missing: $ovmf_vars_template"

rm -f -- "$module_disk"
truncate -s 128M "$module_disk"
mkfs.fat -F 32 -n RECOVERY "$module_disk" >/dev/null
mcopy -i "$module_disk" "$artifact" ::/001-recovery.zxm
mcopy -i "$module_disk" "$guest_checks" ::/recovery-guest.sh
cp -- "$ovmf_vars_template" "$ovmf_vars"

log "Booting EFI Linux for recovery module integration checks"
set +e
{
    sleep 75
    printf '%s\n' 'stty -ixon -ixoff 2>/dev/null || true'
    sleep 1
    printf '%s\n' 'modprobe virtio_blk || { echo EFILINUX_RECOVERY_FAIL:virtio-blk-module; poweroff -f; exit; }'
    printf '%s\n' 'udevadm settle --timeout=10 2>/dev/null || true'
    printf '%s\n' 'test -b /dev/vda || { echo EFILINUX_RECOVERY_FAIL:module-disk-device; cat /proc/partitions; poweroff -f; exit; }'
    printf '%s\n' 'mkdir -p /mnt'
    printf '%s\n' 'mount -t vfat -o rw /dev/vda /mnt || { echo EFILINUX_RECOVERY_FAIL:module-disk-mount; poweroff -f; exit; }'
    printf '%s\n' 'exec /usr/bin/sh /mnt/recovery-guest.sh'
} | timeout --signal=TERM 210s qemu-system-x86_64 \
    -machine q35,accel=tcg \
    -cpu "$qemu_cpu" \
    -m 2G \
    -drive if=pflash,format=raw,readonly=on,file="$ovmf_code" \
    -drive if=pflash,format=raw,file="$ovmf_vars" \
    -drive format=raw,file=fat:rw:"$EFILINUX_EFI_DIR" \
    -drive if=virtio,format=raw,file="$module_disk" \
    -display none \
    -serial stdio \
    -monitor none \
    -no-reboot \
    > "$boot_log" 2>&1
qemu_status=$?
set -e

if [[ $qemu_status -ne 0 && $qemu_status -ne 124 ]]; then
    tail -n 180 "$boot_log" >&2
    die "recovery QEMU exited unexpectedly with status $qemu_status"
fi

tr -d '\r' < "$boot_log" > "$normalized_log"
if grep -q 'Kernel panic' "$normalized_log"; then
    tail -n 180 "$boot_log" >&2
    die "kernel panic detected during recovery module boot"
fi
if grep -q '^EFILINUX_RECOVERY_FAIL:' "$normalized_log"; then
    tail -n 220 "$boot_log" >&2
    die "recovery module guest checks reported a failure"
fi
if ! grep -Fxq 'EFILINUX_RECOVERY_OK' "$normalized_log"; then
    tail -n 220 "$boot_log" >&2
    die "recovery module guest checks did not complete"
fi

log "Recovery ZXM load, command probes, kernel clients, NBD round trip, and unload checks passed"
printf 'Boot log: %s\n' "$boot_log"
