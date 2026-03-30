#!/bin/sh
set -eu

. /usr/local/bin/immich-rclone-mount.sh

exec gosu immich tini -- ./start.sh "$@"
