<div align="center">

# Immich + Internxt on Coolify

**Self-hosted photo management backed by Internxt's encrypted cloud storage.**

[![GitHub](https://img.shields.io/badge/repo-thies2005%2Fimmich--rclone--coolify-181717?logo=github)](https://github.com/thies2005/immich-rclone-coolify)
[![Coolify](https://img.shields.io/badge/deploy-Coolify-blue)](https://coolify.io)
[![Immich](https://img.shields.io/badge/Immich-v2-4250af?logo=immich)](https://immich.app)
[![Internxt](https://img.shields.io/badge/Internxt-E2E%20encrypted-0066ff)](https://internxt.com)
[![rclone](https://img.shields.io/badge/rclone-custom%20fork-orange?logo=rclone)](https://github.com/thies2005/rclone)

A production-ready Docker Compose stack that runs **Immich** with an **Internxt** remote mounted as an external library via a custom **rclone** fork with automatic 2FA re-authentication. Designed to deploy on a **50 GB** Coolify host.

**Two steps: run one install script on the host, then deploy in Coolify.**

</div>

---

## Architecture

```
  Your browser ──▶ Immich (Docker) ──▶ Host FUSE mount ──▶ Internxt Cloud
      (photos)       (Coolify)         (rclone on host)     (encrypted)
```

rclone runs directly on the host as a **systemd service**. Docker containers access the files through a simple bind mount. No mount propagation tricks, no privileged containers.

```
┌─────────────────────────────────────────────────────┐
│  Host (Linux)                                        │
│                                                      │
│  ┌──────────────────────────────────────────────┐    │
│  │  rclone systemd service (immich-rclone)       │    │
│  │  FUSE mount → /mnt/immich-external-library    │    │
│  │  Config: /etc/immich-rclone/rclone.conf       │    │
│  │  Cache:  /var/cache/immich-rclone/             │    │
│  └──────────────────────┬───────────────────────┘    │
│                         │ bind mount (ro)            │
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

## Why Host-Based rclone?

Running rclone inside Docker caused **mount propagation failures** — the FUSE mount was invisible to other containers. This happens when the Docker host is itself a container (LXC, Proxmox, etc.). Running rclone directly on the host eliminates the problem entirely.

| | Docker rclone | Host rclone (this branch) |
|---|---|---|
| Mount propagation | Broken on nested containers | Works everywhere |
| Privileged containers | Required | Not needed |
| Cache duplication | Risk of duplicate caches | Single cache |
| Setup complexity | All in Coolify | One script + Coolify |
| Boot persistence | Depends on Docker restart | systemd (always first) |

## Quick Start

### Step 1: Run the install script on your host

```bash
# SSH into your server (one-time), then:
sudo bash install.sh
```

The script will:
- Install build dependencies (git, golang, fuse3)
- Compile the custom rclone fork with Internxt + 2FA support
- Ask for your Internxt credentials (email, password, TOTP secret)
- Create a systemd service that auto-starts on boot
- Start the mount immediately

Takes about 5-10 minutes (Go compilation).

### Step 2: Deploy in Coolify

**New Resource → Docker Compose (from GitHub)** → select `thies2005/immich-rclone-coolify`

Set this env var in Coolify:
```
DB_PASSWORD=a-strong-random-password
```

Click **Deploy**.

### Step 3: Add External Library in Immich

- Open Immich, create admin account
- **Administration → External Libraries → Create Library**
- Path: `/mnt/external-library` → **Scan**

First scan is slow (2-4 hours for 10k photos) — every file downloads and decrypts through E2E. Subsequent scans are fast.

## 50 GB Storage Budget

| Component | Path | Allocation |
|---|---|---|
| rclone VFS cache | `/var/cache/immich-rclone/` | **8 GB** (hard cap) |
| Immich uploads | `upload_data` | ~4 GB |
| ML model cache | `ml_cache` | ~3 GB |
| PostgreSQL | `postgres_data` | ~2 GB |
| Redis | `redis_data` | <100 MB |
| Docker + OS | *(Docker root)* | ~5 GB |
| External library | *(FUSE mount)* | **0 GB** — Internxt |
| **Headroom** | | **~28 GB** |

## Useful Commands

```bash
# rclone service
sudo systemctl status immich-rclone    # check status
sudo systemctl restart immich-rclone   # restart mount
journalctl -u immich-rclone -f         # live logs
du -sh /var/cache/immich-rclone        # check cache size

# Update Internxt credentials
sudo nano /etc/immich-rclone/rclone.conf
sudo systemctl restart immich-rclone

# Change rclone settings (cache size, etc.)
sudo nano /etc/immich-rclone/mount.env
sudo systemctl restart immich-rclone
```

## Files

| File | Description |
|---|---|
| `install.sh` | **Run this first** — builds rclone, creates config, sets up systemd |
| `docker-compose.yml` | Coolify deployment (Immich + Postgres + Redis) |
| [`COOLIFY-SETUP.md`](COOLIFY-SETUP.md) | Detailed Coolify setup and troubleshooting |
| [`ENV-VARIABLES.md`](ENV-VARIABLES.md) | All environment variables |

## Built With

- [Immich](https://immich.app) — self-hosted Google Photos alternative
- [Internxt](https://internxt.com) — zero-knowledge encrypted cloud storage
- [rclone](https://rclone.org) — cloud storage Swiss army knife (custom [fork](https://github.com/thies2005/rclone) with TOTP 2FA)
- [Coolify](https://coolify.io) — open-source PaaS

## License

MIT
