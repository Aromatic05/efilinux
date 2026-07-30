#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command readelf
rootfs=$EFILINUX_ROOTFS
loader="$rootfs/usr/lib/ld-linux-x86-64.so.2"
[[ -x $loader ]] || die "target loader is missing"

target() {
    "$loader" --library-path "$rootfs/usr/lib" "$@"
}

for command in file less curl rsync 7zz strace lsof dmidecode lspci ddrescue; do
    [[ -x "$rootfs/usr/bin/$command" ]] || die "application command is missing: $command"
done

target "$rootfs/usr/bin/less" --version >/dev/null
target "$rootfs/usr/bin/curl" --version >/dev/null
target "$rootfs/usr/bin/rsync" --version >/dev/null
target "$rootfs/usr/bin/7zz" >/dev/null
target "$rootfs/usr/bin/strace" -V >/dev/null
target "$rootfs/usr/bin/lsof" -v >/dev/null
target "$rootfs/usr/bin/dmidecode" --version >/dev/null
target "$rootfs/usr/bin/lspci" --version >/dev/null
target "$rootfs/usr/bin/ddrescue" --version >/dev/null

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
printf '\211PNG\r\n\032\n' > "$work/sample.png"
MAGIC="$rootfs/usr/share/misc/magic.mgc" \
    target "$rootfs/usr/bin/file" --brief "$work/sample.png" | \
    grep -Fqx 'PNG image data'

printf 'EFI Linux archive round trip\n' > "$work/payload.txt"
target "$rootfs/usr/bin/7zz" a -tzip "$work/payload.zip" "$work/payload.txt" >/dev/null
target "$rootfs/usr/bin/7zz" t "$work/payload.zip" >/dev/null
mkdir "$work/unpacked"
(cd "$work/unpacked" && target "$rootfs/usr/bin/7zz" x "$work/payload.zip" >/dev/null)
cmp "$work/payload.txt" "$work/unpacked/payload.txt"

while IFS= read -r binary; do
    while IFS= read -r needed; do
        [[ -e "$rootfs/usr/lib/$needed" ]] || \
            die "application ELF dependency is outside target rootfs: $binary needs $needed"
    done < <(readelf -d "$binary" | awk '/NEEDED/ { gsub(/\[|\]/, "", $NF); print $NF }')
done < <(find "$rootfs/usr/bin" -maxdepth 1 -type f -perm -u+x \( \
    -name file -o -name less -o -name curl -o -name rsync -o -name 7zz -o \
    -name strace -o -name lsof -o -name dmidecode -o -name lspci -o -name ddrescue \
    \) -print)

log "Applications execute under the target loader; archive, libmagic, and ELF closure checks passed"
