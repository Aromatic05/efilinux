#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=cifs-utils
pkgver=7.7
depends=(glibc keyutils krb5 libcap talloc)
builddepends=(linux-headers)
makedepends=(autoconf automake gcc libtool make patch pkg-config)

prepare() {
    local archive="$downloaddir/cifs-utils-$pkgver.tar.bz2"
    download "https://download.samba.org/pub/linux-cifs/cifs-utils/cifs-utils-$pkgver.tar.bz2" "$archive"
    checksum sha256 2f8aae9aa5ddd73fbaf4d61e2e5e19ef54124cbf2810b626820050e7bd2f6606 "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/files/optional-idmap-plugin.patch" \
        "$srcdir/optional-idmap-plugin.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/source" -Np1 -i "$srcdir/optional-idmap-plugin.patch"
}

build() {
    ROOTSBINDIR=/usr/bin \
        target_autotools_configure "$srcdir/source" "$builddir" \
            --bindir=/usr/bin \
            --sbindir=/usr/bin \
            --libexecdir=/usr/lib/cifs-utils \
            --enable-cifsupcall \
            --enable-cifscreds \
            --disable-cifsidmap \
            --enable-cifsacl \
            --enable-smbinfo \
            --disable-pythontools \
            --disable-pam \
            --disable-systemd \
            --disable-man \
            --with-libcap-ng=no \
            --with-libcap
    target_make_install "$builddir" "$develdir"
}

devel() {
    strip_all "$develdir/usr/bin"
}

package() {
    package_keep \
        /usr/bin/mount.cifs \
        /usr/bin/mount.smb3 \
        /usr/bin/cifs.upcall \
        /usr/bin/cifscreds \
        /usr/bin/getcifsacl \
        /usr/bin/setcifsacl \
        /usr/bin/smbinfo
}

recipe_main "$@"
