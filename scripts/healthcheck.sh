#!/bin/sh
set -eu

MOUNT_TARGET="${RCLONE_MOUNT_TARGET:-/mnt/external-library}"

if ! mountpoint -q "${MOUNT_TARGET}" 2>/dev/null; then
    echo "HEALTHCHECK FAIL: ${MOUNT_TARGET} is not a mountpoint"
    exit 1
fi

if ! ls -1qA "${MOUNT_TARGET}" 2>/dev/null | grep -q .; then
    echo "HEALTHCHECK FAIL: ${MOUNT_TARGET} is empty — remote may be unreachable"
    exit 1
fi

exit 0
