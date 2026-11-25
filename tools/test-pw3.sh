#!/bin/sh
set -eu
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <SSH host or alias for a Paperwhite 3>" >&2
    exit 2
fi
host=$1
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
stage=$(ssh "$host" 'mktemp -d /tmp/toumo-test.XXXXXX')
case "$stage" in
    /tmp/toumo-test.[A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9]) ;;
    *) echo "Unexpected temporary directory" >&2; exit 1 ;;
esac
trap 'ssh "$host" "rm -rf $stage"' EXIT
cd "$root"
tar -czf - toumo.koplugin tests/device.lua tests/fixture.epub | ssh "$host" "cd '$stage' && tar -xzf -"
ssh "$host" "set -eu; mkdir '$stage/fallback'; cp '$stage/toumo.koplugin/toumo_raster.lua' '$stage/toumo.koplugin/paper.grain' '$stage/fallback/'; mv '$stage/tests/fixture.epub' '$stage/test.epub'; cd /mnt/us/koreader; ulimit -c 0; KO_HOME='$stage' LD_LIBRARY_PATH=./libs ./luajit '$stage/tests/device.lua' '$stage'"
