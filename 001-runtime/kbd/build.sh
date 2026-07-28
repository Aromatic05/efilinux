#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
require_command autoreconf curl gcc make patch python3 sha256sum tar
ensure_directories
package="kbd-$KBD_VERSION"
archive="$EFILINUX_DOWNLOADS/$package.tar.xz"
patch_file="$EFILINUX_DOWNLOADS/$package-backspace-1.patch"
prepare_package "$package"
download "https://www.kernel.org/pub/linux/utils/kbd/$package.tar.xz" "$archive"
download "https://www.linuxfromscratch.org/patches/lfs/development/$package-backspace-1.patch" "$patch_file"
verify_sha256 "$KBD_SHA256" "$archive"
verify_sha256 "$KBD_BACKSPACE_SHA256" "$patch_file"
extract_source "$archive" "$PACKAGE_SOURCE"
patch -d "$PACKAGE_SOURCE" -Np1 < "$patch_file"
python3 - "$PACKAGE_SOURCE/configure.ac" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
old = 'AS_IF([test "$HAVE_BZIP2" = "no"], [\n\tAC_CHECK_LIB(bz2, BZ2_bzDecompressInit, ['
new = 'AS_IF([test "$with_bzip2" != "no" && test "$HAVE_BZIP2" = "no"], [\n\tAC_CHECK_LIB(bz2, BZ2_bzDecompressInit, ['
if source.count(old) != 1:
    raise SystemExit("unexpected Kbd bzip2 fallback structure")
path.write_text(source.replace(old, new))
PY
autoreconf -fi "$PACKAGE_SOURCE"
log "Configuring Kbd"
cd "$PACKAGE_BUILD"
CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)" \
    "$PACKAGE_SOURCE/configure" --prefix=/usr --bindir=/usr/bin \
        --disable-vlock --disable-nls --disable-tests --disable-xkb \
        --with-zlib --without-bzip2 --with-lzma --with-zstd
log "Building Kbd"
make -j"$EFILINUX_JOBS"
make DESTDIR="$PACKAGE_STAGING" install
merge_sysroot "$PACKAGE_STAGING"
