#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=nfs-utils
pkgver=2.9.1
depends=(glibc keyutils krb5 libcap libevent libnl libtirpc rpcbind util-linux)
builddepends=(linux-headers)
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/nfs-utils-$pkgver.tar.xz"
    download "https://www.kernel.org/pub/linux/utils/nfs-utils/$pkgver/nfs-utils-$pkgver.tar.xz" "$archive"
    checksum sha256 302846343bf509f8f884c23bdbd0fe853b7f7cbb6572060a9082279d13b21a2c "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/files/module-config-paths.patch" \
        "$srcdir/module-config-paths.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/source" -Np1 -i "$srcdir/module-config-paths.patch"
}

build_host_rpcgen() {
    local source="$builddir/tools/rpcgen"
    local output="$builddir/tools/rpcgen/rpcgen"

    mkdir -p "$(dirname -- "$output")"
    gcc \
        -O2 \
        -DHAVE_CONFIG_H \
        -I"$builddir/support/include" \
        -I"$source" \
        -o "$output" \
        "$source/rpc_clntout.c" \
        "$source/rpc_cout.c" \
        "$source/rpc_hout.c" \
        "$source/rpc_main.c" \
        "$source/rpc_parse.c" \
        "$source/rpc_sample.c" \
        "$source/rpc_scan.c" \
        "$source/rpc_svcout.c" \
        "$source/rpc_tblout.c" \
        "$source/rpc_util.c"
}

build() {
    local config_root=/opt/recovery/etc

    cp -a "$srcdir/source/." "$builddir/"
    PKG_CONFIG=/usr/bin/pkg-config \
    target_release_configure "$builddir" "$builddir" \
        --bindir=/usr/bin \
        --sbindir=/usr/bin \
        --libexecdir=/usr/lib/nfs-utils \
        --disable-static \
        --enable-shared \
        --enable-nfsv4 \
        --with-rpcgen=internal \
        --disable-blkmapd \
        --enable-gss \
        --disable-svcgss \
        --disable-kprefix \
        --enable-uuid \
        --enable-mount \
        --enable-libmount-mount \
        --disable-sbin-override \
        --disable-junction \
        --enable-tirpc \
        --enable-ipv6 \
        --enable-mountconfig \
        --disable-nfsdcld \
        --disable-nfsrahead \
        --disable-nfsdcltrack \
        --disable-nfsdctl \
        --disable-nfsv4server \
        --disable-ldap \
        --disable-gums \
        --with-statdpath=/run/nfs/statd \
        --with-statduser=root \
        --with-start-statd=/usr/bin/start-statd \
        --without-systemd \
        --with-nfsconfig="$config_root/nfs.conf" \
        --with-mountfile="$config_root/nfsmount.conf" \
        --with-tirpcinclude="$EFILINUX_SYSROOT/usr/include/tirpc" \
        --with-krb5="$EFILINUX_SYSROOT/usr" \
        --with-pluginpath=/usr/lib/libnfsidmap
    build_host_rpcgen
    target_make_install "$builddir" "$develdir"
    install -Dm0644 "$builddir/nfs.conf" \
        "$develdir$config_root/nfs.conf"
    install -Dm0644 "$builddir/utils/mount/nfsmount.conf" \
        "$develdir$config_root/nfsmount.conf"
    install -Dm0644 "$builddir/support/nfsidmap/idmapd.conf" \
        "$develdir$config_root/idmapd.conf"
}

devel() {
    find "$develdir" -type f \( -name '*.a' -o -name '*.la' \) -delete
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=(
        /usr/bin/mount.nfs
        /usr/bin/mount.nfs4
        /usr/bin/umount.nfs
        /usr/bin/umount.nfs4
        /usr/bin/showmount
        /usr/bin/nfsstat
        /usr/bin/rpc.statd
        /usr/bin/sm-notify
        /usr/bin/start-statd
        /usr/bin/rpc.gssd
        /usr/bin/rpc.idmapd
        /usr/bin/nfsidmap
        /opt/recovery/etc/nfs.conf
        /opt/recovery/etc/nfsmount.conf
        /opt/recovery/etc/idmapd.conf
    )
    package_add_library_family keep 'libnfsidmap.so.*'
    [[ ! -d "$pkgdir/usr/lib/libnfsidmap" ]] || keep+=(/usr/lib/libnfsidmap/)
    package_keep "${keep[@]}"
}

recipe_main "$@"
