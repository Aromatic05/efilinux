#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command blkid dumpe2fs mkfs.ext4 python3

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
run_root="$work/run"
media_a="$work/media-a"
media_b="$work/media-b"
mkdir -p \
    "$run_root" \
    "$media_a/efilinux/modules" \
    "$media_b/efilinux/modules" \
    "$work/outside"
printf module-a > "$media_a/efilinux/modules/a.zxm"
printf module-b > "$media_b/efilinux/modules/b.zxm"
printf escaped > "$work/outside/escaped.zxm"
ln -s "$work/outside" "$media_a/efilinux/modules/escape"

cat > "$media_a/efilinux/efilinux.conf" <<'EOF'
# The same logical module is declared twice across media and must load once.
module modules/a.zxm
module ../escape.zxm
module modules/escape/escaped.zxm
persistence persistence.img
EOF
cat > "$media_b/efilinux/efilinux.conf" <<'EOF'
module modules/a.zxm
module modules/b.zxm
unknown ignored
EOF

printf '/dev/test-a\t%s\t0\text4\n' "$media_a" > "$run_root/media.tsv"
printf '/dev/test-b\t%s\t0\tiso9660\n' "$media_b" >> "$run_root/media.tsv"

cat > "$work/zxmod" <<'EOF'
#!/bin/sh
set -eu
[ "$1" = load ]
printf '%s\n' "$(basename "$2")" >> "$EFILINUX_TEST_ZXMOD_LOG"
EOF
chmod 0755 "$work/zxmod"

EFILINUX_LIVE_LIBRARY="$ROOT/002-system/efilinux-live/files/usr/lib/efilinux/live-common.sh" \
EFILINUX_LIVE_SKIP_SCAN=1 \
EFILINUX_LIVE_RUN_ROOT="$run_root" \
EFILINUX_LIVE_MEDIA_FILE="$run_root/media.tsv" \
EFILINUX_LIVE_ZXMOD="$work/zxmod" \
EFILINUX_TEST_ZXMOD_LOG="$work/zxmod.log" \
    "$ROOT/002-system/efilinux-live/files/usr/libexec/efilinux-live-modules" \
    2> "$work/modules.stderr"

cat > "$work/expected-modules" <<'EOF'
a.zxm
b.zxm
EOF
cmp "$work/expected-modules" "$work/zxmod.log"
grep -Fq 'invalid module path: ../escape.zxm' "$work/modules.stderr"
grep -Fq 'module path escapes its efilinux directory: modules/escape/escaped.zxm' \
    "$work/modules.stderr"
grep -Fq 'unknown directive: unknown' "$work/modules.stderr"

media_create="$work/create-media"
"$ROOT/002-system/efilinux-live/files/usr/bin/efilinux-persistence-create" \
    "$media_create" 64 > "$work/create.log"
persistence="$media_create/efilinux/persistence.img"
[[ $(blkid -p -s TYPE -o value "$persistence") == ext4 ]] || \
    die "persistence helper did not create an ext4 container"
dumpe2fs -h "$persistence" 2>/dev/null | grep -Fq 'Filesystem volume name:   EFILINUX_PERSIST'

python3 - "$media_create/efilinux/efilinux.conf" <<'PY'
from pathlib import Path
import sys

lines = [
    line.split("#", 1)[0].strip()
    for line in Path(sys.argv[1]).read_text().splitlines()
]
directives = [line for line in lines if line]
if directives.count("persistence persistence.img") != 1:
    raise SystemExit(f"unexpected persistence directives: {directives}")
PY

if "$ROOT/002-system/efilinux-live/files/usr/bin/efilinux-persistence-create" \
        "$media_create" 64 >/dev/null 2>&1; then
    die "persistence helper overwrote an existing container"
fi

log "Live configuration parsing, module deduplication, traversal rejection, and ext4 container creation passed"
