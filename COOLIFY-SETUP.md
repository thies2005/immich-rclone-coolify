# Coolify Deployment — Setup Guide

All configuration happens through Coolify's UI. No SSH into the host, no manual file creation, no `.env` files.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Docker (managed by Coolify)                                 │
│                                                              │
│  ┌────────────┐   bind mount :shared   ┌──────────────────┐ │
│  │  rclone     │───────────────────────│  FUSE mount point │ │
│  │  (FUSE)     │                       │  (auto-created)   │ │
│  └─────┬───────┘                       └────────┬─────────┘ │
│        │        bind mount :ro,slave             │           │
│  ┌─────▼────────────────────────────────────────▼─────────┐ │
│  │  immich-server  +  immich-microservices                │ │
│  └───────────────────────────────────────────────────────┘ │
│                                                             │
│  Named volumes (Docker-managed, no host paths needed):      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐  │
│  │ postgres │ │  redis   │ │ uploads  │ │ ml_cache     │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────────┘  │
│  ┌──────────────┐ ┌──────────────┐                          │
│  │ rclone_cache │ │rclone_config │  ← auto-generated from   │
│  └──────────────┘ └──────────────┘     env vars             │
└──────────────────────────────────────────────────────────────┘
         │
         │  E2E-encrypted API (auto-2FA via totp_secret)
         ▼
   Internxt Cloud
```

All storage uses Docker **named volumes** except the FUSE mount point, which uses a bind mount (Docker auto-creates the directory). The `rclone.conf` file is auto-generated from environment variables on every container start. The `immich-microservices` service handles background jobs, library scanning, and database migrations — it must start before `immich-server`.

---

## Step 1: Add to Coolify

1. In the Coolify UI, go to **Project → New Resource → Docker Compose (from GitHub)**.
2. Select this repository: `thies2005/immich-rclone-coolify`
3. The `docker-compose.yml` is at the repo root — no base directory change needed.
4. Coolify will build the custom rclone image from the fork during first deploy.

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
2. The first deployment takes 5–10 minutes (rclone compiles from Go source).
3. Watch the logs:
    - **rclone**: Should show `Generating rclone.conf`, then `Starting rclone mount`
    - **immich-microservices**: Starts after rclone passes healthchecks, runs DB migrations
    - **immich-server**: Starts after microservices passes healthchecks (up to 120 seconds after microservices)

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

## How rclone.conf Is Generated

The entrypoint script auto-generates `/config/rclone/rclone.conf` from environment variables on every container start:

```ini
[MyInternxt]
type = internxt
email = you@domain.com
pass = <obscured by rclone>
totp_secret = JBSWY3DPEHPK3PXP
```

This means:
- **No manual rclone config** — just set env vars in Coolify
- **Credential changes** — update env vars in Coolify UI, redeploy
- **Config persists** in the `rclone_config` named volume between restarts, but is regenerated on each start from env vars

---

## How Volumes Work

| Volume | Type | Purpose |
|---|---|---|
| `rclone_config` | Named | Auto-generated `rclone.conf` |
| `rclone_cache` | Named | VFS cache (hard-capped at 8G) |
| `upload_data` | Named | Immich user uploads |
| `ml_cache` | Named | ML model cache |
| `postgres_data` | Named | Database |
| `redis_data` | Named | Job queue |
| `/mnt/immich-external-library` | Bind mount | FUSE mount point (auto-created) |

Only the FUSE mount point uses a host bind mount (required for mount propagation between containers). Docker creates this directory automatically — no manual creation needed.

---

## Troubleshooting

### rclone container exits immediately

```bash
docker logs immich-rclone 2>&1 | tail -30
```

Common causes:
- **`INTERNXT_EMAIL must be set`**: Missing required variable in Coolify UI.
- **`/dev/fuse not found`**: FUSE kernel module not available. Extremely rare on modern Linux — run `modprobe fuse` on the host.
- **Authentication failure**: Verify `INTERNXT_EMAIL`, `INTERNXT_PASSWORD`, and `INTERNXT_TOTP_SECRET` are correct.

### rclone healthcheck fails

- Internxt auth with 2FA can take 30–60s. The 90s `start_period` handles this.
- Verify Internxt credentials are correct.
- Check logs: `docker logs immich-rclone -f`
- Empty remotes now pass the default healthcheck. Set `RCLONE_HEALTHCHECK_REQUIRE_CONTENTS=true` only if you want startup to fail on an empty library.

### FUSE mount not visible to Immich

- The `:shared` / `:slave` propagation is essential — don't remove from compose file.
- Verify on the host: `mountpoint /mnt/immich-external-library && ls /mnt/immich-external-library`

### Cache filling up disk

```bash
docker exec immich-rclone du -sh /cache/vfs
```

- Hard-capped at `RCLONE_VFS_CACHE_MAX_SIZE` (default 8G).
- Reduce to `4G` if needed. Set shorter `RCLONE_VFS_CACHE_MAX_AGE` (e.g. `12h`).

### Slow scans

- **First scan is always slow** — E2E encryption requires full file download before reading.
- Increase `RCLONE_DIR_CACHE_TIME` to `30m` to reduce API calls.
- Keep `RCLONE_TRANSFERS` at `2` — higher values trigger rate limits.
- Subsequent scans are fast (only changed files re-downloaded).

### Rebuilding after fork changes

- **Redeploy** with **Force Rebuild** in Coolify UI.
- To use a different fork branch, set `RCLONE_BRANCH` in the environment variables.
