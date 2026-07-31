#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=ffmpeg-libs
pkgver=8.1.2
depends=(glibc zlib)
builddepends=(linux-headers)
makedepends=(gcc make nasm pkg-config)
prepare() {
    local archive="$downloaddir/ffmpeg-$pkgver.tar.xz"
    download "https://ffmpeg.org/releases/ffmpeg-$pkgver.tar.xz" "$archive"
    checksum sha256 464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c "$archive"
    extract "$archive" "$srcdir/source"
}
build() {
    local -a decoders=(
        aac aac_latm ac3 alac ass av1 dca eac3 flac h264 hevc mjpeg movtext
        mp3 mp3float mpeg2video mpeg4 opus pcm_f32le pcm_s16le pcm_s24le
        ssa subrip vorbis vp8 vp9 webvtt wmav1 wmav2
    )
    local -a parsers=(aac aac_latm ac3 av1 dca flac h264 hevc mjpeg opus vorbis vp8 vp9)
    local -a demuxers=(
        aac ac3 asf ass av1 avi eac3 flac flv h264 hevc matroska mjpeg mov
        mp3 mpegps mpegts ogg pcm_f32le pcm_s16le pcm_s24le wav webvtt
    )
    local decoder_list parser_list demuxer_list
    decoder_list=$(IFS=,; echo "${decoders[*]}")
    parser_list=$(IFS=,; echo "${parsers[*]}")
    demuxer_list=$(IFS=,; echo "${demuxers[*]}")

    mkdir -p "$builddir"
    cd "$builddir"
    "$srcdir/source/configure" \
        --prefix=/usr \
        --libdir=/usr/lib \
        --enable-cross-compile \
        --target-os=linux \
        --arch=x86_64 \
        --cc="$CC" \
        --cxx="$CXX" \
        --ar="$AR" \
        --nm="$NM" \
        --ranlib="$RANLIB" \
        --strip="$STRIP" \
        --sysroot="$EFILINUX_SYSROOT" \
        --extra-cflags="$CFLAGS -ffunction-sections -fdata-sections" \
        --extra-ldflags="$LDFLAGS -Wl,--gc-sections" \
        --pkg-config=/usr/bin/pkg-config \
        --pkg-config-flags=--static \
        --enable-shared \
        --disable-static \
        --enable-small \
        --disable-autodetect \
        --disable-programs \
        --disable-doc \
        --disable-debug \
        --disable-network \
        --disable-everything \
        --enable-avcodec \
        --enable-avfilter \
        --enable-avformat \
        --enable-avutil \
        --enable-swresample \
        --enable-swscale \
        --enable-pthreads \
        --enable-zlib \
        --enable-protocol=file \
        --enable-decoder="$decoder_list" \
        --enable-parser="$parser_list" \
        --enable-demuxer="$demuxer_list"
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}
devel() {
    find "$develdir" -type f -name '*.a' -delete
    strip_all "$develdir/usr/lib"
}
package() {
    local -a keep=()
    local library
    for library in avcodec avdevice avfilter avformat avutil swresample swscale; do
        package_add_library_family keep "lib$library.so.*"
    done
    package_keep "${keep[@]}"
}
recipe_main "$@"
