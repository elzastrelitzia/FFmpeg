#!/usr/bin/env bash
# Stripped ffmpeg: audio-only decode, wav/pcm_s16le output.
set -euo pipefail
cd "$(dirname "$0")"

JOBS="$(nproc)"

# everything off, then opt back in. deps come along automatically via *_select.
./configure \
  --disable-everything \
  --disable-debug --disable-doc \
  --enable-stripping \
  --enable-static --disable-shared \
  --pkg-config-flags=--static \
  --disable-programs --enable-ffmpeg --disable-ffplay --disable-ffprobe \
  --disable-indevs --disable-outdevs --disable-network \
  --disable-vaapi --disable-libdrm --disable-vdpau --disable-xlib \
  --disable-vulkan --disable-opencl --disable-libmfx --disable-cuda \
  --disable-zlib --disable-bzlib \
  --extra-cflags="-Os -ffunction-sections -fdata-sections" \
  --extra-ldflags="-static -Wl,--gc-sections" \
  \
  --enable-decoder=opus,aac,vorbis,mp3,mp3float,flac,alac,pcm_s16le \
  --enable-encoder=pcm_s16le \
  --enable-parser=opus,aac,flac,mpegaudio \
  --enable-demuxer=matroska,mov,ogg,mp3,flac,wav,aac \
  --enable-muxer=wav,tee \
  --enable-protocol=file,pipe,fd \
  --enable-filter=anull,aresample,aformat,atrim

make -j"$JOBS"
