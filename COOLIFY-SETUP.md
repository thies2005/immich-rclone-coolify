# Coolify Deployment — Setup Guide

All configuration happens through Coolify's UI. No SSH into the host, no manual file creation, no `.env` files.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Docker (managed by Coolify)                                 │
│                                                              │
│  Each immich container runs its own rclone FUSE mount:       │
│                                                              │
│  ┌──────────────────────────────┐  ┌───────────────────────┐ │
│  │  immich-server               │  │  immich-microservices │ │
│  │  ┌─────────────────────────┐ │  │  ┌─────────────────┐  │ │
│  │  │ rclone → /mnt/external- │ │  │  │ rclone → FUSE   │  │ │
│  │  │ library (FUSE mount)    │ │  │  │ mount           │  │ │
│  │  └─────────────────────────┘ │  │  └─────────────────┘  │ │
│  │  ┌─────────────────────────┐ │  │  ┌─────────────────┐  │ │
│  │  │ Immich API (port 2283)  │ │  │  │ Background jobs │  │ │
│  │  └─────────────────────────┘ │  │  │ + DB migrations │  │ │
│  └──────────────────────────────┘  │  └─────────────────┘  │ │
│                                    └───────────────────────┘ │
│                                                              │
│  Named volumes:                                              │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐  │
│  │ postgres │ │  redis   │ │ uploads  │ │ ml_cache     │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────────┘  │
│  ┌──────────────────┐ ┌──────────────────┐ ┌────────────┐  │
│  │rclone_cache_srv  │ │rclone_cache_ms  │ │rclone_conf │  │
│  └──────────────────┘ └──────────────────┘ └────────────┘  │
└──────────────────────────────────────────────────────────────┘
         │
         │  E2E-encrypted API (auto-2FA via totp_secret)
         ▼
   Internxt Cloud
```

rclone is embedded directly inside the immich-server and immich-microservices containers. Each container mounts its own FUSE filesystem — no cross-container mount propagation needed.

---

## Step 1: Add to Coolify

1. In the Coolify UI, go to **Project → New Resource → Docker Compose (from GitHub)**.
2. Select this repository: `thies2005/immich-rclone-coolify`
3. The `docker-compose.yml` is at the repo root — no base directory change needed.
4. Coolify will build custom immich images (with rclone included) during first deploy.

---

## Step 2: Set Environment Variables

In the Coolify resource settings, add these **required** variables:

| Variable | Value |
|---|---|
| `INTERNXT_EMAIL` | `you@domain.com` |
| `INTERNXT_PASSWORD` | `your-internxt-password` |
| `INTERNXT_TOTP_SECRET` | `JBSWY3DPEHPK3PXP` *(only if your account uses 2FA)* |
| `DB_PASSWORD` | *(a strong random password)* |

That's it. Everything else has working defaults.

> **Getting your TOTP secret:** When you set up 2FA on your Internxt account, you scanned a QR code. The `secret=` parameter inside that QR code (a base32 string like `JBSWY3DPEHPK3PXP`) is what goes in `INTERNXT_TOTP_SECRET`. This is NOT a one-time code from your authenticator — it's the permanent secret key. If you lost it, disable and re-enable 2FA on your Internxt account to get a new one.

### Optional tuning

See [`ENV-VARIABLES.md`](ENV-VARIABLES.md) for the full list. Common overrides:

| Variable | Why change it |
|---|---|
| `RCLONE_VFS_CACHE_MAX_SIZE` | Default is `8G`. Reduce to `4G` if disk is tight. |
| `RCLONE_DIR_CACHE_TIME` | Default is `5m`. Increase to `30m` to reduce API calls. |
| `RCLONE_TIMEOUT` | Default is `120s`. Increase to `300s` for slow connections. |

### Configure reverse proxy

1. In the Coolify UI, under the **immich-server** service, set the **Domains** field to your URL (e.g. `https://photos.example.com`).
2. Coolify generates Traefik labels and routes traffic to port `2283`.

---

## Step 3: Deploy

1. Click **Deploy** in the Coolify UI.
2. The first deployment takes 10–15 minutes (rclone compiles from Go source for each immich image).
3. Watch the logs:
   - **immich-microservices**: Should show `[immich-rclone] FUSE mount ready`, then `Running migrations`, then `Immich Microservices is running`
   - **immich-server**: Should show `[immich-rclone] FUSE mount ready`, then `Immich Server is listening`

---

## Step 4: Post-Deploy — Immich Setup

### Create Admin Account

Open your domain (e.g. `https://photos.example.com`) and create the admin account.

### Register the External Library

1. Go to **Administration → External Libraries**
2. Click **Create Library**
3. Set the **Import Path** to `/mnt/external-library`
4. Save → Click **Scan**

> **First scan is slow** — every file downloads from Internxt and decrypts through E2E. 10k photos may take 2–4 hours. This is expected. Subsequent scans are fast.

---

## How It Works

Each immich container (server + microservices) includes rclone and mounts Internxt directly via FUSE. The entrypoint:
1. Generates `rclone.conf` from environment variables
2. Starts `rclone mount` in the background
3. Waits for the FUSE mount to be ready
4. Starts the Immich application

This avoids cross-container mount propagation issues that occur in some Docker environments.

---

## Troubleshooting

### Container fails to start

```bash
docker logs immich-server 2>&1 | tail -30
```

Common causes:
- **`INTERNXT_EMAIL must be set`**: Missing required variable in Coolify UI.
- **`/dev/fuse not found`**: FUSE kernel module not available. Run `modprobe fuse` on the host.
- **Authentication failure**: Verify `INTERNXT_EMAIL`, `INTERNXT_PASSWORD`, and `INTERNXT_TOTP_SECRET` are correct.

### FUSE mount not ready

- Internxt auth with 2FA can take 30–60s. The entrypoint waits up to 60s.
- Verify credentials are correct.
- Check logs for `[immich-rclone]` prefixed messages.

### Cache filling up disk

Each immich container has its own VFS cache volume:
- `rclone_cache_server` for immich-server
- `rclone_cache_microservices` for immich-microservices

Hard-capped at `RCLONE_VFS_CACHE_MAX_SIZE` (default 8G each). Total cache usage can be up to 16G. Reduce to `4G` if needed.

### Slow scans

- **First scan is always slow** — E2E encryption requires full file download before reading.
- Increase `RCLONE_DIR_CACHE_TIME` to `30m` to reduce API calls.
- Keep `RCLONE_TRANSFERS` at `2` — higher values trigger rate limits.
- Subsequent scans are fast (only changed files re-downloaded).

### Rebuilding after fork changes

- **Redeploy** with **Force Rebuild** in Coolify UI.
- To use a different fork branch, set `RCLONE_BRANCH` in the environment variables.
