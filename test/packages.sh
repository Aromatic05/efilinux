#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command awk comm grep sha256sum sort tar
package_assert_current_index

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

declare -A seen_packages=()
package_count=0

while IFS=$'\t' read -r name version recipe_key content_hash archive_name digest extra; do
    [[ -n "$name" ]] || continue
    [[ "$name" != \#* ]] || continue
    [[ -z ${extra:-} ]] || die "invalid package index record: $name"
    [[ -n "$version" && -n "$recipe_key" && -n "$content_hash" && -n "$archive_name" && -n "$digest" ]] || \
        die "incomplete package index record: $name"
    [[ -z ${seen_packages[$name]+present} ]] || die "duplicate package index record: $name"
    seen_packages[$name]=1
    [[ "$content_hash" == "$digest" ]] || \
        die "package content hash and archive digest differ: $name"
    [[ "$archive_name" == "$(basename -- "$archive_name")" ]] || \
        die "unsafe package archive name: $archive_name"

    archive="$EFILINUX_PACKAGES/$archive_name"
    [[ -f "$archive.sha256" ]] || die "package checksum sidecar is missing: $archive_name"
    (cd "$EFILINUX_PACKAGES" && sha256sum --check --status "$archive_name.sha256") || \
        die "package checksum sidecar is invalid: $archive_name"
    package_verify_archive "$archive" "$name" "$version" "$recipe_key" "$digest"

    filelist="$work/$name.filelist"
    install="$work/$name.install"
    missing="$work/$name.install-missing"
    tar --extract --to-stdout --file "$archive" .FILELIST > "$filelist"
    tar --extract --to-stdout --file "$archive" .INSTALL > "$install"

    LC_ALL=C sort -c -u "$filelist" || die ".FILELIST is not sorted and unique: $name"
    LC_ALL=C sort -c -u "$install" || die ".INSTALL is not sorted and unique: $name"
    if grep -Ev '^/([^/]+/?)*$' "$filelist" >/dev/null; then
        die ".FILELIST contains an invalid absolute path: $name"
    fi
    if grep -Ev '^/([^/]+/?)*$' "$install" >/dev/null; then
        die ".INSTALL contains an invalid absolute path: $name"
    fi
    LC_ALL=C comm -23 "$install" "$filelist" > "$missing"
    if [[ -s "$missing" ]]; then
        die ".INSTALL is not a subset of .FILELIST: $name"
    fi

    while IFS= read -r member; do
        case $member in
            .PKGINFO|.BUILDINFO|.FILELIST|.INSTALL|devel|devel/*) ;;
            *) die "package archive contains an undeclared top-level member: $member" ;;
        esac
    done < <(tar --list --file "$archive")

    package_count=$((package_count + 1))
done < "$EFILINUX_PACKAGE_INDEX"

((package_count > 0)) || die "package index contains no packages"
printf 'validated %d format-%d packages\n' "$package_count" "$EFILINUX_PACKAGE_FORMAT"
