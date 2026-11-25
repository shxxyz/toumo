#!/bin/sh
set -eu
exec "$(dirname -- "$0")/build-native.sh" armel
