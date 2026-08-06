#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
source "$ROOT/modules/001-recovery/lib/target-layout.sh"
pkgname=gtkhash
pkgver=1.5
depends=(glib glibc gtk3 libgcrypt zlib)
builddepends=()
makedepends=(gcc meson ninja pkg-config)
prepare() {
    local archive="$downloaddir/gtkhash-$pkgver.tar.gz"
    download "https://github.com/gtkhash/gtkhash/archive/refs/tags/v$pkgver.tar.gz" "$archive"
    checksum sha256 657635f4134fcc2b30641b3f5ca4859a15e8a9e6fa22ee260f4e541bb1a9497d "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    input_shared_file "$ROOT/modules/001-recovery/lib/target-layout.sh" "$srcdir/recovery-target-layout.sh"
}
build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        --prefix=/opt/recovery \
        -Dappstream=false \
        -Dblake2=false \
        -Dbuild-caja=false \
        -Dbuild-gtkhash=true \
        -Dbuild-nautilus=false \
        -Dbuild-nemo=false \
        -Dbuild-thunar=false \
        -Dgcrypt=true \
        -Dglib-checksums=true \
        -Dinternal-md6=true \
        -Dlibcrypto=false \
        -Dlinux-crypto=false \
        -Dmbedtls=false \
        -Dnettle=false \
        -Dzlib=true
    target_meson_install "$builddir" "$develdir"
    recovery_prune_translations "$develdir"

    mv "$develdir/opt/recovery/bin/gtkhash" "$develdir/opt/recovery/bin/gtkhash.bin"
    install -Dm0755 "$EFILINUX_SYSROOT/usr/bin/glib-compile-schemas" \
        "$develdir/opt/recovery/libexec/glib-compile-schemas"
    cat > "$develdir/opt/recovery/bin/gtkhash" <<'EOF'
#!/bin/sh
set -eu

umask 077
if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    runtime_parent="$XDG_RUNTIME_DIR/efilinux-recovery"
else
    runtime_parent="/tmp/efilinux-recovery-$(id -u)"
fi
mkdir -p "$runtime_parent"
chmod 0700 "$runtime_parent"
runtime=$(mktemp -d "$runtime_parent/gtkhash-schemas.XXXXXX")
cleanup() {
    rm -rf -- "$runtime"
}
trap cleanup EXIT HUP INT TERM

cp /opt/recovery/share/glib-2.0/schemas/*.xml "$runtime/"
/opt/recovery/libexec/glib-compile-schemas "$runtime"
GSETTINGS_SCHEMA_DIR="$runtime" /opt/recovery/bin/gtkhash.bin "$@"
EOF
    chmod 0755 "$develdir/opt/recovery/bin/gtkhash"

    sed -i \
        -e 's#^TryExec=.*#TryExec=/opt/recovery/bin/gtkhash#' \
        -e 's#^Exec=.*#Exec=/opt/recovery/bin/gtkhash %U#' \
        -e 's#^Icon=.*#Icon=document-properties#' \
        -e 's#^Categories=.*#Categories=System;Security;#' \
        "$develdir/opt/recovery/share/applications/org.gtkhash.gtkhash.desktop"
    recovery_publish_usr_paths "$develdir" share/applications
}
check() {
    [[ -x "$develdir/opt/recovery/bin/gtkhash" ]] || die "gtkhash launcher is missing"
    [[ -x "$develdir/opt/recovery/bin/gtkhash.bin" ]] || die "gtkhash binary is missing"
    [[ -x "$develdir/opt/recovery/libexec/glib-compile-schemas" ]] ||
        die "gtkhash schema compiler is missing"
}
devel() {
    strip_all \
        "$develdir/opt/recovery/bin/gtkhash.bin" \
        "$develdir/opt/recovery/libexec/glib-compile-schemas"
}
package() {
    package_keep \
        /opt/recovery/bin/gtkhash \
        /opt/recovery/bin/gtkhash.bin \
        /opt/recovery/libexec/glib-compile-schemas \
        /usr/share/applications/org.gtkhash.gtkhash.desktop \
        /opt/recovery/share/glib-2.0/schemas/ \
        /opt/recovery/share/locale/
}
recipe_main "$@"
