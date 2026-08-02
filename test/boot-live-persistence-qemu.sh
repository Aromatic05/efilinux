#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command \
    debugfs \
    mkfs.ext4 \
    mkudffs \
    mksquashfs \
    python3 \
    qemu-system-x86_64 \
    timeout \
    truncate \
    xorriso
ensure_directories

qemu_cpu=${QEMU_CPU:-Nehalem}
ovmf_code=${OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}
ovmf_vars_template=${OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}
efi_binary="$EFILINUX_EFI_DIR/EFI/BOOT/BOOTX64.EFI"
work="$EFILINUX_TEST/live-persistence"
module_stage="$work/module-stage"
unmarked_module_stage="$work/unmarked-module-stage"
media_stage="$work/media-stage"
unmarked_stage="$work/unmarked-stage"
iso_stage="$work/iso-stage"
module_image="$media_stage/efilinux/modules/live-sample.zxm"
unmarked_module_image="$unmarked_stage/efilinux/modules/unmarked-sample.zxm"
media_disk="$work/live-media.img"
unmarked_disk="$work/unmarked-media.img"
iso_image="$work/live-media.iso"
udf_image="$work/live-media.udf"
persistence_copy="$work/persistence.img"
builder="$ROOT/005-utils/zxmod/files/usr/bin/zxmod-build"
persistence_helper="$ROOT/002-system/efilinux-live/files/usr/bin/efilinux-persistence-create"
guest_checks="$ROOT/test/helpers/live-persistence-guest.sh"

[[ -f $efi_binary ]] || die "EFI binary is missing: $efi_binary"
[[ -f $ovmf_code ]] || die "OVMF code image is missing: $ovmf_code"
[[ -f $ovmf_vars_template ]] || die "OVMF variables image is missing: $ovmf_vars_template"
[[ -x $builder ]] || die "zxmod builder is missing: $builder"
[[ -x $persistence_helper ]] || die "persistence helper is missing: $persistence_helper"
[[ -x $guest_checks ]] || die "live persistence guest checks are missing: $guest_checks"

reset_directory "$work"
mkdir -p \
    "$module_stage/usr/bin" \
    "$unmarked_module_stage/usr/bin" \
    "$media_stage/efilinux/modules" \
    "$unmarked_stage/efilinux/modules" \
    "$iso_stage/efilinux"
cat > "$module_stage/usr/bin/live-module-command" <<'MODULE'
#!/bin/sh
printf '%s\n' live-module-autoload-ok
MODULE
cat > "$unmarked_module_stage/usr/bin/unmarked-module-command" <<'MODULE'
#!/bin/sh
printf '%s\n' unmarked-module-must-not-load
MODULE
install -m0755 "$guest_checks" "$module_stage/usr/bin/live-persistence-guest"
chmod 0755 \
    "$module_stage/usr/bin/live-module-command" \
    "$unmarked_module_stage/usr/bin/unmarked-module-command"
"$builder" \
    --id live-sample \
    --version 1.0 \
    --arch "$EFILINUX_ARCH" \
    "$module_stage" \
    "$module_image"

"$builder" \
    --id unmarked-sample \
    --version 1.0 \
    --arch "$EFILINUX_ARCH" \
    "$unmarked_module_stage" \
    "$unmarked_module_image"
cat > "$unmarked_stage/efilinux/efilinux.conf" <<'CONFIG'
module modules/unmarked-sample.zxm
CONFIG
truncate -s 96M "$unmarked_disk"
mkfs.ext4 -q -F -L DATA -d "$unmarked_stage" "$unmarked_disk"

"$persistence_helper" "$media_stage" 96 >/dev/null
cat > "$media_stage/efilinux/efilinux.conf" <<'CONFIG'
module modules/live-sample.zxm
persistence persistence.img
CONFIG
truncate -s 192M "$media_disk"
mkfs.ext4 -q -F -L EFILINUX -d "$media_stage" "$media_disk"

printf '%s\n' efilinux-iso9660-ok > "$iso_stage/efilinux/iso-marker.txt"
printf '%s\n' '# ISO9660 media is enumerated but contributes no modules.' \
    > "$iso_stage/efilinux/efilinux.conf"
xorriso -as mkisofs -quiet -R -J -V EFILINUX -o "$iso_image" "$iso_stage"

mkudffs \
    --new-file \
    --blocksize=2048 \
    --media-type=hd \
    --label=EFILINUX \
    "$udf_image" 16384 >/dev/null

run_boot() {
    local boot_number=$1
    local ovmf_vars="$work/OVMF_VARS.$boot_number.fd"
    local boot_log="$EFILINUX_LOGS/qemu-live-persistence-$boot_number.log"
    local normalized_log="$work/qemu-live-persistence-$boot_number.normalized.log"
    local qemu_status

    cp "$ovmf_vars_template" "$ovmf_vars"
    log "Booting persistent EFI Linux pass $boot_number"
    set +e
    {
        sleep 90
        printf '%s\n' 'stty -ixon -ixoff 2>/dev/null || true'
        sleep 1
        printf '%s\n' "/usr/bin/live-persistence-guest $boot_number"
    } | timeout --signal=TERM 210s qemu-system-x86_64 \
        -machine q35,accel=tcg \
        -cpu "$qemu_cpu" \
        -m 2G \
        -drive if=pflash,format=raw,readonly=on,file="$ovmf_code" \
        -drive if=pflash,format=raw,file="$ovmf_vars" \
        -drive format=raw,file=fat:rw:"$EFILINUX_EFI_DIR" \
        -drive if=none,id=livemedia,format=raw,file="$media_disk" \
        -device virtio-blk-pci,drive=livemedia \
        -drive if=none,id=unmarkedmedia,format=raw,file="$unmarked_disk" \
        -device virtio-blk-pci,drive=unmarkedmedia \
        -drive if=none,id=udfmedia,format=raw,readonly=on,file="$udf_image" \
        -device virtio-blk-pci,drive=udfmedia \
        -drive media=cdrom,format=raw,readonly=on,file="$iso_image" \
        -display none \
        -serial stdio \
        -monitor none \
        -no-reboot \
        > "$boot_log" 2>&1
    qemu_status=$?
    set -e

    if [[ $qemu_status -ne 0 && $qemu_status -ne 124 ]]; then
        tail -n 180 "$boot_log" >&2
        die "live persistence QEMU pass $boot_number exited with status $qemu_status"
    fi

    python3 - "$boot_log" "$normalized_log" <<'PY'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1]).read_bytes().replace(b"\r", b"")
normalized = re.sub(rb"\x1b\[[0-?]*[ -/]*[@-~]", b"", source)
Path(sys.argv[2]).write_bytes(normalized)
PY
    if grep -q 'Kernel panic' "$normalized_log" || \
       grep -q '^EFILINUX_LIVE_FAIL:' "$normalized_log"; then
        tail -n 220 "$boot_log" >&2
        die "live persistence guest pass $boot_number reported a failure"
    fi
    for marker in \
        EFILINUX_LIVE_MEDIA_OK \
        EFILINUX_LIVE_MODULE_OK \
        "EFILINUX_LIVE_BOOT_${boot_number}_OK"; do
        grep -Fxq "$marker" "$normalized_log" || {
            tail -n 220 "$boot_log" >&2
            die "live persistence guest pass $boot_number did not report $marker"
        }
    done
}

run_boot 1
run_boot 2

grep -Fxq EFILINUX_LIVE_PERSISTENCE_WRITTEN \
    "$work/qemu-live-persistence-1.normalized.log" || \
    die "first boot did not write the persistent root marker"
grep -Fxq EFILINUX_LIVE_PERSISTENCE_RESTORED \
    "$work/qemu-live-persistence-2.normalized.log" || \
    die "second boot did not restore the persistent root marker"

debugfs -R "dump /efilinux/persistence.img $persistence_copy" \
    "$media_disk" >/dev/null 2>&1
persisted_value=$(debugfs -R 'cat /upper/etc/efilinux-live-persistent-marker' \
    "$persistence_copy" 2>/dev/null)
[[ $persisted_value == persisted-across-reboot ]] || \
    die "persistent marker is absent from the ext4 container after two boots"

log "Filesystem enumeration, module autoload, ISO9660/UDF reads, and persistent root replay passed across two boots"
printf 'Boot logs: %s\n' "$EFILINUX_LOGS/qemu-live-persistence-1.log"
printf '           %s\n' "$EFILINUX_LOGS/qemu-live-persistence-2.log"
