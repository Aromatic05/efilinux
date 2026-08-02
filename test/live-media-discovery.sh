#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/002-system/efilinux-live/files/usr/lib/efilinux/live-common.sh"

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

cat > "$work/lsblk" <<'EOF'
#!/bin/sh
cat <<'INVENTORY'
/dev/test-unmarked part
/dev/test-marked-a part
/dev/test-marked-b part
/dev/test-marked-c part
/dev/test-slow part
INVENTORY
EOF

cat > "$work/udevadm" <<'EOF'
#!/bin/sh
set -eu

if [ "$1" = settle ]; then
    exit 0
fi

[ "$1" = info ]
shift
while [ $# -gt 0 ]; do
    case $1 in
        --name)
            device=$2
            shift 2
            ;;
        *) shift ;;
    esac
done

case ${device:-} in
    /dev/test-unmarked)
        printf '%s\n' ID_FS_TYPE=ext4 ID_FS_LABEL=DATA
        ;;
    /dev/test-marked-a)
        printf '%s\n' ID_FS_TYPE=ext4 ID_FS_LABEL=EFILINUX
        ;;
    /dev/test-marked-b)
        printf '%s\n' ID_FS_TYPE=iso9660 ID_FS_LABEL=EFILINUX
        ;;
    /dev/test-marked-c)
        printf '%s\n' ID_FS_TYPE=udf ID_FS_LABEL=EFILINUX
        ;;
    /dev/test-slow)
        sleep 2
        printf '%s\n' ID_FS_TYPE=ext4 ID_FS_LABEL=EFILINUX
        ;;
    *) exit 1 ;;
esac
EOF
chmod 0755 "$work/lsblk" "$work/udevadm"

export EFILINUX_LIVE_LSBLK="$work/lsblk"
export EFILINUX_LIVE_UDEVADM="$work/udevadm"
export EFILINUX_LIVE_MEDIA_LABEL=EFILINUX
export EFILINUX_LIVE_MAX_BLOCK_DEVICES=5
export EFILINUX_LIVE_MAX_MEDIA=2
export EFILINUX_LIVE_METADATA_TIMEOUT=1

live_collect_block_metadata > "$work/metadata"
live_filter_labeled_media < "$work/metadata" > "$work/candidates"

cat > "$work/expected" <<'EOF'
/dev/test-marked-a	part	ext4
/dev/test-marked-b	part	iso9660
EOF
cmp "$work/expected" "$work/candidates"

if grep -Fq /dev/test-unmarked "$work/candidates"; then
    die "unmarked media entered the mount candidate set"
fi
if grep -Fq /dev/test-slow "$work/metadata"; then
    die "a timed-out udev metadata query entered the inventory"
fi

log "Live media discovery uses bounded udev metadata and accepts only the EFILINUX filesystem label"
