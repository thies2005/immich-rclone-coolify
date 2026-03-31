<div align="center">

# Immich + Internxt on Coolify

**Self-hosted photo management backed by Internxt's encrypted cloud storage.**

[![GitHub](https://img.shields.io/badge/repo-thies2005%2Fimmich--rclone--coolify-181717?logo=github)](https://github.com/thies2005/immich-rclone-coolify)
[![Coolify](https://img.shields.io/badge/deploy-Coolify-blue)](https://coolify.io)
[![Immich](https://img.shields.io/badge/Immich-v2-4250af?logo=immich)](https://immich.app)
[![Internxt](https://img.shields.io/badge/Internxt-E2E%20encrypted-0066ff)](https://internxt.com)
[![rclone](https://img.shields.io/badge/rclone-custom%20fork-orange?logo=rclone)](https://github.com/thies2005/rclone)

</div>

---

## What This Does

Runs [Immich](https://immich.app) (self-hosted Google Photos alternative) on your server with your [Internxt](https://internxt.com) cloud storage mounted as an external library. Your photos live encrypted in Internxt's cloud, but you browse and search them through Immich's web UI.

Uses a [custom rclone fork](https://github.com/thies2005/rclone) with automatic TOTP 2FA support for Internxt.

## Architecture

```
  Your browser ──> Immich (Docker) ──> Host FUSE mount ──> Internxt Cloud
      (photos)       (Coolify)         (rclone on host)     (encrypted)
```

rclone runs on the **host** as a systemd service. Docker containers access the files through a bind mount. No privileged containers, no mount propagation hacks.

```
┌─────────────────────────────────────────────────────┐
│  Host (Linux)                                        │
│                                                      │
│  ┌──────────────────────────────────────────────┐    │
│  │  rclone systemd service (immich-rclone)       │    │
│  │  FUSE mount -> /mnt/immich-external-library   │    │
│  │  Config: /etc/immich-rclone/rclone.conf       │    │
│  │  Cache:  /var/cache/immich-rclone/            │    │
│  └──────────────────────┬───────────────────────┘    │
│                         │ bind mount (read-only)     │
│  ┌──────────────────────▼───────────────────────┐    │
│  │  Docker (managed by Coolify)                  │    │
│  │                                                │    │
│  │  ┌──────────────┐  ┌─────────────────────┐   │    │
│  │  │ immich-server│  │ immich-microservices│   │    │
│  │  │ (API + UI)  │  │ (jobs + migrations) │   │    │
│  │  └──────────────┘  └─────────────────────┘   │    │
│  │  ┌──────────────┐  ┌─────┐  ┌───────────┐   │    │
│  │  │ machine-learn│  │ pg  │  │  redis    │   │    │
│  │  └──────────────┘  └─────┘  └───────────┘   │    │
│  └────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
         │
         │  E2E-encrypted API (auto-2FA via TOTP)
         ▼
   Internxt Cloud Storage
```

## Prerequisites

- A **Linux server** with Docker and [Coolify](https://coolify.io) installed
- At least **50 GB disk** (32 GB for rclone cache, rest for Immich)
- SSH access to the server (one-time, to run the install script)
- An **Internxt** account (with or without 2FA)

## Step-by-Step Setup

### Step 1: Download the install script

SSH into your server and clone the repo (or just download `install.sh`):

```bash
git clone -b host-rclone https://github.com/thies2005/immich-rclone-coolify.git
cd immich-rclone-coolify
```

### Step 2: Run the install script

```bash
sudo bash install.sh
```

The script will walk you through everything:

1. **Installs dependencies** — `git`, `golang`, `fuse3` (via apt, dnf, or yum)
2. **Checks FUSE** — verifies `/dev/fuse` exists, tries `modprobe fuse` if not
3. **Compiles rclone** — clones the custom fork and builds it (3-8 minutes)
4. **Asks for your Internxt credentials:**
   - **Email** — your Internxt login email
   - **Password** — your Internxt password (typed twice for confirmation)
   - **TOTP secret** — only if your account has 2FA enabled (see below)
   - **Remote name** — just press Enter for the default (`MyInternxt`)
5. **Creates files on your host:**

   | File | Purpose |
   |---|---|
   | `/opt/immich-rclone/rclone` | The compiled rclone binary |
   | `/opt/immich-rclone/rclone-fuse-mount.sh` | Mount script used by systemd |
   | `/opt/immich-rclone/rclone-fuse-cleanup.sh` | Unmount script for clean shutdown |
   | `/etc/immich-rclone/rclone.conf` | Your Internxt credentials (obscured password) |
   | `/etc/immich-rclone/mount.env` | rclone settings (cache size, timeouts, etc.) |
   | `/etc/systemd/system/immich-rclone.service` | systemd unit file |
   | `/etc/logrotate.d/immich-rclone` | Log rotation config |

6. **Starts the mount** and waits up to 60 seconds for it to become ready

> **Getting your TOTP secret:** When you originally set up 2FA on your Internxt account, you scanned a QR code. That QR code contains a `secret=` parameter in base32 (e.g. `JBSWY3DPEHPK3PXP`). That is your TOTP secret. It is NOT a one-time code from your authenticator app. If you lost it, disable and re-enable 2FA on your Internxt account to get a new one.

### Step 3: Verify the mount

```bash
ls /mnt/immich-external-library
```

You should see your Internxt files and folders listed. If you see files, the mount is working. If the directory is empty, check the logs:

```bash
journalctl -u immich-rclone -f
tail -f /var/log/immich-rclone/rclone.log
```

### Step 4: Add the stack to Coolify

1. Open your **Coolify UI**
2. Go to **Project -> New Resource -> Docker Compose (from GitHub)**
3. Select repository: **`thies2005/immich-rclone-coolify`**
4. Set the branch to **`host-rclone`**
5. The `docker-compose.yml` is at the repo root -- no base directory change needed

### Step 5: Set the database password

In the Coolify resource settings, add this **required** environment variable:

```
DB_PASSWORD=a-strong-random-password
```

Generate a strong password, e.g. `openssl rand -hex 24`.

That's the only variable you must set. Everything else has working defaults. See [`ENV-VARIABLES.md`](ENV-VARIABLES.md) for the full list.

### Step 6: Configure the reverse proxy

1. In the Coolify UI, under the **immich-server** service settings
2. Set the **Domains** field to your URL (e.g. `https://photos.example.com`)
3. Coolify will auto-generate Traefik labels and route traffic to port 2283

### Step 7: Deploy

1. Click **Deploy** in Coolify
2. First deploy takes 1-2 minutes (pulling Docker images)
3. Watch the container logs in Coolify:
   - **immich-microservices** starts first -- runs database migrations
   - **immich-server** starts after microservices passes healthchecks
   - **immich-machine-learning** starts in parallel

### Step 8: Create your admin account

1. Open your domain (e.g. `https://photos.example.com`) in a browser
2. Create the admin account with your email and a password

### Step 9: Add the External Library

1. Log in to Immich
2. Go to **Administration** (left sidebar) -> **External Libraries**
3. Click **Create Library**
4. Set the **Import Path** to exactly: `/mnt/external-library`
5. Click **Save**
6. Click the **Scan** button on the new library

### Step 10: Wait for the first scan

The first scan downloads every file from Internxt and decrypts it through E2E encryption. This is slow:

| Library size | Expected time |
|---|---|
| 1,000 photos | ~15-30 minutes |
| 10,000 photos | ~2-4 hours |
| 50,000 photos | ~8-16 hours |

You can watch progress in Immich under **Administration -> Jobs**. Subsequent scans are fast -- only new or changed files are re-downloaded.

---

## What Gets Installed on the Host

The install script creates a systemd service called `immich-rclone` that:

- **Auto-starts on boot** before Docker (`After=network-online.target`)
- **Mounts your Internxt storage** to `/mnt/immich-external-library`
- **Auto-restarts** on failure with 15-second backoff
- **Cleans up** stale mounts before each start
- **Logs** to both systemd journal and `/var/log/immich-rclone/rclone.log`

```
/opt/immich-rclone/
├── rclone                      # compiled binary
├── rclone-fuse-mount.sh        # mount script (systemd ExecStart)
└── rclone-fuse-cleanup.sh      # unmount script (systemd ExecStop)

/etc/immich-rclone/
├── rclone.conf                 # Internxt credentials
└── mount.env                   # cache size, timeouts, etc.

/var/cache/immich-rclone/       # VFS cache (max 32 GB)
/var/log/immich-rclone/         # log file (auto-rotated weekly)
/mnt/immich-external-library/   # FUSE mount point (0 local disk)
```

## Disk Usage

| Component | Path | Allocation |
|---|---|---|
| rclone VFS cache | `/var/cache/immich-rclone/` | **32 GB** (hard cap) |
| Immich uploads | `upload_data` | ~4 GB |
| ML model cache | `ml_cache` | ~3 GB |
| PostgreSQL | `postgres_data` | ~2 GB |
| Redis | `redis_data` | <100 MB |
| Docker + OS | *(Docker root)* | ~5 GB |
| External library | *(FUSE mount)* | **0 GB** -- Internxt |
| **Total** | | **~46 GB** |

> A 50 GB disk leaves very little headroom. If disk is tight, edit
> `RCLONE_VFS_CACHE_MAX_SIZE` in `/etc/immich-rclone/mount.env` to a
> smaller value (e.g. `16G`) and restart the service.

## Useful Commands

### Check status

```bash
sudo systemctl status immich-rclone     # service status
ls /mnt/immich-external-library         # verify mount has files
du -sh /var/cache/immich-rclone         # check cache size
```

### View logs

```bash
journalctl -u immich-rclone -f          # live systemd logs
tail -f /var/log/immich-rclone/rclone.log  # rclone's own log
```

### Restart the mount

```bash
sudo systemctl restart immich-rclone
```

### Change Internxt credentials

```bash
sudo nano /etc/immich-rclone/rclone.conf
sudo systemctl restart immich-rclone
```

Or re-run `sudo bash install.sh` -- it will ask for new credentials.

### Change rclone settings (cache size, timeouts)

```bash
sudo nano /etc/immich-rclone/mount.env
sudo systemctl restart immich-rclone
```

See [`ENV-VARIABLES.md`](ENV-VARIABLES.md) for all available settings.

### Update rclone to latest fork version

Re-running the install script rebuilds rclone from the latest source and restarts the service. Existing credentials are preserved:

```bash
sudo bash install.sh
```

### Full uninstall

```bash
sudo systemctl stop immich-rclone
sudo systemctl disable immich-rclone
sudo rm /etc/systemd/system/immich-rclone.service
sudo rm -rf /opt/immich-rclone /etc/immich-rclone /var/cache/immich-rclone /var/log/immich-rclone
sudo systemctl daemon-reload
```

## Troubleshooting

### Mount not visible in Docker containers

Check the host first:

```bash
ls /mnt/immich-external-library
```

If empty or missing, the host service isn't ready:

```bash
sudo systemctl status immich-rclone
journalctl -u immich-rclone -f
```

If the host mount has files but containers don't see them, restart the Coolify deployment.

### rclone service won't start

- Verify credentials: `sudo cat /etc/immich-rclone/rclone.conf`
- Check for auth errors: `journalctl -u immich-rclone -f`
- 2FA login can take 30-60 seconds on first start

### Cache filling up disk

```bash
du -sh /var/cache/immich-rclone
```

The cache is hard-capped at `RCLONE_VFS_CACHE_MAX_SIZE` (default 32G). To reduce:

```bash
sudo nano /etc/immich-rclone/mount.env
# Change RCLONE_VFS_CACHE_MAX_SIZE=16G
sudo systemctl restart immich-rclone
```

### Slow first scan

This is expected. Internxt uses end-to-end encryption -- every file must be fully downloaded and decrypted before Immich can read it. Subsequent scans only process new or changed files and are fast.

## Files

| File | Description |
|---|---|
| `install.sh` | **Run this first** -- builds rclone, creates config, sets up systemd |
| `docker-compose.yml` | Coolify deployment (Immich + Postgres + Redis) |
| [`COOLIFY-SETUP.md`](COOLIFY-SETUP.md) | Coolify-specific setup details |
| [`ENV-VARIABLES.md`](ENV-VARIABLES.md) | All environment variables |

## Built With

- [Immich](https://immich.app) -- self-hosted Google Photos alternative
- [Internxt](https://internxt.com) -- zero-knowledge encrypted cloud storage
- [rclone](https://rclone.org) -- cloud storage Swiss army knife (custom [fork](https://github.com/thies2005/rclone) with TOTP 2FA)
- [Coolify](https://coolify.io) -- open-source PaaS

## License

MIT
