#!/usr/bin/env bash

set -euo pipefail

MODULE_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(cd -- "$MODULE_DIR/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command desktop-file-validate python3 readelf sha256sum strings timeout unsquashfs

artifact="$ROOT/modules/output/004-browser.zxm"
work="$MODULE_DIR/build/test/artifact"
image="$work/image"
module_root="$image/root"
base_root="$EFILINUX_ROOTFS"
loader="$base_root/usr/lib/ld-linux-x86-64.so.2"
browser_root="$module_root/opt/ungoogled-chromium"
browser="$browser_root/chrome"
launcher="$module_root/usr/bin/ungoogled-chromium"
desktop="$module_root/usr/share/applications/ungoogled-chromium.desktop"
library_path="$module_root/usr/lib:$browser_root:$base_root/usr/lib"

[[ -f "$artifact" ]] || die "browser module artifact is missing: $artifact"
[[ -x "$loader" ]] || die "base EFI dynamic loader is missing: $loader"
reset_directory "$work"
unsquashfs -quiet -dest "$image" "$artifact"

grep -Fxq 'format=1' "$image/metadata/manifest"
grep -Fxq 'id=browser' "$image/metadata/manifest"
grep -Fxq 'arch=x86_64' "$image/metadata/manifest"
grep -Fxq 'version=117.0.5938.149' "$image/metadata/manifest"

cat > "$work/expected-packages" <<'PACKAGES'
libcups	2.4.7
nspr	4.35-1
nss	3.95-1
ungoogled-chromium	117.0.5938.149-1.1
PACKAGES

tail -n +2 "$module_root/opt/efilinux/modules/browser/packages.tsv" |
    LC_ALL=C sort > "$work/actual-packages"
cmp -s "$work/expected-packages" "$work/actual-packages" ||
    die "browser module package manifest differs from the expected independent set"

[[ -x "$browser" ]] || die "Ungoogled Chromium executable is missing"
[[ -x "$launcher" ]] || die "Ungoogled Chromium launcher is missing"
[[ -f "$desktop" ]] || die "Ungoogled Chromium desktop entry is missing"
[[ -f "$module_root/usr/share/icons/hicolor/48x48/apps/ungoogled-chromium.png" ]] ||
    die "Ungoogled Chromium icon is missing"
[[ -s "$browser_root/resources.pak" ]] || die "Chromium resources.pak is missing"
[[ -s "$browser_root/icudtl.dat" ]] || die "Chromium ICU data is missing"
[[ -s "$browser_root/v8_context_snapshot.bin" ]] || die "Chromium V8 snapshot is missing"

desktop-file-validate "$desktop"
grep -Fxq 'Exec=ungoogled-chromium %U' "$desktop"
grep -Fxq 'Icon=ungoogled-chromium' "$desktop"
bash -n "$launcher"
for flag in \
    --disable-background-networking \
    --disable-breakpad \
    --disable-component-update \
    --disable-domain-reliability \
    OptimizationGuideModelDownloading \
    --disable-sync; do
    grep -Fq -- "$flag" "$launcher" || die "browser launcher is missing policy flag: $flag"
done
grep -Fq 'root_flags+=(--no-sandbox)' "$launcher" ||
    die "browser launcher does not handle the root live-session case"

printf '%s\n' en-US.pak zh-CN.pak > "$work/expected-locales"
find "$browser_root/locales" -maxdepth 1 -type f -name '*.pak' -printf '%f\n' |
    LC_ALL=C sort > "$work/actual-locales"
cmp -s "$work/expected-locales" "$work/actual-locales" ||
    die "browser locale set is not trimmed to en-US and zh-CN"
if find "$browser_root/locales" -type f -name '*.pak.info' -print -quit | grep -q .; then
    die "browser module still contains locale metadata"
fi

if find "$browser_root" \
        \( -name chromedriver -o -iname '*crashpad*' -o -name chrome_sandbox \
           -o -iname '*swiftshader*' -o -iname '*on_device_model*' \
           -o -iname '*gemini*' \) -print -quit | grep -q .; then
    die "browser module contains driver, crash reporting, SwiftShader, or AI payload"
fi
if find "$module_root" \
        \( -path '*/include/*' -o -path '*/lib/pkgconfig/*' \
           -o -path '*/share/man/*' -o -path '*/share/doc/*' \
           -o -path '*/lib/debug/*' -o -name '*.a' -o -name '*.la' \) \
        -print -quit | grep -q .; then
    die "browser module contains development, documentation, static, or debug payload"
fi

version_output=$(env -u LD_PRELOAD -u LD_LIBRARY_PATH \
    "$loader" --library-path "$library_path" "$browser" --version)
grep -Fq 'Chromium 117.0.5938.149' <<<"$version_output"
major=$(sed -n 's/^Chromium \([0-9][0-9]*\).*/\1/p' <<<"$version_output")
[[ -n "$major" ]] || die "unable to parse Chromium major version"
(( major > 100 && major < 127 )) ||
    die "Chromium major version is outside the requested pre-MV2-disable range: $major"

if strings -a "$browser" | grep -Fq 'OnDeviceModelService'; then
    die "Chromium binary contains the later on-device AI model service"
fi
if strings -a "$browser" | grep -Fq 'ExtensionManifestV2Unsupported'; then
    die "Chromium binary contains the later MV2 unsupported gate"
fi
if strings -a "$browser" | grep -Fq 'ExtensionManifestV2Disabled'; then
    die "Chromium binary contains the later MV2 disabled gate"
fi

python3 - "$module_root" "$base_root" <<'PY'
from pathlib import Path
import re
import subprocess
import sys

module_root = Path(sys.argv[1])
base_root = Path(sys.argv[2])
library_directories = [
    module_root / "opt/ungoogled-chromium",
    module_root / "usr/lib",
    base_root / "usr/lib",
]
missing = []
elf_count = 0

for root in (module_root / "opt/ungoogled-chromium", module_root / "usr/lib"):
    for path in root.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        with path.open("rb") as stream:
            if stream.read(4) != b"\x7fELF":
                continue
        elf_count += 1
        dynamic = subprocess.run(
            ["readelf", "-d", str(path)], check=True, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            env={"LC_ALL": "C", "PATH": "/usr/bin:/bin"},
        ).stdout
        for soname in re.findall(r"Shared library: \[(.*?)\]", dynamic):
            if not any((directory / soname).exists() for directory in library_directories):
                missing.append((path, soname))

if missing:
    for path, soname in missing:
        print(f"{path}: missing {soname}", file=sys.stderr)
    raise SystemExit(1)
if elf_count < 10:
    raise SystemExit(f"browser module ELF set is unexpectedly small: {elf_count}")
print(f"browser module ELF closure: {elf_count} files")
PY

mkdir -p "$work/home" "$work/config" "$work/cache"
set +e
timeout 20 env -u LD_PRELOAD \
    LD_LIBRARY_PATH="$library_path" \
    HOME="$work/home" \
    XDG_CONFIG_HOME="$work/config" \
    XDG_CACHE_HOME="$work/cache" \
    "$browser" \
    --no-sandbox \
    --headless=new \
    --disable-gpu \
    --disable-dev-shm-usage \
    --disable-background-networking \
    --disable-component-update \
    --disable-features=OptimizationGuideModelDownloading,OptimizationHints,OptimizationTargetPrediction \
    --user-data-dir="$work/profile" \
    --dump-dom 'data:text/html,<html><body>efilinux-browser-smoke</body></html>' \
    >"$work/headless.out" 2>"$work/headless.err"
headless_status=$?
set -e
(( headless_status == 0 )) || {
    sed -n '1,160p' "$work/headless.err" >&2
    die "Ungoogled Chromium headless smoke test failed: $headless_status"
}
grep -Fq 'efilinux-browser-smoke' "$work/headless.out" ||
    die "Ungoogled Chromium headless smoke output is incomplete"

size=$(stat -c %s "$artifact")
(( size <= 128 * 1024 * 1024 )) ||
    die "browser module exceeds 128 MiB: $size"
sha256sum "$artifact"
log "Chromium 117 MV2-era policy, no-AI audit, resources, ELF closure, and headless smoke test passed ($size bytes)"
