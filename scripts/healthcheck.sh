#!/bin/sh
set -eu

MOUNT_TARGET="${RCLONE_MOUNT_TARGET:-/mnt/external-library}"
REQUIRE_CONTENTS="${RCLONE_HEALTHCHECK_REQUIRE_CONTENTS:-false}"

if ! mountpoint -q "${MOUNT_TARGET}" 2>/dev/null; then
    echo "HEALTHCHECK FAIL: ${MOUNT_TARGET} is not a mountpoint"
    exit 1
fi

if [ "${REQUIRE_CONTENTS}" = "true" ]; then
    if ! ls -1qA "${MOUNT_TARGET}" 2>/dev/null | grep -q .; then
        echo "HEALTHCHECK FAIL: ${MOUNT_TARGET} is empty — remote may be unreachable"
        exit 1
    fi
fi

exit 0
