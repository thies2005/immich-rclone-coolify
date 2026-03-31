#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }

INSTALL_DIR="/opt/immich-rclone"
CONFIG_DIR="/etc/immich-rclone"
CACHE_DIR="/var/cache/immich-rclone"
MOUNT_POINT="/mnt/immich-external-library"
SERVICE_NAME="immich-rclone"
RCLONE_REPO="https://github.com/thies2005/rclone.git"
RCLONE_BRANCH="master"

RELEASE=$(lsb_release -is 2>/dev/null || cat /etc/os-release 2>/dev/null | grep ^ID= | cut -d= -f2 || echo "linux")
is_debian_like() { [[ "$RELEASE" =~ ^(debian|ubuntu|linuxmint|pop)_os) ]] || command -v apt-get &>/dev/null; }

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        Immich + Internxt (rclone) — Host Install            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

if [ "$(id -u)" -ne 0 ]; then
    fail "Run this script as root: sudo bash install.sh"
fi

info "This will:"
echo "  1. Install build dependencies (git, golang, fuse3)"
echo "  2. Compile the custom rclone fork with Internxt + 2FA support"
echo "  3. Ask for your Internxt credentials"
echo "  4. Create a systemd service that auto-mounts on boot"
echo "  5. Create the mount point at ${MOUNT_POINT}"
echo ""
echo "  Your Coolify Docker containers will access files via bind mount."
echo ""
read -rp "Press Enter to continue or Ctrl+C to cancel..."

if is_debian_like; then
    info "Installing dependencies (apt)..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq git golang-go fuse3
    ok "Dependencies installed"
else
    if command -v go &>/dev/null && command -v git &>/dev/null && command -v fusermount3 &>/dev/null; then
        ok "Dependencies already present"
    else
        info "Installing dependencies (dnf/yum)..."
        if command -v dnf &>/dev/null; then
            dnf install -y git golang fuse3 fuse3-devel
        elif command -v yum &>/dev/null; then
            yum install -y git golang fuse fuse3-devel
        else
            fail "Cannot auto-install dependencies. Install git, golang, and fuse3 manually, then re-run."
        fi
        ok "Dependencies installed"
    fi
fi

echo "user_allow_other" > /etc/fuse.conf
ok "FUSE configured"

info "Cloning rclone fork (${RCLONE_BRANCH})..."
TMPDIR=$(mktemp -d)
git clone --depth 1 --branch "${RCLONE_BRANCH}" "${RCLONE_REPO}" "${TMPDIR}/rclone"
cd "${TMPDIR}/rclone"

info "Compiling rclone (this takes 3-8 minutes)..."
CGO_ENABLED=0 go build -v -ldflags "-s" -o "${INSTALL_DIR}/rclone" .
ok "rclone compiled"

cd /
rm -rf "${TMPDIR}"
ok "Build artifacts cleaned up"

mkdir -p "${CONFIG_DIR}" "${CACHE_DIR}" "${MOUNT_POINT}"
ok "Directories created: ${CONFIG_DIR}, ${CACHE_DIR}, ${MOUNT_POINT}"

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  Internxt Credentials"
echo "══════════════════════════════════════════════════════════════"
echo ""

read -rp "Internxt email: " INTERNXT_EMAIL
while true; do
    read -rsp "Internxt password: " INTERNXT_PASSWORD
    echo ""
    read -rsp "Confirm password: " INTERNXT_PASSWORD2
    echo ""
    if [ "$INTERNXT_PASSWORD" = "$INTERNXT_PASSWORD2" ]; then
        break
    fi
    warn "Passwords don't match. Try again."
done

read -rp "TOTP secret (leave empty if no 2FA): " INTERNXT_TOTP_SECRET

read -rp "Remote name [MyInternxt]: " REMOTE_NAME
REMOTE_NAME="${REMOTE_NAME:-MyInternxt}"

OBSCURED_PASS=$("${INSTALL_DIR}/rclone" obscure "${INTERNXT_PASSWORD}")

{
    echo "[${REMOTE_NAME}]"
    echo "type = internxt"
    echo "email = ${INTERNXT_EMAIL}"
    echo "pass = ${OBSCURED_PASS}"
    if [ -n "${INTERNXT_TOTP_SECRET}" ]; then
        echo "totp_secret = ${INTERNXT_TOTP_SECRET}"
    fi
} > "${CONFIG_DIR}/rclone.conf"

chmod 600 "${CONFIG_DIR}/rclone.conf"
ok "rclone.conf saved to ${CONFIG_DIR}/rclone.conf"

cat > "${CONFIG_DIR}/mount.env" <<ENVEOF
REMOTE_NAME=${REMOTE_NAME}
MOUNT_POINT=${MOUNT_POINT}
CACHE_DIR=${CACHE_DIR}
RCLONE_BIN=${INSTALL_DIR}/rclone
CONFIG_FILE=${CONFIG_DIR}/rclone.conf
RCLONE_VFS_CACHE_MAX_SIZE=8G
RCLONE_VFS_CACHE_MAX_AGE=48h
RCLONE_BUFFER_SIZE=64M
RCLONE_READ_AHEAD=128M
RCLONE_VFS_CACHE_POLL_INTERVAL=30s
RCLONE_DIR_CACHE_TIME=5m
RCLONE_TRANSFERS=2
RCLONE_CHECKERS=4
RCLONE_RETRIES=5
RCLONE_LOW_LEVEL_RETRIES=10
RCLONE_TIMEOUT=120s
RCLONE_CONTIMEOUT=30s
ENVEOF
ok "mount.env saved to ${CONFIG_DIR}/mount.env"

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Immich rclone FUSE mount (Internxt)
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
NotifyAccess=all
EnvironmentFile=${CONFIG_DIR}/mount.env
ExecStartPre=${INSTALL_DIR}/rclone-fuse-cleanup.sh
ExecStart=${INSTALL_DIR}/rclone-fuse-mount.sh
ExecStop=${INSTALL_DIR}/rclone-fuse-cleanup.sh
Restart=on-failure
RestartSec=10

LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
ok "systemd service installed: ${SERVICE_NAME}.service"

cat > "${INSTALL_DIR}/rclone-fuse-mount.sh" <<'MOUNTEOF'
#!/usr/bin/env bash
set -euo pipefail

source /etc/immich-rclone/mount.env

if mountpoint -q "${MOUNT_POINT}" 2>/dev/null; then
    echo "[rclone-mount] ${MOUNT_POINT} is already mounted — skipping"
    exit 0
fi

mkdir -p "${MOUNT_POINT}" "${CACHE_DIR}"

exec "${RCLONE_BIN}" mount \
    "${REMOTE_NAME}:" \
    "${MOUNT_POINT}" \
    --config "${CONFIG_FILE}" \
    --vfs-cache-mode full \
    --vfs-cache-max-size "${RCLONE_VFS_CACHE_MAX_SIZE}" \
    --vfs-cache-max-age "${RCLONE_VFS_CACHE_MAX_AGE}" \
    --cache-dir "${CACHE_DIR}" \
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
    --no-checksum \
    --allow-other \
    --log-level INFO
MOUNTEOF

cat > "${INSTALL_DIR}/rclone-fuse-cleanup.sh" <<'CLEANUPEOF'
#!/usr/bin/env bash
set -euo pipefail

source /etc/immich-rclone/mount.env

if mountpoint -q "${MOUNT_POINT}" 2>/dev/null; then
    echo "[rclone-cleanup] Unmounting ${MOUNT_POINT}..."
    fusermount -uz "${MOUNT_POINT}" 2>/dev/null || true
    sleep 1
    if mountpoint -q "${MOUNT_POINT}" 2>/dev/null; then
        umount -l "${MOUNT_POINT}" 2>/dev/null || true
        sleep 1
    fi
    if mountpoint -q "${MOUNT_POINT}" 2>/dev/null; then
        echo "[rclone-cleanup] WARNING: ${MOUNT_POINT} still mounted after cleanup"
        exit 1
    fi
    echo "[rclone-cleanup] Done"
fi
CLEANUPEOF

chmod +x "${INSTALL_DIR}/rclone-fuse-mount.sh" "${INSTALL_DIR}/rclone-fuse-cleanup.sh"
ok "Helper scripts installed"

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
ok "Service enabled (starts on boot)"

info "Starting mount..."
systemctl start "${SERVICE_NAME}"

sleep 3

if systemctl is-active --quiet "${SERVICE_NAME}"; then
    ok "rclone service is running!"
else
    warn "Service not running yet — Internxt 2FA login can take 30-60s"
    info "Check status:  systemctl status ${SERVICE_NAME}"
    info "Watch logs:    journalctl -u ${SERVICE_NAME} -f"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                   Installation Complete!                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Mount point:   ${MOUNT_POINT}"
echo "  Config:        ${CONFIG_DIR}/rclone.conf"
echo "  Service:       systemctl status ${SERVICE_NAME}"
echo "  Logs:          journalctl -u ${SERVICE_NAME} -f"
echo ""
echo "  Next steps:"
echo "  1. Wait for the mount to be ready (check with: ls ${MOUNT_POINT})"
echo "  2. Deploy the Docker Compose stack from Coolify"
echo "  3. In Immich, add External Library → /mnt/external-library"
echo ""
echo "  Useful commands:"
echo "    sudo systemctl start ${SERVICE_NAME}     # start mount"
echo "    sudo systemctl stop ${SERVICE_NAME}      # stop mount"
echo "    sudo systemctl restart ${SERVICE_NAME}   # restart mount"
echo "    journalctl -u ${SERVICE_NAME} -f         # live logs"
echo "    du -sh ${CACHE_DIR}                      # check cache size"
echo ""
