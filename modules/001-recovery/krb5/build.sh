#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=krb5
pkgver=1.22.2
depends=(e2fsprogs glibc keyutils)
builddepends=()
makedepends=(gcc make perl pkg-config)

prepare() {
    local archive="$downloaddir/krb5-$pkgver.tar.gz"
    download "https://kerberos.org/dist/krb5/1.22/krb5-$pkgver.tar.gz" "$archive"
    checksum sha256 3243ffbc8ea4d4ac22ddc7dd2a1dc54c57874c40648b60ff97009763554eaf13 "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/files/gcc16-const-strchr.patch" \
        "$srcdir/gcc16-const-strchr.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/source" -Np1 -i "$srcdir/gcc16-const-strchr.patch"
}

build() {
    target_release_configure "$srcdir/source/src" "$builddir" \
        --disable-rpath \
        --disable-nls \
        --disable-pkinit \
        --with-size-optimizations \
        --without-ldap \
        --without-libedit \
        --without-lmdb \
        --with-crypto-impl=builtin \
        --with-tls-impl=no \
        --with-system-et
    target_make_install "$builddir" "$develdir"
}

devel() {
    find "$develdir" -type f \( -name '*.a' -o -name '*.la' \) -delete
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=(
        /usr/bin/
    )
    local family
    for family in \
        'libgssapi_krb5.so.*' \
        'libgssrpc.so.*' \
        'libk5crypto.so.*' \
        'libkadm5clnt_mit.so.*' \
        'libkadm5srv_mit.so.*' \
        'libkdb5.so.*' \
        'libkrad.so.*' \
        'libkrb5.so.*' \
        'libkrb5support.so.*' \
        'libverto.so.*'; do
        package_add_library_family keep "$family"
    done
    [[ ! -d "$pkgdir/usr/lib/krb5" ]] || keep+=(/usr/lib/krb5/)
    package_keep "${keep[@]}"
}

recipe_main "$@"
