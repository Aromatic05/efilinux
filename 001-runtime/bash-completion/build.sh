#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=bash-completion
pkgver=2.18.0

depends=(bash)
builddepends=()
makedepends=(install)

prepare() {
    local archive="$downloaddir/bash-completion-$pkgver.tar.xz"
    download \
        "https://github.com/scop/bash-completion/releases/download/$pkgver/bash-completion-$pkgver.tar.xz" \
        "$archive"
    checksum sha256 88bcf85124f77f74f2f2f8bcd16ac4382d807a827ede742a64940c7116aea33f "$archive"
    extract "$archive" "$srcdir/source"
    input_tree "$recipedir/files" "$srcdir/files"
}

build() {
    local completion destination source_file
    local -a completions=(
        7z bind chmod chown cpio cryptsetup curl dd doas env file find free
        gzip hostname ip kill killall lsof lsusb mount nmcli openssl pgrep ping
        ps rsync smartctl ssh ssh-add ssh-keygen strace sysctl tar umount watch xz
    )

    install -Dm0644 "$srcdir/source/bash_completion" \
        "$develdir/usr/share/bash-completion/bash_completion"
    install -d -m0755 "$develdir/usr/share/bash-completion/completions"

    for completion in "${completions[@]}"; do
        source_file=
        for source_file in \
            "$srcdir/source/completions-core/$completion.bash" \
            "$srcdir/source/completions/$completion.bash" \
            "$srcdir/source/completions-fallback/$completion.bash"; do
            [[ -f "$source_file" ]] && break
        done
        [[ -f "$source_file" ]] || continue
        destination=$completion
        [[ $completion != 7z ]] || destination=7zz
        install -m0644 "$source_file" \
            "$develdir/usr/share/bash-completion/completions/$destination"
    done

    for source_file in "$srcdir/files/usr/share/bash-completion/completions/"*; do
        [[ -f "$source_file" ]] || continue
        install -m0644 "$source_file" \
            "$develdir/usr/share/bash-completion/completions/${source_file##*/}"
    done
}

package() {
    package_keep \
        /usr/share/bash-completion/bash_completion \
        /usr/share/bash-completion/completions/
}

recipe_main "$@"
