<div align="center">

# Immich + Internxt on Coolify

**Self-hosted photo management backed by Internxt's encrypted cloud storage.**

[![GitHub](https://img.shields.io/badge/repo-thies2005%2Fimmich--rclone--coolify-181717?logo=github)](https://github.com/thies2005/immich-rclone-coolify)
[![Coolify](https://img.shields.io/badge/deploy-Coolify-blue)](https://coolify.io)
[![Immich](https://img.shields.io/badge/Immich-v2-4250af?logo=immich)](https://immich.app)
[![Internxt](https://img.shields.io/badge/Internxt-E2E%20encrypted-0066ff)](https://internxt.com)
[![rclone](https://img.shields.io/badge/rclone-custom%20fork-orange?logo=rclone)](https://github.com/thies2005/rclone)

A production-ready Docker Compose stack that runs **Immich** with an **Internxt** remote mounted as an external library via a custom **rclone** fork with automatic 2FA re-authentication. Designed to deploy on a **50 GB** Coolify host.

**No SSH into the host. No manual file creation. Just set 3–4 env vars in Coolify and deploy.**

</div>

---

## What This Does

```
  Your browser ──▶ Immich ──▶ rclone FUSE mount ──▶ Internxt Cloud
     (photos)      (server)     (E2E decrypt)        (encrypted)
```

- Mounts your **Internxt** cloud storage inside Docker using a [custom rclone fork](https://github.com/thies2005/rclone) with **automatic TOTP 2FA** support
- Serves the mount to **Immich** as a read-only external library for browsing, searching, and backing up photos
- Keeps **0 bytes** of your Internxt library on local disk (VFS cache only)
- Runs entirely through **Coolify** — everything configured via environment variables in the UI

## How It Works

1. **rclone.conf is auto-generated** from env vars on every container start — no manual config file needed
2. **Named Docker volumes** for all persistent data — Coolify manages them automatically
3. **FUSE mount shared between containers** via bind mount with `shared`/`slave` propagation — the mount point directory is auto-created by Docker
4. **`--vfs-cache-mode full` enforced** — the only mode compatible with Internxt's E2E encryption

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
│  │  immich-server                                        │ │
│  └───────────────────────────────────────────────────────┘ │
│                                                             │
│  Named volumes (Docker-managed, no host paths needed):      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐  │
│  │ postgres │ │  redis   │ │ uploads  │ │ ml_cache     │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────────┘  │
│  ┌──────────────┐ ┌──────────────┐                          │
│  │ rclone_cache │ │rclone_config │  ← auto-generated       │
│  └──────────────┘ └──────────────┘     from env vars       │
└──────────────────────────────────────────────────────────────┘
         │
         │  E2E-encrypted API (auto-2FA via totp_secret)
         ▼
   Internxt Cloud Storage
```

## 50 GB Storage Budget

| Component | Volume | Allocation | Local? |
|---|---|---|---|
| rclone VFS cache | `rclone_cache` | **8 GB** (hard cap) | Yes — auto-evicted |
| Immich uploads | `upload_data` | ~4 GB | Yes |
| ML model cache | `ml_cache` | ~3 GB | Yes |
| PostgreSQL | `postgres_data` | ~2 GB | Yes |
| Redis | `redis_data` | <100 MB | Yes |
| Docker + OS | *(Docker root)* | ~5 GB | Yes |
| **External library** | *(FUSE mount)* | **0 GB** | **No** — Internxt |
| **Headroom** | | **~28 GB** | |

## Quick Start

### 1. Add to Coolify

**New Resource → Docker Compose (from GitHub)** → select `thies2005/immich-rclone-coolify`

### 2. Set these env vars in the Coolify UI

```
INTERNXT_EMAIL=you@domain.com
INTERNXT_PASSWORD=your-internxt-password
INTERNXT_TOTP_SECRET=JBSWY3DPEHPK3PXP
DB_PASSWORD=a-strong-random-password
```

> `INTERNXT_TOTP_SECRET` is only needed if your Internxt account has 2FA enabled. It's the **base32 secret key** from when you set up 2FA — NOT a one-time code from your authenticator app. If you lost it, disable and re-enable 2FA on your Internxt account.

### 3. Deploy

Click **Deploy**. First deploy takes 5–10 minutes (rclone compiles from source).

### 4. Post-deploy

- Open Immich, create admin account
- **Administration → External Libraries → Create Library**
- Path: `/mnt/external-library` → **Scan**

First scan is slow (2–4 hours for 10k photos) — every file downloads and decrypts through E2E. Subsequent scans are fast.

> 📖 **Need a detailed step-by-step guide?** See [`DEPLOY.md`](DEPLOY.md) for complete Coolify deployment instructions with screenshots-like navigation.

## What to Expect

| Phase | Duration | Why |
|---|---|---|
| First deploy | 5–10 min | rclone compiles from Go source |
| rclone startup | 30–90 sec | Internxt auth + 2FA + FUSE mount |
| First library scan | 2–4 hours / 10k photos | E2E download + decrypt per file |
| Subsequent deploys | 1–2 min | Image cached, rclone reconnects |
| Subsequent scans | Minutes | Only changed files re-downloaded |

## Services

| Service | Image | Purpose |
|---|---|---|
| `rclone` | Built from [thies2005/rclone](https://github.com/thies2005/rclone) | FUSE mount with auto-2FA |
| `immich-server` | `ghcr.io/immich-app/immich-server` | API + web UI |
| `immich-machine-learning` | `ghcr.io/immich-app/immich-machine-learning` | Smart search, face detection |
| `postgres` | `ghcr.io/immich-app/postgres` | Database with vector extensions |
| `redis` | `docker.io/valkey/valkey:9` | Job queue + cache |

## Documentation

| File | Description |
|---|---|
| [`DEPLOY.md`](DEPLOY.md) | **Step-by-step Coolify deployment guide** (start here for detailed instructions) |
| [`COOLIFY-SETUP.md`](COOLIFY-SETUP.md) | Full troubleshooting guide with common issues |
| [`ENV-VARIABLES.md`](ENV-VARIABLES.md) | All environment variables with defaults |
| [`docker-compose.yml`](docker-compose.yml) | Service definitions |
| [`Dockerfile.rclone`](Dockerfile.rclone) | Multi-stage rclone build from fork |
| [`scripts/entrypoint.sh`](scripts/entrypoint.sh) | Config generation, mount, signal handling |
| [`scripts/healthcheck.sh`](scripts/healthcheck.sh) | FUSE mount health verification |

## Built With

- [Immich](https://immich.app) — self-hosted Google Photos alternative
- [Internxt](https://internxt.com) — zero-knowledge encrypted cloud storage
- [rclone](https://rclone.org) — cloud storage Swiss army knife (custom [fork](https://github.com/thies2005/rclone) with TOTP 2FA)
- [Coolify](https://coolify.io) — open-source PaaS

## License

MIT
