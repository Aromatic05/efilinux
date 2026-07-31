#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command gcc readelf
ensure_directories

work="$EFILINUX_TEST/linker-optimizations"
reset_directory "$work"

cat > "$work/unused.c" <<'C'
int efilinux_unused_library_symbol(void) { return 42; }
C
cat > "$work/consumer.c" <<'C'
int main(void) { return 0; }
C
cat > "$work/relocations.c" <<'C'
static int values[512];
void *references[512] = {
#define R(n) &values[n]
    R(0), R(1), R(2), R(3), R(4), R(5), R(6), R(7),
    R(8), R(9), R(10), R(11), R(12), R(13), R(14), R(15),
#define R16(base) \
    R(base), R(base + 1), R(base + 2), R(base + 3), \
    R(base + 4), R(base + 5), R(base + 6), R(base + 7), \
    R(base + 8), R(base + 9), R(base + 10), R(base + 11), \
    R(base + 12), R(base + 13), R(base + 14), R(base + 15)
    R16(16), R16(32), R16(48), R16(64), R16(80), R16(96), R16(112),
    R16(128), R16(144), R16(160), R16(176), R16(192), R16(208), R16(224),
    R16(240), R16(256), R16(272), R16(288), R16(304), R16(320), R16(336),
    R16(352), R16(368), R16(384), R16(400), R16(416), R16(432), R16(448),
    R16(464), R16(480), R16(496)
};
C

(
    source "$ROOT/profiles/makepkg.conf"
    gcc $CFLAGS -fPIC -shared "$work/unused.c" -o "$work/libunused.so" \
        $LDFLAGS -Wl,-soname,libunused.so.1
    gcc $CFLAGS "$work/consumer.c" -o "$work/consumer" \
        $LDFLAGS -L"$work" -lunused
    gcc $CFLAGS -fPIC -shared "$work/relocations.c" -o "$work/librelocations.so" \
        $LDFLAGS -Wl,-soname,librelocations.so.1
)

if LC_ALL=C readelf -d "$work/consumer" | grep -Fq 'Shared library: [libunused.so.1]'; then
    die "target linker retains an unused shared-library dependency"
fi

relr_tags=$(LC_ALL=C readelf -d "$work/librelocations.so")
for tag in RELR RELRSZ RELRENT; do
    grep -Eq "\($tag\)" <<<"$relr_tags" ||
        die "target linker did not emit the $tag dynamic tag"
done

log "Target linker drops unused DSOs and packs relative relocations"
