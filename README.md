<div align="center">

# Immich + Internxt on Coolify

**Self-hosted photo management backed by Internxt's encrypted cloud storage.**

[![GitHub](https://img.shields.io/badge/repo-thies2005%2Fimmich--rclone--coolify-181717?logo=github)](https://github.com/thies2005/immich-rclone-coolify)
[![Coolify](https://img.shields.io/badge/deploy-Coolify-blue)](https://coolify.io)
[![Immich](https://img.shields.io/badge/Immich-release-4250af?logo=immich)](https://immich.app)
[![Internxt](https://img.shields.io/badge/Internxt-E2E%20encrypted-0066ff)](https://internxt.com)
[![rclone](https://img.shields.io/badge/rclone-custom%20fork-orange?logo=rclone)](https://github.com/thies2005/rclone)

A production-ready Docker Compose stack that runs **Immich** with an **Internxt** remote mounted as an external library via a custom **rclone** fork with automatic 2FA re-authentication. Designed to deploy on a **50 GB** Coolify host.

</div>

---

## What This Does

```
  Your browser ──▶ Immich ──▶ rclone FUSE mount ──▶ Internxt Cloud
     (photos)      (server)     (E2E decrypt)        (encrypted)
```

- Mounts your **Internxt** cloud storage as a filesystem inside Docker using a [custom rclone fork](https://github.com/thies2005/rclone) with **automatic TOTP 2FA** support
- Serves the mount to **Immich** as a read-only external library for browsing, searching, and backing up photos
- Keeps **0 bytes** of your Internxt library on local disk (VFS cache only)
- Runs entirely through **Coolify** with no `.env` file needed

## Why This Exists

Internxt uses **client-side end-to-end encryption**. Every file must be fully downloaded and decrypted before it can be read. Standard cloud mounts break because they attempt random seeks on encrypted ciphertext.

This stack forces `--vfs-cache-mode full` (the only mode compatible with E2E) and isolates the cache, uploads, and mount point into separate storage volumes to stay within a strict **50 GB budget**.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Coolify Host (50 GB disk)                                       │
│                                                                  │
│  ┌────────────┐   host bind :rshared   ┌───────────────────┐   │
│  │  rclone     │───────────────────────│ /external-library  │   │
│  │  (FUSE)     │                       │  (mount point)    │   │
│  └─────┬───────┘                       └────────┬──────────┘   │
│        │  host bind :ro,rslave                  │              │
│  ┌─────▼───────────────────────────────────────▼───────────┐   │
│  │  immich-server (API + web)                             │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                                │
│  ┌──────────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │  immich-ml    │  │ redis    │  │ postgres │  │  rclone  │  │
│  │  (AI search)  │  │ (queue)  │  │ (pgvector)│  │  cache   │  │
│  └──────────────┘  └──────────┘  └──────────┘  └──────────┘  │
│       ~3 GB          <100 MB       ~2 GB         ~8 GB cap    │
└────────────────────────────────────────────────────────────────┘
         │
         │  E2E-encrypted API (auto-2FA via totp_secret)
         ▼
   Internxt Cloud Storage
```

### Key Design Choices

| Decision | Rationale |
|---|---|
| Host bind mounts for FUSE | Named volumes default to `rprivate` propagation, which silently prevents FUSE mounts from being visible across containers. Bind mounts with `rshared`/`rslave` fix this. |
| Build rclone from fork source | The custom fork adds `totp_secret` support for automatic Internxt 2FA re-login. Not available in upstream rclone. |
| No `.env` file | Coolify injects variables via its UI. Required variables use `:?` syntax so the container refuses to start with a clear error message. |
| Three isolated storage paths | Cache, uploads, and mount point are physically separate to prevent any single component from consuming the entire 50 GB disk. |

## 50 GB Storage Budget

| Component | Allocation | Local? |
|---|---|---|
| rclone VFS cache | **8 GB** (hard cap) | Yes — evicted automatically |
| Immich uploads | ~4 GB | Yes |
| ML model cache | ~3 GB | Yes |
| PostgreSQL | ~2 GB | Yes |
| Redis | <100 MB | Yes |
| Docker + OS | ~5 GB | Yes |
| **External library** | **0 GB** | **No** — served from Internxt |
| **Headroom** | **~28 GB** | |

## Quick Start

### Prerequisites

- A Linux host running [Coolify](https://coolify.io)
- `fuse3` installed on the host (`apt install fuse3`)
- An [Internxt](https://internxt.com) account
- **50 GB** free disk space

### 1. Host Prep

```bash
apt update && apt install -y fuse3
BASE="/data/coolify/immich"
mkdir -p "$BASE"/{external-library,rclone-config,rclone-cache,upload,postgres,ml-cache,redis}
```

### 2. Configure rclone

Create `$BASE/rclone-config/rclone.conf`:

```ini
[MyInternxt]
type = internxt
email = you@domain.com
password = your-password
totp_secret = JBSWY3DPEHPK3PXP
```

> `totp_secret` is the base32 key from when you set up 2FA on your Internxt account — this fork uses it to automatically generate TOTP codes on every reconnect, so you never need to enter 2FA manually.

### 3. Add to Coolify

1. **New Resource → Docker Compose (from GitHub)**
2. Select `thies2005/immich-rclone-coolify`
3. Add the required environment variables (see below)
4. Deploy

### Minimum Required Variables

| Variable | Value |
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
| `DB_PASSWORD` | *(strong random password)* |

### 4. Post-Deploy

- Open Immich and create your admin account
- Go to **Administration → External Libraries**
- Add a library with path `/mnt/external-library`
- Click **Scan** (first scan is slow — every file downloads and decrypts from Internxt)

## What to Expect

- **First deploy**: 5–10 minutes (rclone compiles from source)
- **First scan**: Slow — each file is downloaded, decrypted, cached. 10k photos may take 2–4 hours. This is normal.
- **Subsequent scans**: Fast — only changed files are re-downloaded, directory listings are cached
- **Subsequent deploys**: Minutes — the rclone image is cached by Docker

## Services

| Service | Image | Purpose |
|---|---|---|
| `rclone` | Built from [thies2005/rclone](https://github.com/thies2005/rclone) | FUSE mount of Internxt with auto-2FA |
| `immich-server` | `ghcr.io/immich-app/immich` | API + web UI |
| `immich-machine-learning` | `ghcr.io/immich-app/immich` | Smart search, face detection |
| `postgres` | `tensorchord/pgvecto-rs:pg14` | Database with pgvector |
| `redis` | `redis:7-alpine` | Job queue + cache |

## Documentation

| File | Description |
|---|---|
| [`COOLIFY-SETUP.md`](COOLIFY-SETUP.md) | Full step-by-step deployment guide with troubleshooting |
| [`ENV-VARIABLES.md`](ENV-VARIABLES.md) | Complete reference for all environment variables |
| [`docker-compose.yml`](docker-compose.yml) | Service definitions |
| [`Dockerfile.rclone`](Dockerfile.rclone) | Multi-stage rclone build from fork |
| [`scripts/entrypoint.sh`](scripts/entrypoint.sh) | Mount startup, validation, signal handling |
| [`scripts/healthcheck.sh`](scripts/healthcheck.sh) | FUSE mount health verification |

## Built With

- [Immich](https://immich.app) — self-hosted Google Photos alternative
- [Internxt](https://internxt.com) — zero-knowledge encrypted cloud storage
- [rclone](https://rclone.org) — the Swiss army knife of cloud storage (custom [fork](https://github.com/thies2005/rclone) with TOTP 2FA support)
- [Coolify](https://coolify.io) — open-source PaaS platform

## License

MIT
