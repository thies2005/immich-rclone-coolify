#!/usr/bin/env bash
set -euo pipefail

# One-command host-side rclone update.
#
#   sudo bash update-rclone.sh                # rebuild from the fork's master
#   sudo bash update-rclone.sh v1.76.0        # rebuild from a specific fork tag
#   sudo bash update-rclone.sh --skip-containers   # don't stop/restart Immich containers
#
# What it does:
#   1. Updates this repo clone (git checkout master && git pull) and re-runs
#      itself once, so you always execute the latest version of this script.
#   2. Stops the Docker containers that bind-mount /mnt/immich-external-library
#      (they would hold a dead bind across the FUSE mount restart otherwise).
#   3. Runs install.sh --yes (rebuilds rclone, restarts the mount; Internxt
#      credentials in /etc/immich-rclone are preserved).
#   4. Verifies service + mount, restarts the containers, waits for health.
#
# Immich itself is NOT updated by this script — redeploy in Coolify for that
# (IMMICH_VERSION env var; floating "v3" pulls the latest v3.x minor).

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }

SERVICE_NAME="immich-rclone"
COOLIFY_MOUNT_SERVICE="coolify-backups-mount.service"
INSTALL_DIR="/opt/immich-rclone"
MOUNT_POINT="/mnt/immich-external-library"
LOG_FILE="/var/log/immich-rclone/rclone.log"

RCLONE_TAG=""
SKIP_CONTAINERS=0
for arg in "$@"; do
    case "${arg}" in
        --skip-containers) SKIP_CONTAINERS=1 ;;
        -*) fail "Unknown option: ${arg} (supported: --skip-containers)" ;;
        *) RCLONE_TAG="${arg}" ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "$(id -u)" -eq 0 ] || fail "Run as root: sudo bash update-rclone.sh"

# ── 1. Self-update this repo clone, then re-exec the fresh script ──────────
if [ "${UPDATE_RCLONE_SELF_UPDATED:-0}" != "1" ]; then
    info "Updating repo clone at ${SCRIPT_DIR}..."
    git -C "${SCRIPT_DIR}" checkout master 2>/dev/null || warn "Could not checkout master (continuing)"
    git -C "${SCRIPT_DIR}" pull --ff-only 2>/dev/null || warn "git pull failed (continuing with local copy)"
    export UPDATE_RCLONE_SELF_UPDATED=1
    exec bash "${SCRIPT_DIR}/update-rclone.sh" "$@"
fi

# ── 2. Current version ──────────────────────────────────────────────────────
describe_rclone_version() {
    if [ ! -x "${INSTALL_DIR}/rclone" ]; then
        echo "(not installed)"
        return 0
    fi
    local ver rev
    ver="$("${INSTALL_DIR}/rclone" version 2>/dev/null | head -n1 || true)"
    [ -n "${ver}" ] || ver="(unknown)"
    if [[ "${ver}" == *-DEV ]]; then
        rev="$("${INSTALL_DIR}/rclone" version --deps 2>/dev/null | awk '/^- vcs\.revision:/ {print substr($3, 1, 7); exit}' || true)"
        if [ -n "${rev}" ]; then
            echo "${ver} (${rev})"
            return 0
        fi
    fi
    echo "${ver}"
}

OLD_VERSION="$(describe_rclone_version)"
info "Current rclone: ${OLD_VERSION}"

# ── 3. Find and stop containers that bind-mount the external library ───────
# Restarting the FUSE mount under running containers leaves them on a stale
# bind (external library breaks until the container restarts). Stop/start is
# transparent to Coolify — no redeploy, no config change.
CONTAINERS=()
if [ "${SKIP_CONTAINERS}" = "0" ] && command -v docker &>/dev/null && docker info &>/dev/null; then
    for id in $(docker ps -q); do
        if docker inspect --format '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' "${id}" 2>/dev/null | grep -qx "${MOUNT_POINT}"; then
            CONTAINERS+=("$(docker inspect --format '{{.Name}}' "${id}" | sed 's#^/##')")
        fi
    done
fi

CONTAINERS_STOPPED=0
COOLIFY_MOUNT_STOPPED=0

restart_coolify_mount() {
    if [ "${COOLIFY_MOUNT_STOPPED}" = "1" ]; then
        COOLIFY_MOUNT_STOPPED=0
        info "Restarting ${COOLIFY_MOUNT_SERVICE}..."
        if systemctl start "${COOLIFY_MOUNT_SERVICE}"; then
            ok "${COOLIFY_MOUNT_SERVICE} restarted"
        else
            warn "Failed to restart ${COOLIFY_MOUNT_SERVICE} — check: systemctl status ${COOLIFY_MOUNT_SERVICE}"
        fi
    fi
}

restart_containers() {
    if [ "${CONTAINERS_STOPPED}" = "1" ] && [ ${#CONTAINERS[@]} -gt 0 ]; then
        CONTAINERS_STOPPED=0
        info "Starting containers again..."
        if ! docker start "${CONTAINERS[@]}" >/dev/null; then
            warn "Failed to start one or more containers: ${CONTAINERS[*]}"
            return 1
        fi
        info "Waiting for containers to become healthy (max 120s)..."
        for c in "${CONTAINERS[@]}"; do
            STATUS="unknown"
            for _ in $(seq 1 60); do
                STATUS="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${c}" 2>/dev/null || echo "unknown")"
                if [ "${STATUS}" = "healthy" ] || [ "${STATUS}" = "running" ]; then
                    break
                fi
                sleep 2
            done
            ok "${c}: ${STATUS}"
        done
    fi
}

cleanup_on_exit() {
    local rc=$?
    set +e
    restart_coolify_mount
    restart_containers
    exit "${rc}"
}

trap cleanup_on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [ "${SKIP_CONTAINERS}" = "1" ]; then
    warn "--skip-containers: leaving containers running — redeploy in Coolify afterwards, or the external library will be broken"
elif [ ${#CONTAINERS[@]} -gt 0 ]; then
    info "Stopping ${#CONTAINERS[@]} container(s) using the mount: ${CONTAINERS[*]}"
    CONTAINERS_STOPPED=1
    docker stop "${CONTAINERS[@]}" >/dev/null
else
    info "No running containers bind-mount ${MOUNT_POINT} — nothing to stop"
fi

# Stop coolify-backups-mount.service if installed and active so it doesn't keep
# running on a deleted /opt/immich-rclone/rclone binary inode (its config in
# /etc/coolify-backup/rclone.conf is separate from /etc/immich-rclone/rclone.conf).
if command -v systemctl &>/dev/null && systemctl is-active --quiet "${COOLIFY_MOUNT_SERVICE}"; then
    info "Stopping ${COOLIFY_MOUNT_SERVICE} before replacing ${INSTALL_DIR}/rclone..."
    COOLIFY_MOUNT_STOPPED=1
    systemctl stop "${COOLIFY_MOUNT_SERVICE}"
fi

# ── 4. Rebuild rclone via install.sh ────────────────────────────────────────
info "Rebuilding rclone from fork (${RCLONE_TAG:-master})..."
if [ -n "${RCLONE_TAG}" ]; then
    RCLONE_BRANCH="${RCLONE_TAG}" bash "${SCRIPT_DIR}/install.sh" --yes
else
    bash "${SCRIPT_DIR}/install.sh" --yes
fi

# ── 5. Verify ───────────────────────────────────────────────────────────────
MOUNT_OK=1
if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
    MOUNT_OK=0
    warn "Service ${SERVICE_NAME} is not active"
fi
if ! mountpoint -q "${MOUNT_POINT}"; then
    MOUNT_OK=0
    warn "Mount ${MOUNT_POINT} is not mounted"
fi

restart_coolify_mount
restart_containers

NEW_VERSION="$(describe_rclone_version)"

echo ""
if [ "${MOUNT_OK}" = "1" ]; then
    echo -e "${GREEN}rclone updated: ${OLD_VERSION} -> ${NEW_VERSION}${NC}"
    echo -e "${GREEN}Mount is live at ${MOUNT_POINT}.${NC}"
    echo ""
    echo "  Immich version itself is managed by Coolify (IMMICH_VERSION env var;"
    echo "  floating 'v3' pulls the latest v3.x minor on every redeploy)."
    echo "  Verify in Immich: Administration -> External Libraries -> scan."
else
    echo -e "${RED}rclone was rebuilt (${OLD_VERSION} -> ${NEW_VERSION}) but the mount is NOT ready.${NC}"
    echo ""
    echo "  Diagnostics:"
    echo "    systemctl status ${SERVICE_NAME}"
    echo "    journalctl -u ${SERVICE_NAME} -n 30"
    echo "    tail -n 30 ${LOG_FILE}"
    echo ""
    echo "  The external library stays broken until the mount is back. Try:"
    echo "    sudo systemctl restart ${SERVICE_NAME}"
    echo "  If it keeps failing, stop the service and clear the VFS cache:"
    echo "    sudo systemctl stop ${SERVICE_NAME} && sudo rm -rf /var/cache/immich-rclone/*"
    echo "    sudo systemctl start ${SERVICE_NAME}"
    exit 1
fi
