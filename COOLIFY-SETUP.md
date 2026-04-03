# Coolify Deployment — Setup Guide

rclone runs on the host as a systemd service. This guide covers the Coolify (Docker) side.

---

## Prerequisite: Install rclone on the Host

Before deploying in Coolify, SSH into your server once and run:

```bash
sudo bash install.sh
```

This builds rclone, sets up your Internxt credentials, and creates a systemd service that auto-mounts on boot. See the [README](README.md) for details.

Verify the mount is working:

```bash
ls /mnt/immich-external-library
```

If you see your Internxt files, proceed to Coolify setup.

---

## Step 1: Add to Coolify

1. In the Coolify UI, go to **Project → New Resource → Docker Compose (from GitHub)**.
2. Select this repository: `thies2005/immich-rclone-coolify`
3. Use the **`host-rclone`** branch.
4. The `docker-compose.yml` is at the repo root — no base directory change needed.

---

## Step 2: Set Environment Variables

In the Coolify resource settings, add:

| Variable | Value |
|---|---|
| `DB_PASSWORD` | *(a strong random password)* |

That's the only required variable. Everything else has working defaults.

### Machine learning backends (recommended)

Set backend targets only as env vars. Do not hardcode remote hostnames in compose.

| Variable | Example |
|---|---|
| `ML_LB_METHOD` | `round_robin` |
| `ML_BACKEND_1` | `immich-machine-learning:3003` |
| `ML_BACKEND_2` | `192.168.1.50:3003` |
| `ML_BACKEND_3` | `ml-remote.example.internal:3003` |
| `ML_BACKEND_1_WEIGHT` | `2` |
| `ML_BACKEND_2_WEIGHT` | `1` |
| `ML_BACKEND_3_WEIGHT` | `1` |

Notes:
- `ML_BACKEND_1` defaults to `immich-machine-learning:3003`.
- Keep additional backends empty unless used.
- For weighted mode, set `ML_LB_METHOD=weighted`.

### Optional

| Variable | Why change it |
|---|---|
| `IMMICH_VERSION` | Default `v2`. Pin to a specific release (e.g. `v2.1.0`). |
| `DB_USERNAME` | Default `immich`. |
| `DB_DATABASE_NAME` | Default `immich`. |

### Configure reverse proxy

1. Under **immich-server**, set the **Domains** field to your URL (e.g. `https://photos.example.com`).
2. Coolify generates Traefik labels and routes traffic to port `2283`.

---

## Step 3: Deploy

1. Click **Deploy**.
2. First deploy takes 1-2 minutes (just pulling images — no build step).
3. Watch the logs:
   - **immich-microservices**: Runs DB migrations
   - **immich-server**: Starts API + web UI

---

## Step 4: Post-Deploy — Immich Setup

### Create Admin Account

Open your domain and create the admin account.

### Register the External Library

1. Go to **Administration → External Libraries**
2. Click **Create Library**
3. Set the **Import Path** to `/mnt/external-library`
4. Save → Click **Scan**

> **First scan is slow** — every file downloads from Internxt and decrypts through E2E. 10k photos may take 2–4 hours. Subsequent scans are fast.

### Set Machine Learning URL

In Immich **Administration -> Settings -> Machine Learning**, set:

`http://immich-ml-balancer:80`

Use one URL only. Do not configure Immich with multiple ML URLs when using the balancer.

---

## How it Works in Coolify

- `immich-ml-balancer` runs in the same Compose stack and same internal Docker network.
- The balancer is not published publicly (no host ports).
- It load-balances local and remote ML backends from `ML_BACKEND_*` env vars.
- If one backend fails, nginx retries other healthy backends.

---

## Validate After Deploy

From a container terminal in Coolify (for example `immich-server`):

```bash
curl -fsS http://immich-ml-balancer/healthz
curl -fsS http://immich-ml-balancer/ping
```

Expected:
- `/healthz` returns `ok`
- `/ping` returns machine-learning ping response

---

## Troubleshooting

### Mount not visible in containers

Check the host mount first:

```bash
ls /mnt/immich-external-library
```

If empty or missing:

```bash
sudo systemctl status immich-rclone
journalctl -u immich-rclone -f
```

### rclone service won't start

- Check credentials: `sudo cat /etc/immich-rclone/rclone.conf`
- Fix and restart: `sudo systemctl restart immich-rclone`
- Auth issues with 2FA: check `journalctl -u immich-rclone -f`

### Cache filling up disk

```bash
du -sh /var/cache/immich-rclone
```

Edit cache limit:

```bash
sudo nano /etc/immich-rclone/mount.env
# Change RCLONE_VFS_CACHE_MAX_SIZE=4G (for example)
sudo systemctl restart immich-rclone
```

### Slow scans

- **First scan is always slow** — E2E encryption requires full file download.
- Subsequent scans only re-download changed files.
- To tune: edit `/etc/immich-rclone/mount.env` and adjust `RCLONE_DIR_CACHE_TIME`, `RCLONE_TRANSFERS`, etc.

### Update Internxt credentials

```bash
sudo nano /etc/immich-rclone/rclone.conf
sudo systemctl restart immich-rclone
```

Or re-run the install script — it preserves your settings.

### Update rclone to latest fork version

Re-running the install script will rebuild rclone from the latest fork source and restart the service. Existing credentials and settings are preserved:

```bash
sudo bash install.sh
```

The script detects the existing config and skips the credential prompt.
