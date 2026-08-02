#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
selector="$ROOT/000-kernel/linux-firmware/select_members.py"
materializer="$ROOT/000-kernel/linux-firmware/materialize_links.py"
deduplicator="$ROOT/000-kernel/linux-firmware/deduplicate_firmware.py"
verifier="$ROOT/000-kernel/linux-firmware/verify_firmware_tree.py"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

cat > "$work/include.list" <<'MANIFEST'
file direct.bin
file iwlwifi-exact-77.ucode
file iwlwifi-ty-a0-gf-a0-100.ucode
file iwlwifi-missing-100.ucode
file iwlwifi-blocked-100.ucode
file vendor/model-b/fw/main-5.bin
file vendor/model-c/fw/main-5.bin
file vendor/model-a/fw/alias.bin
file vendor/spaced.bin
versioned-fallback iwlwifi-
MANIFEST

cat > "$work/exclude.list" <<'MANIFEST'
file excluded.bin
file iwlwifi-blocked-89.ucode
MANIFEST

cat > "$work/WHENCE" <<'WHENCE'
Link: iwlwifi-exact-77.ucode -> intel/iwlwifi/iwlwifi-exact-77.ucode
Link: iwlwifi-ty-a0-gf-a0-89.ucode -> intel/iwlwifi/iwlwifi-ty-a0-gf-a0-89.ucode
Link: iwlwifi-ty-a0-gf-a0-101.ucode -> intel/iwlwifi/iwlwifi-ty-a0-gf-a0-101.ucode
Link: vendor/model-b -> model-a
Link: vendor/model-c/fw -> ../model-a/fw
Link: vendor/model-a/fw/alias.bin -> main-5.bin
Link: vendor/spaced.bin  -> model-a/fw/main-5.bin
Link: vendor/absent.bin -> missing.bin
WHENCE

cat > "$work/archive.list" <<'MEMBERS'
linux-firmware-test/WHENCE
linux-firmware-test/direct.bin
linux-firmware-test/excluded.bin
linux-firmware-test/intel/iwlwifi/iwlwifi-exact-77.ucode
linux-firmware-test/intel/iwlwifi/iwlwifi-ty-a0-gf-a0-89.ucode
linux-firmware-test/intel/iwlwifi/iwlwifi-ty-a0-gf-a0-101.ucode
linux-firmware-test/iwlwifi-blocked-89.ucode
linux-firmware-test/vendor/model-a/fw/main-5.bin
MEMBERS

python3 "$selector" \
    "$work/include.list" \
    "$work/exclude.list" \
    linux-firmware-test \
    "$work/WHENCE" \
    "$work/report.tsv" \
    < "$work/archive.list" > "$work/selected.list"

cat > "$work/expected.list" <<'EXPECTED'
linux-firmware-test/WHENCE
linux-firmware-test/direct.bin
linux-firmware-test/intel/iwlwifi/iwlwifi-exact-77.ucode
linux-firmware-test/intel/iwlwifi/iwlwifi-ty-a0-gf-a0-89.ucode
linux-firmware-test/vendor/model-a/fw/main-5.bin
EXPECTED

cmp "$work/expected.list" "$work/selected.list"
grep -Fxq $'fallback\tiwlwifi-ty-a0-gf-a0-100.ucode\tiwlwifi-ty-a0-gf-a0-89.ucode' \
    "$work/report.tsv"
grep -Fxq $'unresolved\tiwlwifi-missing-100.ucode\t-' "$work/report.tsv"
grep -Fxq $'unresolved\tiwlwifi-blocked-100.ucode\t-' "$work/report.tsv"
grep -Fxq $'exact\tvendor/model-b/fw/main-5.bin\tvendor/model-b/fw/main-5.bin' \
    "$work/report.tsv"
grep -Fxq $'exact\tvendor/model-c/fw/main-5.bin\tvendor/model-c/fw/main-5.bin' \
    "$work/report.tsv"
grep -Fxq $'exact\tvendor/model-a/fw/alias.bin\tvendor/model-a/fw/alias.bin' \
    "$work/report.tsv"
grep -Fxq $'exact\tvendor/spaced.bin\tvendor/spaced.bin' "$work/report.tsv"

mkdir -p "$work/staging/intel/iwlwifi" "$work/staging/vendor/model-a/fw"
printf firmware | zstd --quiet -19 -o \
    "$work/staging/intel/iwlwifi/iwlwifi-exact-77.ucode.zst"
printf firmware | zstd --quiet -19 -o \
    "$work/staging/vendor/model-a/fw/main-5.bin.zst"
printf unique | zstd --quiet -19 -o "$work/staging/vendor/unique.bin.zst"
python3 "$materializer" "$work/WHENCE" "$work/staging"

test "$(readlink "$work/staging/iwlwifi-exact-77.ucode.zst")" = \
    intel/iwlwifi/iwlwifi-exact-77.ucode.zst
test "$(readlink "$work/staging/vendor/model-b")" = model-a
test -e "$work/staging/vendor/model-b/fw/main-5.bin.zst"
test "$(readlink "$work/staging/vendor/model-c/fw")" = ../model-a/fw
test -e "$work/staging/vendor/model-c/fw/main-5.bin.zst"
test "$(readlink "$work/staging/vendor/model-a/fw/alias.bin.zst")" = main-5.bin.zst
test -e "$work/staging/vendor/model-a/fw/alias.bin.zst"
test "$(readlink "$work/staging/vendor/spaced.bin.zst")" = model-a/fw/main-5.bin.zst
test -e "$work/staging/vendor/spaced.bin.zst"
test -z "$(find "$work/staging" -name '* *' -print -quit)"
test ! -e "$work/staging/vendor/absent.bin.zst"

find "$work/staging" \( -type f -o -type l \) -name '*.zst' -printf '%P\n' |
    LC_ALL=C sort > "$work/logical-paths.before"
python3 "$deduplicator" "$work/staging" "$work/dedup-report.tsv"
find "$work/staging" \( -type f -o -type l \) -name '*.zst' -printf '%P\n' |
    LC_ALL=C sort > "$work/logical-paths.after"
cmp "$work/logical-paths.before" "$work/logical-paths.after"

deduplicated_links=$(wc -l < "$work/dedup-report.tsv")
test "$deduplicated_links" -eq 1
IFS=$'\t' read -r duplicate_path canonical_path digest compressed_size < \
    "$work/dedup-report.tsv"
test -L "$work/staging/$duplicate_path"
test -f "$work/staging/$canonical_path"
test "$(stat -c %s "$work/staging/$canonical_path")" -eq "$compressed_size"
case $(readlink "$work/staging/$duplicate_path") in
    /*) false ;;
esac
test "$(sha256sum "$work/staging/$duplicate_path" | awk '{ print $1 }')" = "$digest"
cmp \
    <(zstd --quiet --decompress --stdout < "$work/staging/$duplicate_path") \
    <(zstd --quiet --decompress --stdout < "$work/staging/$canonical_path")

printf 'exact\tduplicate-request\t%s\n' \
    "${duplicate_path%.zst}" > "$work/verification-selection.tsv"
printf 'fallback\tcanonical-request\t%s\n' \
    "${canonical_path%.zst}" >> "$work/verification-selection.tsv"
python3 "$verifier" \
    "$work/staging" \
    "$work/verification-selection.tsv" \
    "$work/dedup-report.tsv"
while IFS= read -r firmware_file; do
    zstd --quiet --test "$firmware_file"
done < <(find "$work/staging" -type f -name '*.zst' -print)

ln -s /etc/passwd "$work/staging/vendor/escape.bin.zst"
if python3 "$verifier" "$work/staging" >/dev/null 2>&1; then
    printf 'firmware verifier accepted a link escaping the firmware root\n' >&2
    exit 1
fi
rm "$work/staging/vendor/escape.bin.zst"

printf 'firmware selection and WHENCE link materialization passed\n'
