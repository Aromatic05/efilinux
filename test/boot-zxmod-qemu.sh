#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command qemu-system-x86_64 timeout mksquashfs mkfs.fat mcopy truncate
ensure_directories

qemu_cpu=${QEMU_CPU:-Nehalem}
ovmf_code=${OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}
ovmf_vars_template=${OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}
ovmf_vars="$EFILINUX_TEST/OVMF_VARS.zxmod.fd"
boot_log="$EFILINUX_LOGS/qemu-zxmod-boot.log"
efi_binary="$EFILINUX_EFI_DIR/EFI/BOOT/BOOTX64.EFI"
module_stage="$EFILINUX_TEST/zxmod-modules"
module_disk="$EFILINUX_TEST/zxmod-modules.img"
builder="$ROOT/005-utils/zxmod/files/usr/bin/zxmod-build"
guest_checks="$ROOT/test/helpers/zxmod-guest-checks.sh"

[[ -f $efi_binary ]] || die "EFI binary is missing: $efi_binary"
[[ -f $ovmf_code ]] || die "OVMF code image is missing: $ovmf_code"
[[ -f $ovmf_vars_template ]] || die "OVMF variables image is missing: $ovmf_vars_template"
[[ -x $builder ]] || die "zxmod builder is missing: $builder"
[[ -x $guest_checks ]] || die "zxmod guest checks are missing: $guest_checks"

rm -rf -- "$module_stage"
rm -f -- "$module_disk"
mkdir -p "$module_stage/sample/usr/bin" "$module_stage/sample/usr/share/zxmod-test" \
    "$module_stage/conflict/usr/bin"
cat > "$module_stage/sample/usr/bin/zxmod-module-command" <<'MODULE_COMMAND'
#!/bin/sh
printf '%s\n' zxmod-module-command
MODULE_COMMAND
chmod 0755 "$module_stage/sample/usr/bin/zxmod-module-command"
printf 'held module payload\n' > "$module_stage/sample/usr/share/zxmod-test/held.txt"
printf 'conflicting replacement\n' > "$module_stage/conflict/usr/bin/zxmod"
"$builder" --id sample --version 1.0 --arch "$EFILINUX_ARCH" \
    "$module_stage/sample" "$module_stage/sample.zxm"
"$builder" --id conflict --version 1.0 --arch "$EFILINUX_ARCH" \
    "$module_stage/conflict" "$module_stage/conflict.zxm"
rm -rf -- "$module_stage/sample" "$module_stage/conflict"
truncate -s 64M "$module_disk"
mkfs.fat -F 32 -n ZXMODTEST "$module_disk" >/dev/null
mcopy -i "$module_disk" \
    "$module_stage/sample.zxm" \
    "$module_stage/conflict.zxm" \
    "$guest_checks" \
    ::/
cp -- "$ovmf_vars_template" "$ovmf_vars"

log "Booting EFI Linux for zxmod integration checks"
set +e
{
    sleep 75
    printf '%s\n' 'stty -ixon -ixoff 2>/dev/null || true'
    sleep 1
    printf '%s\n' 'modprobe virtio_blk || { echo EFILINUX_ZXMOD_FAIL:virtio-blk-module; poweroff -f; exit; }'
    printf '%s\n' 'udevadm settle --timeout=10 2>/dev/null || true'
    printf '%s\n' 'test -b /dev/vda || { echo EFILINUX_ZXMOD_FAIL:module-disk-device; cat /proc/partitions; poweroff -f; exit; }'
    printf '%s\n' 'mkdir -p /mnt'
    printf '%s\n' 'mount -t vfat -o rw /dev/vda /mnt || { echo EFILINUX_ZXMOD_FAIL:module-disk-mount; poweroff -f; exit; }'
    printf '%s\n' 'exec /usr/bin/sh /mnt/zxmod-guest-checks.sh'
} | timeout --signal=TERM 150s qemu-system-x86_64 \
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
    tail -n 120 "$boot_log" >&2
    die "zxmod QEMU exited unexpectedly with status $qemu_status"
fi

normalized_log="$EFILINUX_TEST/qemu-zxmod-boot.normalized.log"
tr -d '\r' < "$boot_log" > "$normalized_log"
if grep -q 'Kernel panic' "$normalized_log"; then
    tail -n 120 "$boot_log" >&2
    die "kernel panic detected during zxmod boot"
fi
if grep -q '^EFILINUX_ZXMOD_FAIL:' "$normalized_log"; then
    tail -n 160 "$boot_log" >&2
    die "zxmod guest checks reported a failure"
fi
if ! grep -Fxq 'EFILINUX_ZXMOD_OK' "$normalized_log"; then
    tail -n 160 "$boot_log" >&2
    die "zxmod guest checks did not complete"
fi

log "zxmod load, conflict, read-only view, persistence, unload, and retained descriptor checks passed"
printf 'Boot log: %s\n' "$boot_log"
