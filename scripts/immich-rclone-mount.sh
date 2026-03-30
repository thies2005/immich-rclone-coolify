#!/bin/sh
set -eu

INTERNXT_REMOTE_NAME="${INTERNXT_REMOTE_NAME:-MyInternxt}"
RCLONE_MOUNT_TARGET="${RCLONE_MOUNT_TARGET:-/mnt/external-library}"
RCLONE_CACHE_DIR="${RCLONE_CACHE_DIR:-/cache/vfs}"

if [ -z "${INTERNXT_EMAIL:-}" ] || [ -z "${INTERNXT_PASSWORD:-}" ]; then
    echo "[immich-rclone] INTERNXT_EMAIL and INTERNXT_PASSWORD not set, skipping mount"
    return 0 2>/dev/null || exit 0
fi

CONFIG_DIR="/config/rclone"
mkdir -p "$CONFIG_DIR" "${RCLONE_MOUNT_TARGET}" "${RCLONE_CACHE_DIR}"

OBSCURED_PASSWORD="$(rclone obscure "${INTERNXT_PASSWORD}")"
if [ -z "${OBSCURED_PASSWORD}" ]; then
    echo "[immich-rclone] ERROR: Failed to obscure password"
    return 1 2>/dev/null || exit 1
fi

{
    echo "[${INTERNXT_REMOTE_NAME}]"
    echo "type = internxt"
    echo "email = ${INTERNXT_EMAIL}"
    echo "pass = ${OBSCURED_PASSWORD}"
    if [ -n "${INTERNXT_TOTP_SECRET:-}" ]; then
        echo "totp_secret = ${INTERNXT_TOTP_SECRET}"
    fi
} > "$CONFIG_DIR/rclone.conf"
chmod 600 "$CONFIG_DIR/rclone.conf"

if mountpoint -q "${RCLONE_MOUNT_TARGET}" 2>/dev/null; then
    echo "[immich-rclone] Stale mount detected at ${RCLONE_MOUNT_TARGET} — cleaning up..."
    fusermount -uz "${RCLONE_MOUNT_TARGET}" 2>/dev/null || umount -l "${RCLONE_MOUNT_TARGET}" 2>/dev/null || true
    sleep 1
fi

echo "[immich-rclone] Starting rclone mount:"
echo "[immich-rclone]   remote:       ${INTERNXT_REMOTE_NAME}:"
echo "[immich-rclone]   mount target: ${RCLONE_MOUNT_TARGET}"
echo "[immich-rclone]   cache dir:    ${RCLONE_CACHE_DIR}"
echo "[immich-rclone]   cache max:    ${RCLONE_VFS_CACHE_MAX_SIZE:-8G}"
echo "[immich-rclone]   2FA/TOTP:     $([ -n "${INTERNXT_TOTP_SECRET:-}" ] && echo 'enabled' || echo 'disabled')"

rclone mount \
    "${INTERNXT_REMOTE_NAME}:" \
    "${RCLONE_MOUNT_TARGET}" \
    --config "$CONFIG_DIR/rclone.conf" \
    --vfs-cache-mode full \
    --vfs-cache-max-size "${RCLONE_VFS_CACHE_MAX_SIZE:-8G}" \
    --vfs-cache-max-age "${RCLONE_VFS_CACHE_MAX_AGE:-48h}" \
    --cache-dir "${RCLONE_CACHE_DIR}" \
    --buffer-size "${RCLONE_BUFFER_SIZE:-64M}" \
    --vfs-read-ahead "${RCLONE_READ_AHEAD:-128M}" \
    --vfs-cache-poll-interval "${RCLONE_VFS_CACHE_POLL_INTERVAL:-30s}" \
    --dir-cache-time "${RCLONE_DIR_CACHE_TIME:-5m}" \
    --transfers "${RCLONE_TRANSFERS:-2}" \
    --checkers "${RCLONE_CHECKERS:-4}" \
    --retries "${RCLONE_RETRIES:-5}" \
    --low-level-retries "${RCLONE_LOW_LEVEL_RETRIES:-10}" \
    --timeout "${RCLONE_TIMEOUT:-120s}" \
    --contimeout "${RCLONE_CONTIMEOUT:-30s}" \
    --no-checksum \
    --allow-other \
    --log-level INFO &

RCLONE_PID=$!
echo "[immich-rclone] rclone started (PID ${RCLONE_PID})"

_cleanup_rclone() {
    echo "[immich-rclone] Caught signal — stopping rclone..."
    kill "$RCLONE_PID" 2>/dev/null || true
    wait "$RCLONE_PID" 2>/dev/null || true
    fusermount -uz "${RCLONE_MOUNT_TARGET}" 2>/dev/null || true
}
trap _cleanup_rclone TERM INT QUIT

for i in $(seq 1 60); do
    if mountpoint -q "${RCLONE_MOUNT_TARGET}" 2>/dev/null; then
        if ls "${RCLONE_MOUNT_TARGET}" >/dev/null 2>&1; then
            echo "[immich-rclone] FUSE mount ready after ${i}s"
            return 0 2>/dev/null || exit 0
        fi
    fi
    sleep 1
done

echo "[immich-rclone] WARNING: FUSE mount not ready after 60s, continuing anyway..."
