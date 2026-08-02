#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command awk blkid mkfs.ext4 mksquashfs unsquashfs

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
media="$work/media"
source_tree="$work/source"
source_module="$work/imported.zxm"
run_root="$work/run"
mkdir -p "$media/efilinux" "$source_tree/usr/bin" "$run_root"
cat > "$source_tree/usr/bin/live-manager-sample" <<'EOF'
#!/bin/sh
printf '%s\n' live-manager-sample
EOF
chmod 0755 "$source_tree/usr/bin/live-manager-sample"
"$ROOT/005-utils/zxmod/files/usr/bin/zxmod-build" \
    --id live-manager-sample \
    --version 1.0 \
    --description 'Live manager fixture' \
    --arch "$EFILINUX_ARCH" \
    "$source_tree" \
    "$source_module"
printf '/dev/test\t%s\t0\text4\n' "$media" > "$run_root/media.tsv"
: > "$media/efilinux/efilinux.conf"

livectl() {
    EFILINUX_LIVE_LIBRARY="$ROOT/002-system/efilinux-live/files/usr/lib/efilinux/live-common.sh" \
    EFILINUX_LIVE_SKIP_SCAN=1 \
    EFILINUX_LIVE_ASSUME_WRITABLE=1 \
    EFILINUX_LIVE_ASSUME_ROOT=1 \
    EFILINUX_LIVE_RUN_ROOT="$run_root" \
    EFILINUX_LIVE_MEDIA_ROOT="$run_root/media" \
    EFILINUX_LIVE_MEDIA_FILE="$run_root/media.tsv" \
    EFILINUX_PERSISTENCE_CREATE="$ROOT/002-system/efilinux-live/files/usr/bin/efilinux-persistence-create" \
        "$ROOT/002-system/efilinux-live/files/usr/bin/efilinux-livectl" "$@"
}

livectl module-import /dev/test "$source_module"
livectl snapshot > "$work/snapshot.imported"
awk -F '\t' '
    $1 == "MODULE" && $2 == "/dev/test" && $4 == "modules/imported.zxm" &&
    $5 == "live-manager-sample" && $6 == "1.0" && $10 == "0" { found=1 }
    END { exit !found }
' "$work/snapshot.imported"

livectl module-autoload /dev/test modules/imported.zxm on
livectl snapshot > "$work/snapshot.autoload"
awk -F '\t' '
    $1 == "MODULE" && $4 == "modules/imported.zxm" && $10 == "1" { found=1 }
    END { exit !found }
' "$work/snapshot.autoload"

if livectl module-autoload /dev/test ../escape.zxm on >/dev/null 2>&1; then
    die 'live manager accepted a traversal path'
fi

livectl persistence-create /dev/test 64 >/dev/null
livectl snapshot > "$work/snapshot.persistence"
awk -F '\t' '
    $1 == "PERSISTENCE" && $2 == "/dev/test" && $4 == "1" && $5 == "1" && $7 >= 67108864 { found=1 }
    END { exit !found }
' "$work/snapshot.persistence"
[[ $(blkid -p -s TYPE -o value "$media/efilinux/persistence.img") == ext4 ]] ||
    die 'live manager persistence container is not ext4'

livectl persistence-disable /dev/test
livectl snapshot > "$work/snapshot.disabled"
awk -F '\t' '
    $1 == "PERSISTENCE" && $2 == "/dev/test" && $4 == "0" && $5 == "1" { found=1 }
    END { exit !found }
' "$work/snapshot.disabled"

livectl module-remove /dev/test modules/imported.zxm
livectl snapshot > "$work/snapshot.removed"
if awk -F '\t' '$1 == "MODULE" { found=1 } END { exit !found }' "$work/snapshot.removed"; then
    die 'live manager did not remove the module from media'
fi

mv "$media/efilinux/efilinux.conf" "$media/efilinux/efilinux.conf.real"
printf 'persistence persistence.img\n' > "$work/external.conf"
ln -s "$work/external.conf" "$media/efilinux/efilinux.conf"
if livectl persistence-enable /dev/test >/dev/null 2>&1; then
    die 'live manager modified a symbolic-link configuration'
fi
rm "$media/efilinux/efilinux.conf"
mv "$media/efilinux/efilinux.conf.real" "$media/efilinux/efilinux.conf"

log 'Live manager import, inventory, autoload, persistence, path safety, and removal passed'
