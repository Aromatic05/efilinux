#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command qemu-system-x86_64 timeout
ensure_directories

qemu_cpu=${QEMU_CPU:-Nehalem}
ovmf_code=${OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}
ovmf_vars_template=${OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}
ovmf_vars="$EFILINUX_TEST/OVMF_VARS.graphical.fd"
boot_log="$EFILINUX_LOGS/qemu-graphical-boot.log"
efi_binary="$EFILINUX_EFI_DIR/EFI/BOOT/BOOTX64.EFI"

[[ -f "$efi_binary" ]] || die "EFI binary is missing: $efi_binary"
[[ -f "$ovmf_code" ]] || die "OVMF code image is missing: $ovmf_code"
[[ -f "$ovmf_vars_template" ]] || \
    die "OVMF variables image is missing: $ovmf_vars_template"

cp "$ovmf_vars_template" "$ovmf_vars"

log "Booting graphical EFI Linux with VirtIO-GPU"
set +e
{
    sleep 100
    printf '%s\n' \
        "test \"\$(cat /run/efilinux/runlevel)\" = 5 && test -S /tmp/.X11-unix/X0 && test -s /run/efilinux/graphical.pid && kill -0 \"\$(cat /run/efilinux/graphical.pid)\" && pidof Xorg >/dev/null && pidof gtk3-demo >/dev/null && DISPLAY=:0 XAUTHORITY=/root/.Xauthority /usr/bin/xdpyinfo >/dev/null && /usr/bin/printf 'EFILINUX_GRAPHICAL_OK\\n' && /usr/bin/poweroff -f"
} | timeout --signal=TERM 180s qemu-system-x86_64 \
    -machine q35,accel=tcg \
    -cpu "$qemu_cpu" \
    -m 3G \
    -drive if=pflash,format=raw,readonly=on,file="$ovmf_code" \
    -drive if=pflash,format=raw,file="$ovmf_vars" \
    -drive format=raw,file=fat:rw:"$EFILINUX_EFI_DIR" \
    -vga none \
    -device virtio-vga \
    -display none \
    -serial stdio \
    -monitor none \
    -no-reboot \
    > "$boot_log" 2>&1
qemu_status=$?
set -e

if [[ "$qemu_status" -ne 0 && "$qemu_status" -ne 124 ]]; then
    tail -n 100 "$boot_log" >&2
    die "graphical QEMU exited unexpectedly with status $qemu_status"
fi

if grep -q 'Kernel panic' "$boot_log"; then
    tail -n 100 "$boot_log" >&2
    die "kernel panic detected during graphical boot"
fi

if ! grep -q 'INIT: Entering runlevel: 5' "$boot_log" || \
   ! grep -q 'EFILINUX_GRAPHICAL_OK' "$boot_log"; then
    tail -n 160 "$boot_log" >&2
    die "Xorg and GTK did not become operational on VirtIO-GPU"
fi

log "OVMF boot reached a live Xorg and GTK 3 session on VirtIO-GPU"
printf 'Boot log: %s\n' "$boot_log"
