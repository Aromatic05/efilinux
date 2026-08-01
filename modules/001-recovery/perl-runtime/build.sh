#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=perl-runtime
pkgver=5.44.0
depends=(glibc zlib)
builddepends=()
makedepends=(bwrap gcc make patch)

prepare() {
    local archive="$downloaddir/perl-$pkgver.tar.xz"

    download "https://www.cpan.org/src/5.0/perl-$pkgver.tar.xz" "$archive"
    checksum sha256 \
        505cf43912e9480495c344c70260452e32aa2a73c546a026b3f100053b23ce91 \
        "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/local-bwrap-target.patch" \
        "$srcdir/local-bwrap-target.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return

    patch -d "$srcdir/source" -Np1 -i "$srcdir/local-bwrap-target.patch"
}

build() {
    local prefix=/opt/efilinux/modules/recovery/perl
    local compiler target_directory

    compiler=$(target_compiler_wrapper gcc)
    target_directory="$builddir/target"
    mkdir -p "$target_directory"

    (
        cd "$builddir"
        sh "$srcdir/source/Configure" \
            -des \
            -Dmksymlinks \
            -Dusecrosscompile \
            -Dtargethost=local \
            -Dtargetrun=local-bwrap \
            -Dtargetto=cp \
            -Dtargetfrom=cp \
            -Dtargetdir="$target_directory" \
            -Dtargetarch=x86_64-linux \
            -Dosname=linux \
            -Dcc="$compiler" \
            -Dar="$AR" \
            -Dnm="$NM" \
            -Dranlib="$RANLIB" \
            -Dsysroot="$EFILINUX_SYSROOT" \
            -Dprefix="$prefix" \
            -Dsiteprefix="$prefix" \
            -Uvendorprefix \
            -Dman1dir=none \
            -Dman3dir=none \
            -Duserelocatableinc \
            -Uuseshrplib \
            -Uuseithreads \
            -Dusedl \
            -Duse64bitint \
            -Dccflags="$CFLAGS" \
            -Dcccdlflags='-fPIC' \
            -Dcppflags="$CPPFLAGS" \
            -Dldflags="$LDFLAGS" \
            -Dlddlflags="$LDFLAGS -shared" \
            -Doptimize='-O2'
    )

    make -C "$builddir" -j"$EFILINUX_JOBS"
    make -C "$builddir" DESTDIR="$develdir" install
}

devel() {
    local prefix="$develdir/opt/efilinux/modules/recovery/perl"

    rm -rf \
        "$prefix/man" \
        "$prefix/lib/5.44.0/pod" \
        "$prefix/lib/site_perl"
    find "$prefix" -type f \( -name '*.a' -o -name '*.h' -o -name '*.pod' \) -delete
    find "$prefix/bin" -mindepth 1 -maxdepth 1 \
        ! -name perl \
        ! -name 'perl5.44.0' \
        -delete
    find "$prefix" -type d -empty -delete
    strip_all "$prefix/bin" "$prefix/lib"
}

package() {
    package_keep /opt/efilinux/modules/recovery/perl/
}

recipe_main "$@"
