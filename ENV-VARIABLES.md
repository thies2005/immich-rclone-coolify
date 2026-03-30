# Environment Variables — Coolify Deployment

Paste these into the Coolify service configuration UI. Most variables have sane defaults — you only **must** set the ones marked **Required**.

---

## Internxt Connection (Required)

| Variable | Required | Default | Description |
|---|---|---|---|
| `INTERNXT_EMAIL` | **Yes** | — | Your Internxt account email. |
| `INTERNXT_PASSWORD` | **Yes** | — | Your Internxt account password. |
| `INTERNXT_REMOTE_NAME` | No | `MyInternxt` | Name for the rclone remote. Only change if you want a custom name. |
| `INTERNXT_TOTP_SECRET` | No | *(empty)* | Base32 TOTP secret from your authenticator app. **Required if your Internxt account has 2FA enabled.** Not a one-time code — it's the permanent secret key. If your account doesn't use 2FA, leave this empty. |

> **How to get `INTERNXT_TOTP_SECRET`:** When you originally set up 2FA on your Internxt account, you scanned a QR code with an authenticator app. That QR code encodes a `secret=` parameter in base32 (e.g. `JBSWY3DPEHPK3PXP`). That value is your TOTP secret. If you no longer have it, disable and re-enable 2FA on your Internxt account to get a new one.

---

## Database

| Variable | Required | Default | Description |
|---|---|---|---|
| `DB_PASSWORD` | **Yes** | — | PostgreSQL password. **Set a strong random password.** |
| `DB_USERNAME` | No | `immich` | PostgreSQL user. |
| `DB_DATABASE_NAME` | No | `immich` | PostgreSQL database name. |

---

## Immich

| Variable | Required | Default | Description |
|---|---|---|---|
| `IMMICH_VERSION` | No | `release` | Immich image tag. Pin to a version (e.g. `v1.134.0`) for reproducibility. |
| `IMMICH_HTTP_PORT` | No | `2283` | Host port for the web interface. Coolify's reverse proxy usually handles this. |

---

## rclone Build

| Variable | Required | Default | Description |
|---|---|---|---|
| `RCLONE_REPO` | No | `https://github.com/thies2005/rclone.git` | Git URL of the rclone fork to build from. |
| `RCLONE_BRANCH` | No | `master` | Branch to clone during build. |

---

## rclone Cache (50 GB Budget)

| Variable | Required | Default | Description |
|---|---|---|---|
| `RCLONE_VFS_CACHE_MAX_SIZE` | No | `8G` | Hard ceiling for VFS cache. The container enforces this limit. Keep at or below `8G` to stay within the 50 GB budget. |
| `RCLONE_VFS_CACHE_MAX_AGE` | No | `48h` | Evict cached files after this idle duration. |
| `RCLONE_VFS_CACHE_POLL_INTERVAL` | No | `30s` | How often rclone scans the cache for eviction. |

---

## rclone Tuning (Internxt E2E Optimized)

| Variable | Required | Default | Description |
|---|---|---|---|
| `RCLONE_VFS_CACHE_MODE` | No | `full` | **Forced to `full` — cannot be changed.** Internxt E2E encryption requires full-file caching. The entrypoint silently overrides any other value. |
| `RCLONE_BUFFER_SIZE` | No | `64M` | Per-file read buffer. |
| `RCLONE_READ_AHEAD` | No | `128M` | Sequential read-ahead for photo/video scanning. |
| `RCLONE_DIR_CACHE_TIME` | No | `5m` | Directory listing cache TTL. |
| `RCLONE_TRANSFERS` | No | `2` | Parallel file transfers. Keep low to avoid Internxt rate limits. |
| `RCLONE_CHECKERS` | No | `4` | Parallel file checkers. |
| `RCLONE_RETRIES` | No | `5` | Retries per failed operation. |
| `RCLONE_LOW_LEVEL_RETRIES` | No | `10` | Low-level HTTP retries. |
| `RCLONE_TIMEOUT` | No | `120s` | Idle timeout. Accounts for E2E decryption latency. |
| `RCLONE_CONTIMEOUT` | No | `30s` | Connection establishment timeout. |
| `RCLONE_NO_CHECKSUM` | No | `true` | Skip checksums — Internxt E2E can cause false mismatches. |
| `RCLONE_EXTRA_MOUNT_ARGS` | No | *(empty)* | Additional flags passed to `rclone mount`. |

---

## FUSE Mount Point

The FUSE mount point is fixed in `docker-compose.yml` for Coolify compatibility:

| Path | Purpose |
|---|---|
| `/mnt/immich-external-library` | Host bind path used for mount propagation between `rclone` and `immich-server` |
| `/mnt/external-library` | In-container mount path used by Immich for the external library |

Coolify rejects `${...}` interpolation inside Docker volume targets and bind sources, so these paths are intentionally hard-coded.

---

## Minimum Configuration (copy-paste into Coolify)

```
INTERNXT_EMAIL=you@domain.com
INTERNXT_PASSWORD=your-internxt-password
INTERNXT_TOTP_SECRET=JBSWY3DPEHPK3PXP
DB_PASSWORD=a-strong-random-password
```

That's it. Everything else has working defaults.

---

## 50 GB Storage Budget

| Component | Volume | Allocation | Notes |
|---|---|---|---|
| PostgreSQL | `postgres_data` | ~2 GB | Grows with metadata. |
| Immich uploads | `upload_data` | ~4 GB | User originals. |
| ML model cache | `ml_cache` | ~3 GB | Face/recognition models. |
| Redis | `redis_data` | <100 MB | LRU-evicted. |
| rclone VFS cache | `rclone_cache` | **~8 GB** | Hard-capped by `RCLONE_VFS_CACHE_MAX_SIZE`. |
| rclone config | `rclone_config` | <1 MB | Auto-generated rclone.conf. |
| Docker images + OS | *(Docker root)* | ~5 GB | Build artifacts. |
| External library | *(FUSE mount)* | **0 GB** | Served from Internxt. |
| **Total used** | | **~22 GB** | |
| **Headroom** | | **~28 GB** | |
