#!/usr/bin/env bash

set -euo pipefail

MODULE_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(cd -- "$MODULE_DIR/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command python3 readelf sha256sum unsquashfs

artifact="$MODULE_DIR/build/output/003-input.zxm"
work="$MODULE_DIR/build/test/artifact"
image="$work/image"
module_root="$image/root"
loader="$EFILINUX_ROOTFS/usr/lib/ld-linux-x86-64.so.2"
library_path="$module_root/usr/lib:$EFILINUX_ROOTFS/usr/lib"

[[ -f "$artifact" ]] || die "input module artifact is missing: $artifact"
reset_directory "$work"
unsquashfs -quiet -dest "$image" "$artifact"

grep -Fxq 'format=1' "$image/metadata/manifest"
grep -Fxq 'id=input' "$image/metadata/manifest"
grep -Fxq 'arch=x86_64' "$image/metadata/manifest"
grep -Fxq 'version=1' "$image/metadata/manifest"

cat > "$work/expected-packages" <<'PACKAGES'
boost	1.89.0
fcitx5	5.1.12
fcitx5-chinese-addons	5.1.8
fcitx5-table-extra	5.1.8
fmt	10.2.1
iso-codes	4.20.1
libime	1.1.11
libuv	1.51.0
opencc	1.1.9
xcb-imdkit	1.0.9
xcb-util-keysyms	0.4.1
xcb-util-wm	0.4.2
PACKAGES

tail -n +2 "$module_root/opt/efilinux/modules/input/packages.tsv" |
    LC_ALL=C sort > "$work/actual-packages"
cmp -s "$work/expected-packages" "$work/actual-packages" ||
    die "input module package manifest differs from the expected self-contained set"

[[ -x "$module_root/usr/bin/fcitx5" ]] || die "fcitx5 command is missing"
for plugin in \
    libclassicui libxim libxcb \
    libchttrans libfullwidth libpinyinhelper libpinyin libpunctuation libtable; do
    [[ -f "$module_root/usr/lib/fcitx5/$plugin.so" ]] ||
        die "fcitx5 plugin is missing: $plugin"
done
for data_file in \
    /usr/share/fcitx5/addon/pinyin.conf \
    /usr/share/fcitx5/addon/table.conf \
    /usr/share/fcitx5/inputmethod/pinyin.conf \
    /usr/share/fcitx5/inputmethod/cangjie.conf \
    /usr/share/fcitx5/inputmethod/wubi98.conf \
    /usr/share/fcitx5/inputmethod/jyutping-table.conf \
    /usr/share/fcitx5/pinyin/symbols \
    /usr/share/iso-codes/json/iso_639-2.json \
    /usr/share/iso-codes/json/iso_3166-1.json \
    /usr/share/libime/sc.dict \
    /usr/share/libime/extb.dict \
    /usr/lib/libime/zh_CN.lm \
    /usr/lib/libime/zh_CN.lm.predict \
    /usr/share/opencc/s2t.json; do
    [[ -f "$module_root$data_file" ]] || die "input runtime data is missing: $data_file"
done

if find "$module_root" \
        \( -path '*/include/*' -o -path '*/lib/pkgconfig/*' -o -name '*.a' \
           -o -name '*.la' -o -path '*/share/man/*' -o -path '*/share/doc/*' \
           -o -path "$module_root/etc" -o -path "$module_root/etc/*" \) \
        -print -quit | grep -q .; then
    die "input module contains development, documentation, static, or /etc payload"
fi

run_target() {
    env -u LD_PRELOAD -u LD_LIBRARY_PATH \
        "$loader" --library-path "$library_path" "$@"
}

run_target "$module_root/usr/bin/fcitx5" --version 2>&1 |
    grep -Fxq '5.1.12'

python3 - "$module_root" "$EFILINUX_ROOTFS" <<'PY'
from pathlib import Path
import re
import subprocess
import sys

module_root = Path(sys.argv[1])
base_root = Path(sys.argv[2])
library_directories = [module_root / "usr/lib", base_root / "usr/lib"]
missing = []
elf_count = 0

for root in (module_root / "usr/bin", module_root / "usr/lib"):
    if not root.exists():
        continue
    for path in root.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        if path.read_bytes()[:4] != b"\x7fELF":
            continue
        elf_count += 1
        result = subprocess.run(
            ["readelf", "-d", str(path)],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        for soname in re.findall(r"Shared library: \[(.*?)\]", result.stdout):
            if not any((directory / soname).exists() for directory in library_directories):
                missing.append((path, soname))

if missing:
    for path, soname in missing:
        print(f"{path}: missing {soname}", file=sys.stderr)
    raise SystemExit(1)

print(f"input module ELF closure: {elf_count} files")
PY

size=$(stat -c %s "$artifact")
(( size <= 48 * 1024 * 1024 )) ||
    die "input module exceeds 48 MiB: $size"
sha256sum "$artifact"
log "Input module commands, package manifest, data, ELF closure, and payload policy passed ($size bytes)"
