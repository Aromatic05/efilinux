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
ovmf_vars="$EFILINUX_TEST/OVMF_VARS.fd"
boot_log="$EFILINUX_LOGS/qemu-boot.log"
efi_binary="$EFILINUX_EFI_DIR/EFI/BOOT/BOOTX64.EFI"

[[ -f "$efi_binary" ]] || die "EFI binary is missing: $efi_binary"
[[ -f "$ovmf_code" ]] || die "OVMF code image is missing: $ovmf_code"
[[ -f "$ovmf_vars_template" ]] || \
    die "OVMF variables image is missing: $ovmf_vars_template"

cp "$ovmf_vars_template" "$ovmf_vars"

log "Booting EFI Linux with QEMU CPU model $qemu_cpu"
set +e
{
    sleep 75
    printf '%s\n' \
        "test \"\$(cat /proc/1/comm)\" = init && /usr/bin/printf 'EFILINUX_PID1=init\\n' && /usr/bin/udevadm control --ping && for service in syslogd dbus crond dhcpcd sshd; do test -s /run/efilinux/\$service.pid && kill -0 \"\$(cat /run/efilinux/\$service.pid)\" || exit 1; done && /usr/bin/printf 'EFILINUX_SERVICES_OK\\n' && /usr/bin/modprobe --version && /usr/bin/modprobe loop && /usr/bin/lsmod && /usr/bin/printf 'EFILINUX_MODULE_LOAD_OK\\n' && /usr/bin/poweroff -f"
} | timeout --signal=TERM 150s qemu-system-x86_64 \
    -machine q35,accel=tcg \
    -cpu "$qemu_cpu" \
    -m 2G \
    -drive if=pflash,format=raw,readonly=on,file="$ovmf_code" \
    -drive if=pflash,format=raw,file="$ovmf_vars" \
    -drive format=raw,file=fat:rw:"$EFILINUX_EFI_DIR" \
    -display none \
    -serial stdio \
    -monitor none \
    -no-reboot \
    > "$boot_log" 2>&1
qemu_status=$?
set -e

if [[ "$qemu_status" -ne 0 && "$qemu_status" -ne 124 ]]; then
    tail -n 80 "$boot_log" >&2
    die "QEMU exited unexpectedly with status $qemu_status"
fi

if grep -q 'Kernel panic' "$boot_log"; then
    tail -n 80 "$boot_log" >&2
    die "kernel panic detected"
fi

if ! grep -q 'INIT: Entering runlevel: 3' "$boot_log" || \
   ! grep -q 'EFILINUX_PID1=init' "$boot_log" || \
   ! grep -q 'EFILINUX_SERVICES_OK' "$boot_log"; then
    tail -n 120 "$boot_log" >&2
    die "SysVinit or the multi-user service set did not become operational"
fi

if ! grep -q 'kmod version' "$boot_log" || \
   ! grep -q 'EFILINUX_MODULE_LOAD_OK' "$boot_log" || \
   ! grep -Eq '^loop[[:space:]]' "$boot_log"; then
    tail -n 120 "$boot_log" >&2
    die "Kmod failed to load a compressed kernel module from rootfs"
fi

log "OVMF boot reached SysVinit multi-user mode with services and Kmod operational"
printf 'Boot log: %s\n' "$boot_log"
