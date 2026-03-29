# Coolify Deployment — Setup Guide

Step-by-step instructions for deploying Immich with an Internxt rclone external library on a Coolify host.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│  Coolify Host                                                       │
│                                                                     │
│  ┌──────────────┐  host bind mount   ┌──────────────────────────┐  │
│  │   rclone      │───────────────────│ /data/.../external-library│  │
│  │   (FUSE)      │  :rshared         │  (FUSE mount point)      │  │
│  └──────┬────────┘                   └───────────┬──────────────┘  │
│         │                                        │                  │
│         │  host bind mount (:ro,rslave)          │                  │
│  ┌──────▼────────────────────────────────────────▼──────────────┐  │
│  │  immich-server  (reads external library read-only)           │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  Separate host paths (isolated):                                    │
│  ┌─────────────────┐  ┌─────────────┐  ┌───────────────────────┐  │
│  │  immich-ml       │  │ redis       │  │  postgres             │  │
│  └─────────────────┘  └─────────────┘  └───────────────────────┘  │
│                                                                     │
│  /data/coolify/immich/rclone-config  → rclone.conf (host-managed)  │
│  /data/coolify/immich/rclone-cache   → VFS cache (isolated)       │
│  /data/coolify/immich/upload         → Immich uploads (isolated)   │
└─────────────────────────────────────────────────────────────────────┘
         │
         │  E2E-encrypted API (this fork auto-handles 2FA via totp_secret)
         ▼
   Internxt Cloud
```

---

## Step 1: Host Preparation (one-time)

SSH into your Coolify host and run:

```bash
# 1. Install fuse3 (required for FUSE mounts)
apt update && apt install -y fuse3

# 2. Verify /dev/fuse exists
ls -la /dev/fuse
# Expected: crw-rw-rw- 1 root root 10, 229 ... /dev/fuse

# 3. Enable user_allow_other in /etc/fuse.conf
sed -i 's/^#user_allow_other/user_allow_other/' /etc/fuse.conf
grep user_allow_other /etc/fuse.conf
```

### Create host directories

```bash
BASE="/data/coolify/immich"

mkdir -p "$BASE/external-library"   # FUSE mount point (must be empty dir)
mkdir -p "$BASE/rclone-config"      # rclone.conf lives here
mkdir -p "$BASE/rclone-cache"       # VFS cache (physically isolated)
mkdir -p "$BASE/upload"             # Immich uploads
mkdir -p "$BASE/postgres"           # PostgreSQL data
mkdir -p "$BASE/ml-cache"           # ML model cache
mkdir -p "$BASE/redis"              # Redis data

# Verify the mount-point directory is empty (rclone refuses to mount over files)
ls -la "$BASE/external-library"
```

---

## Step 2: Configure the Internxt Remote

This fork includes automatic Internxt 2FA handling. The `totp_secret` field in `rclone.conf` allows rclone to generate valid TOTP codes automatically during authentication — no manual 2FA prompt.

### Option A: Interactive config via Docker

```bash
BASE="/data/coolify/immich"

docker run --rm -it \
  -v "$BASE/rclone-config:/config/rclone" \
  -e XDG_CONFIG_HOME=/config \
  rclone/rclone:latest \
  rclone config
```

Follow the prompts:
1. Select **n** (new remote)
2. Name it (e.g. `MyInternxt`)
3. Select storage type: **internxt**
4. Enter your Internxt email and password
5. If your account has 2FA enabled, enter your **TOTP secret** (the base32 key from your authenticator app — NOT a one-time code). This fork stores it as `totp_secret` and generates valid codes automatically on every reconnect.
6. Confirm and exit

### Option B: Manual rclone.conf

Create `/data/coolify/immich/rclone-config/rclone.conf`:

```ini
[MyInternxt]
type = internxt
email = your-email@example.com
password = your-internxt-password
totp_secret = JBSWY3DPEHPK3PXP
```

> **Where to get `totp_secret`:** When you originally set up 2FA on your Internxt account, you scanned a QR code with an authenticator app. That QR code encodes a `secret=` parameter in base32. That value is your `totp_secret`. If you no longer have it, you must disable and re-enable 2FA on your Internxt account to get a new secret.

### Verify the remote works

```bash
docker run --rm -it \
  -v "$BASE/rclone-config:/config/rclone" \
  -e XDG_CONFIG_HOME=/config \
  rclone/rclone:latest \
  rclone lsd MyInternxt:
```

You should see your Internxt root directory listing.

---

## Step 3: Add to Coolify

1. In the Coolify UI, go to **Project → New Resource → Docker Compose (from GitHub)**.
2. Select this repository: `https://github.com/thies2005/immich-rclone-coolify`
3. The `docker-compose.yml` is at the repo root — no base directory change needed.
4. Coolify will build the custom rclone image from the fork during first deploy.

---

## Step 4: Configure Environment Variables in Coolify

In the Coolify resource settings, add all **Required** environment variables from `ENV-VARIABLES.md`. At minimum:

| Variable | Example Value |
|---|---|
| `RCLONE_REMOTE_SOURCE` | `MyInternxt:` |
| `RCLONE_HOST_CONFIG_PATH` | `/data/coolify/immich/rclone-config` |
| `RCLONE_HOST_MOUNT_PATH` | `/data/coolify/immich/external-library` |
| `RCLONE_HOST_CACHE_PATH` | `/data/coolify/immich/rclone-cache` |
| `RCLONE_VFS_CACHE_MAX_SIZE` | `8G` |
| `UPLOAD_HOST_PATH` | `/data/coolify/immich/upload` |
| `DB_HOST_PATH` | `/data/coolify/immich/postgres` |
| `ML_CACHE_HOST_PATH` | `/data/coolify/immich/ml-cache` |
| `REDIS_HOST_PATH` | `/data/coolify/immich/redis` |
| `DB_PASSWORD` | *(a strong random password)* |

See `ENV-VARIABLES.md` for the complete list including optional tuning parameters.

### Configure Coolify Reverse Proxy

1. In the Coolify UI, under the **immich-server** service, set the **Domains** field to your desired URL (e.g. `https://photos.example.com`).
2. Coolify automatically generates Traefik labels and routes traffic to port `2283`.
3. Ensure the **IMMICH_HTTP_PORT** variable is not conflicting with other services, or leave it at the default `2283`.

---

## Step 5: Deploy

1. Click **Deploy** in the Coolify UI.
2. The first deployment takes 5–10 minutes because the rclone image is built from source (clones the fork, compiles Go).
3. Watch the logs for each service:
   - **rclone**: Should show `Starting rclone mount` and eventually pass healthchecks
   - **immich-server**: Depends on rclone being healthy, so it starts after rclone passes healthchecks (up to 90 seconds)

---

## Step 6: Post-Deployment — Immich Setup

### Create Admin Account

Open `https://photos.example.com` (or your configured domain) and create the admin account.

### Register the External Library

1. Log in as admin.
2. Go to **Administration → External Libraries**.
3. Click **Create Library**.
4. Name it (e.g. "Internxt Photos").
5. Set the **Import Path** to `/mnt/external-library` (the in-container path).
6. Save.
7. Click **Scan** to start indexing.

> **First scan is slow.** Every file must be downloaded from Internxt, decrypted through E2E, and written to the VFS cache before Immich can read its metadata. A library of 10,000 photos may take 2–4 hours on first scan. Subsequent scans are much faster due to rclone's directory cache.

---

## Troubleshooting

### rclone container exits immediately

```bash
docker logs immich-rclone 2>&1 | tail -30
```

Common causes:
- **`/dev/fuse not found`**: FUSE kernel module not loaded. Run `modprobe fuse` on the host.
- **`RCLONE_VFS_CACHE_MAX_SIZE must be set`**: Missing required variable in Coolify UI.
- **`permission denied` on cache dir**: Check that the host path is writable (`chmod 777 /data/coolify/immich/rclone-cache`).
- **Authentication failure**: Verify `rclone.conf` has correct email, password, and `totp_secret`.

### rclone healthcheck fails (mount is empty)

- Internxt authentication with 2FA can take 30–60 seconds on first connect. The 90-second `start_period` accounts for this, but very slow connections may need more.
- Verify the remote is accessible from the host:
  ```bash
  docker exec immich-rclone rclone lsd ${RCLONE_REMOTE_SOURCE}
  ```
- If the remote name doesn't match `rclone.conf`, update `RCLONE_REMOTE_SOURCE`.

### FUSE mount not visible to Immich

- Ensure the same `RCLONE_HOST_MOUNT_PATH` is used for both the `rclone` and `immich-server` services.
- The `:rshared` propagation on rclone and `:ro,rslave` on immich-server are essential — do not remove them.
- Verify on the host:
  ```bash
  mountpoint /data/coolify/immich/external-library
  ls /data/coolify/immich/external-library
  ```
  If `mountpoint` returns `is a mountpoint`, the FUSE mount is active on the host and should be visible to Immich.

### Cache filling up disk

```bash
du -sh /data/coolify/immich/rclone-cache
```

- The cache is hard-capped by `RCLONE_VFS_CACHE_MAX_SIZE` (default 8G). Rclone evicts old files when the limit is reached.
- If disk usage exceeds the budget, reduce `RCLONE_VFS_CACHE_MAX_SIZE` to `4G`.
- Set `RCLONE_VFS_CACHE_MAX_AGE` to a shorter duration (e.g. `12h`) to evict files sooner.

### Slow scans / Immich scan timeouts

- **First scan is always slow** — this is expected with E2E encryption. Every file is fully downloaded and decrypted before reading.
- Increase `RCLONE_DIR_CACHE_TIME` to `30m` to reduce repeated directory listings.
- Increase `RCLONE_TIMEOUT` to `300s` for very large files or slow connections.
- Ensure `RCLONE_TRANSFERS` stays at `2` — higher values trigger Internxt rate limits.
- After the first scan completes, subsequent incremental scans are fast (only changed files are re-downloaded).

### Rebuilding after rclone fork changes

- In the Coolify UI, click **Redeploy** with **Force Rebuild** enabled.
- To use a different branch, set `RCLONE_BRANCH` in the Coolify environment variables.

### Checking logs

```bash
# rclone mount activity
docker logs immich-rclone -f

# Immich server
docker logs immich-server -f

# PostgreSQL
docker logs immich-postgres -f
```
