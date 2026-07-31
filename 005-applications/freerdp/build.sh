#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=freerdp
pkgver=3.30.0
depends=(ffmpeg-libs glibc openssl pulseaudio zlib)
builddepends=(linux-headers)
makedepends=(cmake gcc ninja pkg-config)
prepare() {
    local archive="$downloaddir/freerdp-$pkgver.tar.gz"
    download "https://pub.freerdp.com/releases/freerdp-$pkgver.tar.gz" "$archive"
    checksum sha256 e2687d02dea6fede004d36391dac1a74ce57a210f8867fd95033171d4909590c "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    local small_cflags="${CFLAGS/-O2/-Os} -ffunction-sections -fdata-sections"
    local small_cxxflags="${CXXFLAGS/-O2/-Os} -ffunction-sections -fdata-sections"
    local small_ldflags="$LDFLAGS -Wl,--gc-sections"

    CFLAGS="$small_cflags" CXXFLAGS="$small_cxxflags" LDFLAGS="$small_ldflags" \
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DBUILD_SHARED_LIBS=ON \
        -DCMAKE_SKIP_RPATH=ON \
        -DBUILD_TESTING=OFF \
        -DBUILD_TESTING_INTERNAL=OFF \
        -DBUILD_BENCHMARK=OFF \
        -DWITH_MANPAGES=OFF \
        -DWITH_SAMPLE=OFF \
        -DWITH_CLIENT_COMMON=ON \
        -DWITH_CLIENT=OFF \
        -DWITH_CLIENT_SDL=OFF \
        -DWITH_SERVER=OFF \
        -DWITH_SERVER_CHANNELS=OFF \
        -DWITH_SERVER_INTERFACE=OFF \
        -DWITH_CHANNELS=ON \
        -DWITH_CLIENT_CHANNELS=ON \
        -DWITH_X11=OFF \
        -DWITH_WAYLAND=OFF \
        -DWITH_FFMPEG=ON \
        -DWITH_DSP_FFMPEG=ON \
        -DWITH_VIDEO_FFMPEG=ON \
        -DWITH_SWSCALE=ON \
        -DWITH_OPENH264=OFF \
        -DWITH_GFX_AV1=OFF \
        -DWITH_GFX_AZURE=OFF \
        -DWITH_ALSA=OFF \
        -DWITH_PULSE=ON \
        -DWITH_OSS=OFF \
        -DWITH_CUPS=OFF \
        -DWITH_PCSC=OFF \
        -DWITH_PCSC_WINPR=OFF \
        -DWITH_FUSE=OFF \
        -DWITH_KRB5=OFF \
        -DWITH_AAD=OFF \
        -DWITH_JSON_DISABLED=ON \
        -DWITH_UNICODE_BUILTIN=ON \
        -DWITH_TIMEZONE_COMPILED=ON \
        -DWITH_TIMEZONE_ICU=OFF \
        -DWITH_SYSTEMD=OFF \
        -DWITH_URIPARSER=OFF \
        -DWITH_JPEG=OFF \
        -DWITH_CAIRO=OFF \
        -DWITH_OPENCL=OFF \
        -DWITH_THIRD_PARTY=OFF \
        -DWITH_VERBOSE_WINPR_ASSERT=OFF \
        -DWITH_DEBUG_SYMBOLS=OFF \
        -DWITH_CCACHE=OFF \
        -DWITH_CLANG_FORMAT=OFF \
        -DWITH_SMARTCARD_EMULATE=OFF \
        -DCHANNEL_AINPUT=ON \
        -DCHANNEL_AUDIN=OFF \
        -DCHANNEL_CLIPRDR=ON \
        -DCHANNEL_DISP=ON \
        -DCHANNEL_DRDYNVC=ON \
        -DCHANNEL_DRIVE=ON \
        -DCHANNEL_ECHO=OFF \
        -DCHANNEL_ENCOMSP=OFF \
        -DCHANNEL_GEOMETRY=ON \
        -DCHANNEL_GFXREDIR=OFF \
        -DCHANNEL_LOCATION=OFF \
        -DCHANNEL_PARALLEL=OFF \
        -DCHANNEL_PRINTER=OFF \
        -DCHANNEL_RAIL=ON \
        -DCHANNEL_RDP2TCP=OFF \
        -DCHANNEL_RDPDR=ON \
        -DCHANNEL_RDPEAR=OFF \
        -DCHANNEL_RDPECAM=OFF \
        -DCHANNEL_RDPEI=ON \
        -DCHANNEL_RDPEMSC=OFF \
        -DCHANNEL_RDPEWA=OFF \
        -DCHANNEL_RDPGFX=ON \
        -DCHANNEL_RDPSND=ON \
        -DCHANNEL_REMDESK=OFF \
        -DCHANNEL_SERIAL=OFF \
        -DCHANNEL_SMARTCARD=OFF \
        -DCHANNEL_SSHAGENT=OFF \
        -DCHANNEL_TELEMETRY=OFF \
        -DCHANNEL_TSMF=OFF \
        -DCHANNEL_URBDRC=OFF \
        -DCHANNEL_VIDEO=ON
    CFLAGS="$small_cflags" CXXFLAGS="$small_cxxflags" LDFLAGS="$small_ldflags" \
        target_cmake_install "$builddir" "$develdir"
}
devel() {
    find "$develdir" -type f -name '*.a' -delete
    strip_all "$develdir/usr/lib"
}
package() {
    local -a keep=()
    local pattern
    for pattern in \
        'libfreerdp3.so.*' \
        'libfreerdp-client3.so.*' \
        'libwinpr3.so.*'; do
        package_add_library_family keep "$pattern"
    done
    package_keep "${keep[@]}"
}
recipe_main "$@"
