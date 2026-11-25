#!/bin/sh
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
plugin="$root/toumo.koplugin"
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT

build_one() {
    name=$1
    shift
    "${ZIG:-zig}" cc "$@" -O3 -fno-stack-protector -shared -fPIC \
        -ffunction-sections -fdata-sections -nostdlib -Wl,--gc-sections \
        -Wl,--version-script="$root/tools/exports.map" -Wl,-s \
        "$plugin/toumo.c" -o "$build/toumo-$name.so"
    install -m 755 "$build/toumo-$name.so" "$plugin/toumo-$name.so"
}
if [ "$#" -eq 0 ]; then set -- armel armel-generic armhf aarch64; fi
for arch do
    case "$arch" in
        armel) build_one armel -target arm-linux-gnueabi.2.19 -mcpu=cortex_a9 -mfloat-abi=soft ;;
        armel-generic) build_one armel-generic -target arm-linux-gnueabi.2.19 -mcpu=arm1176jzf_s -mfloat-abi=soft ;;
        armhf) build_one armhf -target arm-linux-gnueabihf.2.19 -mcpu=arm1176jzf_s -mfloat-abi=hard ;;
        aarch64) build_one aarch64 -target aarch64-linux-gnu.2.17 -mcpu=generic -Wl,-z,max-page-size=65536 ;;
        *) echo "Unknown target: $arch (expected armel, armel-generic, armhf or aarch64)" >&2; exit 2 ;;
    esac
done
