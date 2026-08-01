#!/usr/bin/env bash

set -euo pipefail

MODULE_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(cd -- "$MODULE_DIR/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command desktop-file-validate python3 readelf sha256sum timeout unsquashfs

artifact="$MODULE_DIR/build/output/004-browser.zxm"
work="$MODULE_DIR/build/test/artifact"
image="$work/image"
module_root="$image/root"
loader="$EFILINUX_ROOTFS/usr/lib/ld-linux-x86-64.so.2"
library_path="$module_root/usr/lib:$EFILINUX_ROOTFS/usr/lib"
browser="$module_root/usr/bin/netsurf-gtk3"
desktop="$module_root/usr/share/applications/netsurf.desktop"

[[ -f "$artifact" ]] || die "browser module artifact is missing: $artifact"
reset_directory "$work"
unsquashfs -quiet -dest "$image" "$artifact"

grep -Fxq 'format=1' "$image/metadata/manifest"
grep -Fxq 'id=browser' "$image/metadata/manifest"
grep -Fxq 'arch=x86_64' "$image/metadata/manifest"
grep -Fxq 'version=1' "$image/metadata/manifest"

printf 'netsurf\t3.11\n' > "$work/expected-packages"
tail -n +2 "$module_root/opt/efilinux/modules/browser/packages.tsv" |
    LC_ALL=C sort > "$work/actual-packages"
cmp -s "$work/expected-packages" "$work/actual-packages" ||
    die "browser module package manifest differs from the expected self-contained set"

[[ -x "$browser" ]] || die "NetSurf executable is missing"
[[ -f "$desktop" ]] || die "NetSurf desktop entry is missing"
[[ -f "$module_root/usr/share/icons/hicolor/48x48/apps/netsurf.png" ]] ||
    die "NetSurf hicolor icon is missing"
[[ -f "$module_root/usr/share/netsurf/ca-bundle.txt" ]] ||
    die "NetSurf TLS certificate bundle is missing"
[[ -f "$module_root/usr/share/netsurf/default.css" ]] ||
    die "NetSurf default stylesheet is missing"
desktop-file-validate "$desktop"
grep -Fxq 'Exec=netsurf-gtk3 %u' "$desktop"
grep -Fxq 'Icon=netsurf' "$desktop"

if find "$module_root" \
    \( -path '*/include/*' -o -path '*/lib/pkgconfig/*' \
       -o -path '*/share/man/*' -o -path '*/share/doc/*' \
       -o -path '*/share/gtk-doc/*' -o -path '*/share/*/tests/*' \
       -o -path '*/share/*/test/*' -o -path '*/lib/debug/*' \
       -name '*.a' -o -name '*.la' \) \
    -print -quit | grep -q .; then
    die "browser module contains development, documentation, debug, or test payload"
fi

run_target() {
    env -u LD_PRELOAD -u LD_LIBRARY_PATH \
        "$loader" --library-path "$library_path" "$@"
}

# NetSurf 3.11 has no non-GUI version switch; a bounded about:blank launch
# verifies the real GTK entry point without leaving a browser process behind.
set +e
timeout --signal=TERM --kill-after=1s 3s \
    env XDG_CONFIG_HOME="$work/config" XDG_CACHE_HOME="$work/cache" \
    "$loader" --library-path "$library_path" "$browser" about:blank \
    >"$work/launch.log" 2>&1
launch_status=$?
set -e
(( launch_status == 124 || launch_status == 137 )) || {
    sed -n '1,120p' "$work/launch.log" >&2
    die "NetSurf did not remain running for the bounded GUI launch smoke test"
}

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

for path in module_root.rglob("*"):
    if not path.is_file() or path.is_symlink() or path.read_bytes()[:4] != b"\x7fELF":
        continue
    elf_count += 1
    result = subprocess.run(
        ["readelf", "-d", str(path)], check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    for soname in re.findall(r"Shared library: \[(.*?)\]", result.stdout):
        if not any((directory / soname).exists() for directory in library_directories):
            missing.append((path, soname))

if missing:
    for path, soname in missing:
        print(f"{path}: missing {soname}", file=sys.stderr)
    raise SystemExit(1)
if elf_count == 0:
    raise SystemExit("browser module contains no ELF executable")

print(f"browser module ELF closure: {elf_count} files")
PY

size=$(stat -c %s "$artifact")
(( size <= 16 * 1024 * 1024 )) ||
    die "browser module exceeds 16 MiB: $size"
sha256sum "$artifact"
log "Browser module manifest, desktop integration, resources, ELF closure, and bounded launch smoke test passed ($size bytes)"
