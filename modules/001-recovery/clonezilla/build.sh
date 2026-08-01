#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=clonezilla
pkgver=5.16.25
depends=(
    bash bc bzip2 cifs-utils coreutils curl dialog dosfstools drbl-runtime e2fsprogs
    findutils gawk gptfdisk grep gzip jq lvm2 mdadm nbd nfs-utils ntfs-3g parted
    netcat-traditional partclone perl-runtime procps-ng qemu-img sed smartmontools sshfs tar util-linux xfsprogs
    wget xz zstd
)
builddepends=()
makedepends=(make)

prepare() {
    local archive="$downloaddir/clonezilla-$pkgver.tar.gz"
    download "https://free.nchc.org.tw/drbl-core/src/stable/clonezilla-$pkgver.tar.gz" "$archive"
    checksum sha256 f8b6e4a1e31a074fc76a5ff7e66e550371b9f66b06936060a7e0dbf5d37f1684 "$archive"
    extract "$archive" "$srcdir/source"
}

build() {
    local module_root=/opt/recovery
    local share_root="$module_root/share/drbl"
    local config_root="$module_root/etc/drbl"
    local ocs_config_root="$module_root/etc/ocs"
    local perl_root="$module_root/perl"

    make -C "$srcdir/source" all

    install -d -m0755 \
        "$develdir/usr/bin" \
        "$develdir$share_root/sbin" \
        "$develdir$share_root/samples" \
        "$develdir$share_root/prerun/ocs" \
        "$develdir$share_root/postrun/ocs" \
        "$develdir$config_root" \
        "$develdir$ocs_config_root"

    cp -a "$srcdir/source/sbin/." "$develdir/usr/bin/"
    cp -a "$srcdir/source/bin/." "$develdir/usr/bin/"
    cp -a "$srcdir/source/scripts/sbin/." "$develdir$share_root/sbin/"
    cp -a "$srcdir/source/samples/." "$develdir$share_root/samples/"
    cp -a "$srcdir/source/prerun/ocs/." "$develdir$share_root/prerun/ocs/"
    cp -a "$srcdir/source/postrun/ocs/." "$develdir$share_root/postrun/ocs/"
    install -m0644 "$srcdir/source/conf/drbl-ocs.conf" \
        "$develdir$config_root/drbl-ocs.conf"

    [[ -f "$develdir/usr/bin/ocsmgrd" ]] ||
        die "Clonezilla management daemon changed upstream"
    rm -f "$develdir/usr/bin/ocsmgrd"

    find "$develdir/usr/bin" "$develdir$module_root" -type f -exec sed -i \
        -e "s#/usr/share/drbl#$share_root#g" \
        -e "s#/etc/drbl#$config_root#g" \
        -e "s#/etc/ocs#$ocs_config_root#g" \
        {} +

    python3 - \
        "$develdir/usr/bin" \
        "$develdir$share_root" \
        "$perl_root" <<'PYCODE'
from pathlib import Path
import sys

private_perl = f'{sys.argv[3]}/bin/perl'
old_path = 'export PATH=/sbin/:/usr/sbin:/bin/:/usr/bin'
new_path = f'export PATH={sys.argv[3]}/bin:/sbin/:/usr/sbin:/bin/:/usr/bin'
path_replacements = 0
shebang_replacements = 0

for root_name in sys.argv[1:3]:
    root = Path(root_name)
    for path in root.rglob('*'):
        if not path.is_file():
            continue
        try:
            text = path.read_text()
        except UnicodeDecodeError:
            continue

        count = text.count(old_path)
        if count:
            text = text.replace(old_path, new_path)
            path_replacements += count

        lines = text.splitlines(keepends=True)
        if lines and lines[0].startswith('#!/usr/bin/perl'):
            lines[0] = '#!' + private_perl + lines[0][len('#!/usr/bin/perl'):]
            text = ''.join(lines)
            shebang_replacements += 1

        path.write_text(text)

if path_replacements != 3:
    raise SystemExit(
        f'Clonezilla PATH assignments changed upstream: {path_replacements} != 3'
    )
if shebang_replacements != 1:
    raise SystemExit(
        f'Clonezilla Perl shebang set changed upstream: {shebang_replacements} != 1'
    )
PYCODE

    find "$develdir/usr/bin" "$develdir$share_root" -type f -exec chmod 0755 {} +
    find "$develdir$module_root/etc" -type f -exec chmod 0644 {} +
}

devel() { :; }

package() {
    package_keep \
        /usr/bin/ \
        /opt/recovery/
}

recipe_main "$@"
