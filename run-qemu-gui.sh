#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

usage() {
    cat <<'USAGE'
Usage: ./run-qemu-gui.sh [--reset-nvram] [--fullscreen] [--dry-run]

Start the built EFI Linux image with VirtIO-GPU in a GTK QEMU window.
Available modules from modules/output are included under /modules on the EFI drive.
The GTK window contains display, serial-console, and QEMU-monitor tabs.

Environment overrides:
  QEMU_MEMORY       Guest memory (default: 4G)
  QEMU_SMP          Guest CPU topology/count (default: 4)
  QEMU_SSH_PORT     Host TCP port forwarded to guest SSH port 22 (default: 2222)
  QEMU_DISPLAY      QEMU GTK display options
  QEMU_BINARY       QEMU executable (default: qemu-system-x86_64)
  OVMF_CODE         Read-only OVMF code image
  OVMF_VARS         OVMF variable-store template
USAGE
}

reset_nvram=0
fullscreen=0
dry_run=0

while (($# > 0)); do
    case $1 in
        --reset-nvram) reset_nvram=1 ;;
        --fullscreen) fullscreen=1 ;;
        --dry-run) dry_run=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done

qemu_binary=${QEMU_BINARY:-qemu-system-x86_64}
qemu_memory=${QEMU_MEMORY:-4G}
qemu_smp=${QEMU_SMP:-4}
qemu_ssh_port=${QEMU_SSH_PORT:-2222}
qemu_display=${QEMU_DISPLAY:-gtk,gl=off,show-tabs=on,zoom-to-fit=on,window-close=on}
ovmf_code=${OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}
ovmf_vars_template=${OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}
ovmf_vars="$EFILINUX_TEST/OVMF_VARS.gui.fd"
efi_binary="$EFILINUX_EFI_DIR/EFI/BOOT/BOOTX64.EFI"
module_output_dir="$ROOT/modules/output"
qemu_efi_dir="$EFILINUX_TEST/qemu-gui-efi"
qemu_module_dir="$qemu_efi_dir/modules"

require_command "$qemu_binary" cp grep id install mkdir
ensure_directories

[[ -f "$efi_binary" ]] || die "EFI binary is missing; run ./build.sh first: $efi_binary"
[[ -f "$ovmf_code" ]] || die "OVMF code image is missing: $ovmf_code"
[[ -f "$ovmf_vars_template" ]] || die "OVMF variable-store template is missing: $ovmf_vars_template"
[[ -c /dev/kvm ]] || die "/dev/kvm is unavailable; load KVM and verify virtualization is enabled"
[[ -r /dev/kvm && -w /dev/kvm ]] || \
    die "user $(id -un) cannot access /dev/kvm"
"$qemu_binary" -accel help 2>/dev/null | grep -qx kvm || \
    die "$qemu_binary was built without KVM support"

if [[ -z ${DISPLAY:-} && -z ${WAYLAND_DISPLAY:-} ]]; then
    die "no graphical display is available (DISPLAY and WAYLAND_DISPLAY are unset)"
fi

reset_directory "$qemu_efi_dir"
cp -a --reflink=auto "$EFILINUX_EFI_DIR/." "$qemu_efi_dir/"
install -d -m0755 "$qemu_module_dir"

module_artifacts=()
if [[ -d "$module_output_dir" ]]; then
    shopt -s nullglob
    module_artifacts=("$module_output_dir"/*.zxm)
    shopt -u nullglob
fi
for module_artifact in "${module_artifacts[@]}"; do
    cp -a --reflink=auto "$module_artifact" "$qemu_module_dir/"
done

if ((reset_nvram)) || [[ ! -f "$ovmf_vars" ]]; then
    cp -- "$ovmf_vars_template" "$ovmf_vars"
fi

if ((fullscreen)); then
    qemu_display+=",full-screen=on"
fi

qemu_command=(
    "$qemu_binary"
    -name "EFI Linux"
    -machine "q35,accel=kvm"
    -cpu host
    -smp "$qemu_smp"
    -m "$qemu_memory"
    -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code"
    -drive "if=pflash,format=raw,file=$ovmf_vars"
    -drive "format=raw,file=fat:rw:$qemu_efi_dir"
    -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:$qemu_ssh_port-:22"
    -device "e1000e,netdev=net0"
    -device "qemu-xhci,id=xhci"
    -device "usb-tablet,bus=xhci.0"
    -vga none
    -device virtio-vga
    -display "$qemu_display"
    -serial vc
    -monitor vc
    -no-reboot
)

printf 'EFI image:  %s\n' "$efi_binary"
printf 'EFI drive:  %s\n' "$qemu_efi_dir"
printf 'Modules:    %s packaged under /modules\n' "${#module_artifacts[@]}"
for module_artifact in "${module_artifacts[@]}"; do
    printf '            %s\n' "${module_artifact##*/}"
done
printf 'NVRAM:      %s\n' "$ovmf_vars"
printf 'KVM:        enabled, CPU=host, SMP=%s, memory=%s\n' "$qemu_smp" "$qemu_memory"
printf 'SSH:        127.0.0.1:%s -> guest:22\n' "$qemu_ssh_port"
printf 'GTK tabs:   VirtIO-GPU display, serial console, QEMU monitor\n'

if ((dry_run)); then
    printf 'Command:'
    printf ' %q' "${qemu_command[@]}"
    printf '\n'
    exit 0
fi

exec "${qemu_command[@]}"
