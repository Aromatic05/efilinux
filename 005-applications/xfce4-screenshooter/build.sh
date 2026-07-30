#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=xfce4-screenshooter
pkgver=1.10.6
depends=(glib glibc gtk3 libpng xfce xorg)
builddepends=()
makedepends=(gcc make patch pkg-config)

prepare() {
    local archive="$downloaddir/xfce4-screenshooter-$pkgver.tar.bz2"
    download "https://archive.xfce.org/src/apps/xfce4-screenshooter/1.10/xfce4-screenshooter-$pkgver.tar.bz2" "$archive"
    checksum sha256 992066cfecfb44a68681340bfd55d524d40410aac3da6ef25c6c6cb2150a5965 "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/patches/0001-disable-imgur-upload.patch" \
        "$srcdir/disable-imgur-upload.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    local help2man_wrapper="$builddir/help2man-target"
    local target_runner="$builddir/run-target-program"

    patch -d "$srcdir/source" -Np1 < "$srcdir/disable-imgur-upload.patch"
    export SOUP3_FOUND=no
    target_release_configure "$srcdir/source" "$builddir" --disable-debug

    cat > "$target_runner" <<RUNNER
#!/usr/bin/env bash
set -euo pipefail
exec env -u LD_PRELOAD -u LD_LIBRARY_PATH \
    "$EFILINUX_SYSROOT/usr/lib/ld-linux-x86-64.so.2" \
    --library-path "$EFILINUX_SYSROOT/usr/lib" \
    "\$EFILINUX_HELP2MAN_TARGET" "\$@"
RUNNER
    chmod 0755 "$target_runner"
    cat > "$help2man_wrapper" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
arguments=("\$@")
last_index=\$((\${#arguments[@]} - 1))
export EFILINUX_HELP2MAN_TARGET
EFILINUX_HELP2MAN_TARGET=\$(realpath -- "\${arguments[\$last_index]}")
arguments[\$last_index]="$target_runner"
exec /usr/bin/help2man "\${arguments[@]}"
WRAPPER
    chmod 0755 "$help2man_wrapper"

    make -C "$builddir" -j"$EFILINUX_JOBS" HELP2MAN="$help2man_wrapper"
    make -C "$builddir" DESTDIR="$develdir" install
    find "$develdir/usr/lib" -name '*.la' -delete 2>/dev/null || true
    target_normalize_pkg_config "$develdir"
}

devel() {
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
    rm -rf -- "$develdir/usr/libexec/xfce4/screenshooter/scripts"
}

package() {
    local -a keep=(/usr/bin/xfce4-screenshooter /usr/share/applications/ /usr/share/icons/hicolor/)
    [[ ! -d "$pkgdir/usr/lib/xfce4/panel/plugins" ]] || keep+=(/usr/lib/xfce4/panel/plugins/)
    [[ ! -d "$pkgdir/usr/share/xfce4/panel/plugins" ]] || keep+=(/usr/share/xfce4/panel/plugins/)
    package_keep "${keep[@]}"
}

recipe_main "$@"
