#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=drbl-runtime
pkgver=5.9.11
depends=(bash coreutils findutils gawk grep iproute2 ncurses perl-runtime procps-ng sed util-linux)
builddepends=()
makedepends=(make)

prepare() {
    local archive="$downloaddir/drbl-$pkgver.tar.gz"
    download "https://free.nchc.org.tw/drbl-core/src/stable/drbl-$pkgver.tar.gz" "$archive"
    checksum sha256 843efaf2832f3d8d10175fa20abde4df408546f7b4048eae222f40a55778ad5d "$archive"
    extract "$archive" "$srcdir/source"
}

build() {
    local module_root=/opt/efilinux/modules/recovery
    local share_root="$module_root/share/drbl"
    local config_root="$module_root/etc/drbl"

    make -C "$srcdir/source/sbin" all
    make -C "$srcdir/source/lang" all
    make -C "$srcdir/source/pkg/misc" all

    install -d -m0755 \
        "$develdir$share_root/sbin" \
        "$develdir$share_root/bin" \
        "$develdir$share_root/lang/bash" \
        "$develdir$share_root/pkg/misc" \
        "$develdir$share_root/image" \
        "$develdir$config_root"

    cp -a "$srcdir/source/scripts/sbin/." "$develdir$share_root/sbin/"
    cp -a "$srcdir/source/scripts/bin/." "$develdir$share_root/bin/"
    cp -a "$srcdir/source/lang/bash/." "$develdir$share_root/lang/bash/"
    cp -a "$srcdir/source/pkg/misc/." "$develdir$share_root/pkg/misc/"
    cp -a "$srcdir/source/image/." "$develdir$share_root/image/"
    install -m0644 "$srcdir/source/conf/drbl.conf" "$develdir$config_root/drbl.conf"

    find "$develdir$module_root" -type f -exec sed -i \
        -e "s#/usr/share/drbl#$share_root#g" \
        -e "s#/etc/drbl#$config_root#g" \
        -e "s#/etc/ocs#$module_root/etc/ocs#g" \
        {} +

    python3 - \
        "$develdir$share_root/sbin/drbl-conf-functions" \
        "$develdir$share_root/sbin/drbl-functions" \
        "$config_root" \
        "$module_root/perl" <<'PYCODE'
from pathlib import Path
import sys

config_root = sys.argv[3]
perl_root = sys.argv[4]
for name in sys.argv[1:3]:
    path = Path(name)
    text = path.read_text()
    text = text.replace(config_root, '${DRBL_CONFIG_DIR}')
    marker = 'DRBL_SCRIPT_PATH="${DRBL_SCRIPT_PATH:-/opt/efilinux/modules/recovery/share/drbl}"\n'
    if marker not in text:
        raise SystemExit(f'DRBL path marker missing in {path}')
    text = text.replace(
        marker,
        marker
        + f'DRBL_CONFIG_DIR="${{DRBL_CONFIG_DIR:-{config_root}}}"\n'
        + f'RECOVERY_PERL_ROOT="${{RECOVERY_PERL_ROOT:-{perl_root}}}"\n'
        + 'PATH="$RECOVERY_PERL_ROOT/bin:$PATH"\n'
        + 'export PATH\n',
        1,
    )
    path.write_text(text)
PYCODE

    python3 - "$develdir$share_root" "$module_root/perl/bin/perl" <<'PYCODE'
from pathlib import Path
import sys

root = Path(sys.argv[1])
private_perl = sys.argv[2]
for path in root.rglob('*'):
    if not path.is_file():
        continue
    try:
        text = path.read_text()
    except UnicodeDecodeError:
        continue
    lines = text.splitlines(keepends=True)
    if not lines:
        continue
    if lines[0].startswith('#!/usr/bin/perl'):
        lines[0] = '#!' + private_perl + lines[0][len('#!/usr/bin/perl'):]
        path.write_text(''.join(lines))
PYCODE
}

devel() { :; }

package() {
    package_keep /opt/efilinux/modules/recovery/
}

recipe_main "$@"
