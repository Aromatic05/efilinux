#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command gcc mke2fs qemu-system-x86_64 readelf timeout truncate
ensure_directories

qemu_cpu=${QEMU_CPU:-Nehalem}
ovmf_code=${OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}
ovmf_vars_template=${OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}
ovmf_vars="$EFILINUX_TEST/OVMF_VARS.graphical.fd"
boot_log="$EFILINUX_LOGS/qemu-graphical-boot.log"
efi_binary="$EFILINUX_EFI_DIR/EFI/BOOT/BOOTX64.EFI"
probe_source="$ROOT/test/helpers/glx-llvmpipe-probe.c"
guest_checks="$ROOT/test/helpers/graphical-guest-checks.sh"
probe_binary="$EFILINUX_TEST/glx-llvmpipe-probe"
probe_stage="$EFILINUX_TEST/glx-llvmpipe-stage"
probe_disk="$EFILINUX_TEST/glx-llvmpipe.img"

[[ -f "$efi_binary" ]] || die "EFI binary is missing: $efi_binary"
[[ -f "$ovmf_code" ]] || die "OVMF code image is missing: $ovmf_code"
[[ -f "$ovmf_vars_template" ]] || \
    die "OVMF variables image is missing: $ovmf_vars_template"
[[ -f "$probe_source" ]] || die "GLX llvmpipe probe source is missing: $probe_source"
[[ -x "$guest_checks" ]] || die "graphical guest checks are missing: $guest_checks"

(
    source "$ROOT/profiles/makepkg.conf"
    gcc $CFLAGS "$probe_source" -o "$probe_binary" \
        $LDFLAGS -lGL -lX11 -ldl -lm
)
while IFS= read -r needed; do
    [[ -e "$EFILINUX_ROOTFS/usr/lib/$needed" ]] ||
        die "GLX probe dependency is outside the rootfs: $needed"
done < <(LC_ALL=C readelf -d "$probe_binary" |
    awk '/NEEDED/ { gsub(/\[|\]/, "", $NF); print $NF }')

rm -rf -- "$probe_stage"
rm -f -- "$probe_disk"
mkdir -p "$probe_stage"
install -m0755 "$probe_binary" "$probe_stage/glx-llvmpipe-probe"
install -m0755 "$guest_checks" "$probe_stage/graphical-guest-checks.sh"
cat > "$probe_stage/fake-efilinux-livectl" <<'EOF'
#!/bin/sh
case ${1:-} in
    snapshot) exit 0 ;;
    *) exit 2 ;;
esac
EOF
chmod 0755 "$probe_stage/fake-efilinux-livectl"
truncate -s 16M "$probe_disk"
mke2fs -q -F -t ext2 -L GLXPROBE -d "$probe_stage" "$probe_disk"

cp "$ovmf_vars_template" "$ovmf_vars"

log "Booting graphical EFI Linux with VirtIO-GPU"
set +e
{
    sleep 100
    printf '%s\n' 'stty -ixon -ixoff 2>/dev/null || true'
    sleep 1
    printf '%s\n' 'modprobe virtio_blk || { echo FAIL:virtio-blk-module; poweroff -f; exit; }'
    printf '%s\n' 'udevadm settle --timeout=10 2>/dev/null || true'
    printf '%s\n' 'test -b /dev/vda || { echo FAIL:glx-probe-device; cat /proc/partitions; poweroff -f; exit; }'
    printf '%s\n' 'mkdir -p /mnt/glx-probe'
    printf '%s\n' 'mount -t ext2 -o ro /dev/vda /mnt/glx-probe || { echo FAIL:glx-probe-mount; poweroff -f; exit; }'
    printf '%s\n' 'exec /mnt/glx-probe/graphical-guest-checks.sh'
} | timeout --signal=TERM 220s qemu-system-x86_64 \
    -machine q35,accel=tcg \
    -cpu "$qemu_cpu" \
    -smp 4 \
    -m 3G \
    -drive if=pflash,format=raw,readonly=on,file="$ovmf_code" \
    -drive if=pflash,format=raw,file="$ovmf_vars" \
    -drive format=raw,file=fat:rw:"$EFILINUX_EFI_DIR" \
    -drive if=none,id=glxprobe,format=raw,file="$probe_disk" \
    -device virtio-blk-pci,drive=glxprobe \
    -vga none \
    -device virtio-vga \
    -device qemu-xhci,id=xhci \
    -device usb-tablet,bus=xhci.0 \
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

normalized_log="$EFILINUX_TEST/qemu-graphical-boot.normalized.log"
tr -d '\r' < "$boot_log" > "$normalized_log"
if grep -q '^FAIL:' "$normalized_log"; then
    tail -n 200 "$boot_log" >&2
    die "graphical guest checks reported a failure"
fi
if ! grep -Fxq 'EFILINUX_XFCE_OK' "$normalized_log"; then
    tail -n 200 "$boot_log" >&2
    die "Xorg and the XFCE desktop did not become operational on VirtIO-GPU"
fi
for marker in \
    EFILINUX_GL_RENDERER=llvmpipe \
    EFILINUX_GL_SHADER_OK \
    EFILINUX_GL_COMPUTE_OK \
    EFILINUX_LIVE_MANAGER_GUI_OK; do
    grep -Fxq "$marker" "$normalized_log" || {
        tail -n 240 "$boot_log" >&2
        die "graphical guest did not report $marker"
    }
done
if ! grep -Eq '^EFILINUX_LLVMPIPE_THREADS=[2-9][0-9]*$' "$normalized_log"; then
    tail -n 240 "$boot_log" >&2
    die "llvmpipe did not report multiple worker threads"
fi

log "OVMF boot reached XFCE and completed llvmpipe GLX, GLSL, compute, and threading checks"
printf 'Boot log: %s\n' "$boot_log"
