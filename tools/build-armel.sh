#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
plugin="$root/versoink.koplugin"
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT

"${ZIG:-zig}" cc -target arm-linux-gnueabi.2.19 -mcpu=cortex_a9 -mfloat-abi=soft \
    -O3 -fno-stack-protector -shared -fPIC -ffunction-sections -fdata-sections \
    -nostdlib -Wl,--gc-sections -Wl,--version-script="$root/tools/exports.map" -Wl,-s \
    "$plugin/versoink.c" -o "$build/versoink-armel.so"
install -m 755 "$build/versoink-armel.so" "$plugin/versoink-armel.so"
