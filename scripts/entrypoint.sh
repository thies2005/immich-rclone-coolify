#!/bin/sh
set -eu

log()   { echo "[entrypoint] $*"; }
warn()  { echo "[entrypoint] WARNING: $*" >&2; }
fatal() { echo "[entrypoint] ERROR: $*" >&2; exit 1; }

INTERNXT_REMOTE_NAME="${INTERNXT_REMOTE_NAME:-MyInternxt}"
: "${INTERNXT_EMAIL:?INTERNXT_EMAIL must be set}"
: "${INTERNXT_PASSWORD:?INTERNXT_PASSWORD must be set}"
INTERNXT_TOTP_SECRET="${INTERNXT_TOTP_SECRET:-}"

: "${RCLONE_MOUNT_TARGET:?RCLONE_MOUNT_TARGET must be set (e.g. /mnt/external-library)}"
: "${RCLONE_CACHE_DIR:?RCLONE_CACHE_DIR must be set (e.g. /cache/vfs)}"
: "${RCLONE_VFS_CACHE_MAX_SIZE:?RCLONE_VFS_CACHE_MAX_SIZE must be set (e.g. 8G). Refusing to start without a hard cache limit.}"

CONFIG_DIR="/config/rclone"
mkdir -p "$CONFIG_DIR"

log "Generating rclone.conf for remote '${INTERNXT_REMOTE_NAME}'..."

{
    echo "[${INTERNXT_REMOTE_NAME}]"
    echo "type = internxt"
    echo "email = ${INTERNXT_EMAIL}"
    echo "password = ${INTERNXT_PASSWORD}"
    if [ -n "$INTERNXT_TOTP_SECRET" ]; then
        echo "totp_secret = ${INTERNXT_TOTP_SECRET}"
    fi
} > "$CONFIG_DIR/rclone.conf"

chmod 600 "$CONFIG_DIR/rclone.conf"
log "rclone.conf written to ${CONFIG_DIR}/rclone.conf"

RCLONE_REMOTE_SOURCE="${INTERNXT_REMOTE_NAME}:"

if [ "${RCLONE_VFS_CACHE_MODE:-full}" != "full" ]; then
    warn "RCLONE_VFS_CACHE_MODE is set to '${RCLONE_VFS_CACHE_MODE}'."
    warn "Internxt uses end-to-end encryption. Every file chunk must be fully"
    warn "downloaded and decrypted before reading. Any vfs-cache-mode other"
    warn "than 'full' causes extremely slow or stalled reads, scan timeouts,"
    warn "and apparent hangs on large files."
    warn "Overriding to 'full'."
fi

RCLONE_VFS_CACHE_MAX_AGE="${RCLONE_VFS_CACHE_MAX_AGE:-48h}"
RCLONE_BUFFER_SIZE="${RCLONE_BUFFER_SIZE:-64M}"
RCLONE_READ_AHEAD="${RCLONE_READ_AHEAD:-128M}"
RCLONE_VFS_CACHE_POLL_INTERVAL="${RCLONE_VFS_CACHE_POLL_INTERVAL:-30s}"
RCLONE_DIR_CACHE_TIME="${RCLONE_DIR_CACHE_TIME:-5m}"
RCLONE_TRANSFERS="${RCLONE_TRANSFERS:-2}"
RCLONE_CHECKERS="${RCLONE_CHECKERS:-4}"
RCLONE_RETRIES="${RCLONE_RETRIES:-5}"
RCLONE_LOW_LEVEL_RETRIES="${RCLONE_LOW_LEVEL_RETRIES:-10}"
RCLONE_TIMEOUT="${RCLONE_TIMEOUT:-120s}"
RCLONE_CONTIMEOUT="${RCLONE_CONTIMEOUT:-30s}"
RCLONE_NO_CHECKSUM="${RCLONE_NO_CHECKSUM:-true}"
RCLONE_EXTRA_MOUNT_ARGS="${RCLONE_EXTRA_MOUNT_ARGS:-}"

mkdir -p "${RCLONE_MOUNT_TARGET}" "${RCLONE_CACHE_DIR}"

CHECKSUM_FLAG=""
if [ "${RCLONE_NO_CHECKSUM}" = "true" ]; then
    CHECKSUM_FLAG="--no-checksum"
fi

cleanup() {
    log "Caught signal — unmounting ${RCLONE_MOUNT_TARGET}..."
    fusermount -uz "${RCLONE_MOUNT_TARGET}" 2>/dev/null || umount -l "${RCLONE_MOUNT_TARGET}" 2>/dev/null || true
    log "Unmount complete. Exiting."
    exit 0
}
trap cleanup TERM INT QUIT

log "Starting rclone mount:"
log "  remote:       ${RCLONE_REMOTE_SOURCE}"
log "  mount target: ${RCLONE_MOUNT_TARGET}"
log "  cache dir:    ${RCLONE_CACHE_DIR}"
log "  cache max:    ${RCLONE_VFS_CACHE_MAX_SIZE}"
log "  2FA/TOTP:     $([ -n "$INTERNXT_TOTP_SECRET" ] && echo 'enabled' || echo 'disabled')"

rclone mount \
    "${RCLONE_REMOTE_SOURCE}" \
    "${RCLONE_MOUNT_TARGET}" \
    --vfs-cache-mode full \
    --vfs-cache-max-size "${RCLONE_VFS_CACHE_MAX_SIZE}" \
    --vfs-cache-max-age "${RCLONE_VFS_CACHE_MAX_AGE}" \
    --cache-dir "${RCLONE_CACHE_DIR}" \
    --buffer-size "${RCLONE_BUFFER_SIZE}" \
    --vfs-read-ahead "${RCLONE_READ_AHEAD}" \
    --vfs-cache-poll-interval "${RCLONE_VFS_CACHE_POLL_INTERVAL}" \
    --dir-cache-time "${RCLONE_DIR_CACHE_TIME}" \
    --transfers "${RCLONE_TRANSFERS}" \
    --checkers "${RCLONE_CHECKERS}" \
    --retries "${RCLONE_RETRIES}" \
    --low-level-retries "${RCLONE_LOW_LEVEL_RETRIES}" \
    --timeout "${RCLONE_TIMEOUT}" \
    --contimeout "${RCLONE_CONTIMEOUT}" \
    ${CHECKSUM_FLAG} \
    --allow-other \
    --log-level INFO \
    ${RCLONE_EXTRA_MOUNT_ARGS} &

RCLONE_PID=$!
log "rclone started (PID ${RCLONE_PID})"

wait $RCLONE_PID
EXIT_CODE=$?
log "rclone exited with code ${EXIT_CODE}"
fusermount -uz "${RCLONE_MOUNT_TARGET}" 2>/dev/null || umount -l "${RCLONE_MOUNT_TARGET}" 2>/dev/null || true
exit $EXIT_CODE
