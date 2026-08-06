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
    bash bc bzip2 cifs-utils coreutils coreutils-sha512sum curl dialog dosfstools drbl-runtime e2fsprogs
    findutils gawk gptfdisk grep gzip jq lzip lvm2 lz4 lzop mdadm nbd nfs-utils
    ntfs-3g parted netcat-traditional partclone pbzip2 perl-runtime pigz plzip
    procps-ng qemu-img sed smartmontools sshfs tar util-linux wget xfsprogs xz zstd
)
builddepends=()
makedepends=(make patch python3)

prepare() {
    local archive="$downloaddir/clonezilla-$pkgver.tar.gz"
    download "https://free.nchc.org.tw/drbl-core/src/stable/clonezilla-$pkgver.tar.gz" "$archive"
    checksum sha256 f8b6e4a1e31a074fc76a5ff7e66e550371b9f66b06936060a7e0dbf5d37f1684 "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/files/clonezilla-local-only.patch" "$srcdir/clonezilla-local-only.patch"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/source" -p1 < "$srcdir/clonezilla-local-only.patch"
}

build() {
    local module_root=/opt/recovery
    local share_root="$module_root/share/drbl"
    local config_root="$module_root/etc/drbl"
    local ocs_config_root="$module_root/etc/ocs"
    local perl_root="$module_root/perl"
    local command
    local -a excluded_commands=(
        create-debian-live
        create-drbl-live
        create-drbl-live-by-pkg
        create-gparted-live
        create-ubuntu-live
        drbl-ocs
        drbl-ocs-live-prep
        gen-torrent-from-ptcl
        get-latest-ocs-live-ver
        ocs-btsrv
        ocs-ezio-leecher
        ocs-ezio-seeder
        ocs-gen-bt-metainfo
        ocs-gen-bt-slices
        ocs-live-feed-img
        ocs-live-get-img
        ocs-memtester
        ocs-related-srv
        ocs-srv-live
        ocsmgrd
    )

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

    python3 - \
        "$develdir$config_root/drbl-ocs.conf" \
        "$develdir$share_root/sbin/ocs-functions" <<'PYCODE'
from pathlib import Path
import sys

config = Path(sys.argv[1])
functions = Path(sys.argv[2])

config_text = config.read_text()
config_replacements = {
    'PARTCLONE_SAVE_OPT_INIT="-a3 -z 10485760"':
        'PARTCLONE_SAVE_OPT_INIT="-a1 -z 10485760"',
    'PARTCLONE_D2D_OPT="-a3 -z 10485760"':
        'PARTCLONE_D2D_OPT="-a1 -z 10485760"',
}
for old, new in config_replacements.items():
    if config_text.count(old) != 1:
        raise SystemExit(f'Clonezilla Partclone option changed upstream: {old!r}')
    config_text = config_text.replace(old, new)
config.write_text(config_text)

functions_text = functions.read_text()
old_failure = '''    echo "Failed to use partclone program to save or restore an image!" | tee --append ${OCS_LOGFILE}
    [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
    echo -n "$msg_press_enter_to_continue..."
    read
'''
new_failure = '''    echo "Failed to use partclone program to save or restore an image!" | tee --append ${OCS_LOGFILE}
    [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
    if [ "$ocs_batch_mode" != "on" ]; then
      echo -n "$msg_press_enter_to_continue..."
      read
    fi
'''
if functions_text.count(old_failure) != 1:
    raise SystemExit('Clonezilla Partclone failure prompt changed upstream')
functions_text = functions_text.replace(old_failure, new_failure)

old_gunzip = 'unzip_stdin_cmd="gunzip -c"'
new_gunzip = 'unzip_stdin_cmd="unpigz -c"'
if functions_text.count(old_gunzip) != 2:
    raise SystemExit('Clonezilla gzip decompression command set changed upstream')
functions.write_text(functions_text.replace(old_gunzip, new_gunzip))
PYCODE

    for command in "${excluded_commands[@]}"; do
        [[ -f "$develdir/usr/bin/$command" ]] ||
            die "Clonezilla local-only exclusion changed upstream: $command"
        rm -f "$develdir/usr/bin/$command"
    done

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
