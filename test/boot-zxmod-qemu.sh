#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command qemu-system-x86_64 timeout mksquashfs
ensure_directories

qemu_cpu=${QEMU_CPU:-Nehalem}
ovmf_code=${OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}
ovmf_vars_template=${OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}
ovmf_vars="$EFILINUX_TEST/OVMF_VARS.zxmod.fd"
boot_log="$EFILINUX_LOGS/qemu-zxmod-boot.log"
efi_binary="$EFILINUX_EFI_DIR/EFI/BOOT/BOOTX64.EFI"
module_disk="$EFILINUX_TEST/zxmod-modules"
builder="$ROOT/005-utils/zxmod/files/usr/bin/zxmod-build"

[[ -f $efi_binary ]] || die "EFI binary is missing: $efi_binary"
[[ -f $ovmf_code ]] || die "OVMF code image is missing: $ovmf_code"
[[ -f $ovmf_vars_template ]] || die "OVMF variables image is missing: $ovmf_vars_template"
[[ -x $builder ]] || die "zxmod builder is missing: $builder"

rm -rf -- "$module_disk"
mkdir -p "$module_disk/sample/usr/bin" "$module_disk/sample/usr/share/zxmod-test" \
    "$module_disk/conflict/usr/bin"
printf '#!/bin/sh\nprintf zxmod-module-command\\n\n' > "$module_disk/sample/usr/bin/zxmod-module-command"
chmod 0755 "$module_disk/sample/usr/bin/zxmod-module-command"
printf 'held module payload\n' > "$module_disk/sample/usr/share/zxmod-test/held.txt"
printf 'conflicting replacement\n' > "$module_disk/conflict/usr/bin/zxmod"
"$builder" --id sample --version 1.0 --arch "$EFILINUX_ARCH" \
    "$module_disk/sample" "$module_disk/sample.zxm"
"$builder" --id conflict --version 1.0 --arch "$EFILINUX_ARCH" \
    "$module_disk/conflict" "$module_disk/conflict.zxm"
rm -rf -- "$module_disk/sample" "$module_disk/conflict"
cp -- "$ovmf_vars_template" "$ovmf_vars"

log "Booting EFI Linux for zxmod integration checks"
set +e
{
    sleep 75
    cat <<'GUEST_CHECKS'
fail() { printf 'EFILINUX_ZXMOD_FAIL:%s\n' "$1"; }
test "$(id -u)" = 0 || { fail not-root; poweroff -f; exit; }
mount -t vfat -o ro /dev/vda /mnt || { fail module-disk-mount; poweroff -f; exit; }
zxmod load /mnt/sample.zxm || fail module-load
test -x /usr/bin/zxmod-module-command || fail module-command-missing
test "$(/usr/bin/zxmod-module-command)" = zxmod-module-command || fail module-command-output
zxmod list | grep -Eq '^sample[[:space:]]' || fail module-list-after-load
touch /usr/share/zxmod-test/must-not-write 2>/dev/null && fail usr-view-writable
exec 3</usr/share/zxmod-test/held.txt || fail held-fd-open
zxmod load /mnt/conflict.zxm && fail conflicting-module-loaded
zxmod unload sample || fail module-unload
test ! -e /usr/bin/zxmod-module-command || fail module-path-remains-after-unload
IFS= read -r held_payload <&3 || fail held-fd-read
test "$held_payload" = 'held module payload' || fail held-fd-content
exec 3<&-
zxmod list | grep -Eq '^sample[[:space:]]' && fail module-list-remains-after-unload
printf 'EFILINUX_ZXMOD_OK\n'
poweroff -f
GUEST_CHECKS
} | timeout --signal=TERM 150s qemu-system-x86_64 \
    -machine q35,accel=tcg \
    -cpu "$qemu_cpu" \
    -m 2G \
    -drive if=pflash,format=raw,readonly=on,file="$ovmf_code" \
    -drive if=pflash,format=raw,file="$ovmf_vars" \
    -drive format=raw,readonly=on,file=fat:ro:"$EFILINUX_EFI_DIR" \
    -drive if=none,id=zxmodtest,format=raw,readonly=on,file=fat:ro:"$module_disk" \
    -device virtio-blk-pci,drive=zxmodtest \
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

log "zxmod load, conflict, read-only view, unload, and retained descriptor checks passed"
printf 'Boot log: %s\n' "$boot_log"
