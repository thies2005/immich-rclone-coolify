# Environment Variables — Coolify Deployment

Paste these into the Coolify service configuration UI. Variables marked **Required** must be set; those marked **Optional** have sane defaults.

---

## Immich Core

| Variable | Required | Default | Description |
|---|---|---|---|
| `IMMICH_VERSION` | No | `release` | Immich image tag from `ghcr.io/immich-app/immich`. Pin to a specific version (e.g. `v1.134.0`) for reproducibility. |
| `IMMICH_HTTP_PORT` | No | `2283` | Host port mapped to Immich's web interface. Coolify's reverse proxy typically ignores this — set the domain in the Coolify UI instead. |

## Database

| Variable | Required | Default | Description |
|---|---|---|---|
| `DB_PASSWORD` | **Yes** | — | PostgreSQL password. **Change this from any default.** |
| `DB_USERNAME` | No | `immich` | PostgreSQL user. |
| `DB_DATABASE_NAME` | No | `immich` | PostgreSQL database name. |

## rclone Build

| Variable | Required | Default | Description |
|---|---|---|---|
| `RCLONE_REPO` | No | `https://github.com/thies2005/rclone.git` | Git URL of the rclone fork to build from. Change this only if you forked the fork. |
| `RCLONE_BRANCH` | No | `master` | Branch to clone during build. |

## rclone Core

| Variable | Required | Default | Description |
|---|---|---|---|
| `RCLONE_REMOTE_SOURCE` | **Yes** | — | Internxt remote path as configured in `rclone.conf` (e.g. `MyInternxt:` or `MyInternxt:/Photos`). |
| `RCLONE_HOST_CONFIG_PATH` | **Yes** | — | Absolute host path to the directory containing `rclone.conf` (e.g. `/data/coolify/immich/rclone-config`). Must exist on the host before deployment. |
| `RCLONE_HOST_MOUNT_PATH` | **Yes** | — | Absolute host path used as the FUSE mount point (e.g. `/data/coolify/immich/external-library`). Must be an empty directory on the host. This is shared between rclone and immich-server. |
| `RCLONE_MOUNT_TARGET` | No | `/mnt/external-library` | In-container mount point. Rarely needs changing. |

## rclone Cache (50 GB Budget — CRITICAL)

| Variable | Required | Default | Description |
|---|---|---|---|
| `RCLONE_HOST_CACHE_PATH` | **Yes** | — | Absolute host path for VFS cache storage (e.g. `/data/coolify/immich/rclone-cache`). **Must be on a different path from the mount point and the upload directory** to prevent runaway disk usage. |
| `RCLONE_CACHE_DIR` | No | `/cache/vfs` | In-container path for VFS cache. Maps to `RCLONE_HOST_CACHE_PATH`. |
| `RCLONE_VFS_CACHE_MAX_SIZE` | **Yes** | — | Hard ceiling for VFS cache (e.g. `8G`). The container **will refuse to start** if this is unset. Must leave room for the rest of the 50 GB budget. |
| `RCLONE_VFS_CACHE_MAX_AGE` | No | `48h` | Evict cached files after this idle duration. |
| `RCLONE_VFS_CACHE_POLL_INTERVAL` | No | `30s` | How often rclone scans the cache for eviction. |

## rclone Tuning (Internxt E2E Optimized)

| Variable | Required | Default | Description |
|---|---|---|---|
| `RCLONE_VFS_CACHE_MODE` | No | `full` | **Forced to `full` — cannot be changed.** Internxt E2E encryption requires full-file caching. The entrypoint silently overrides any other value. |
| `RCLONE_BUFFER_SIZE` | No | `64M` | Per-file read buffer. Increase only if you have spare RAM. |
| `RCLONE_READ_AHEAD` | No | `128M` | Sequential read-ahead for photo/video scanning. |
| `RCLONE_DIR_CACHE_TIME` | No | `5m` | Directory listing cache TTL. Increase to reduce Internxt API calls. |
| `RCLONE_TRANSFERS` | No | `2` | Parallel file transfers. Keep low to avoid Internxt rate limits under E2E decryption load. |
| `RCLONE_CHECKERS` | No | `4` | Parallel file checkers. |
| `RCLONE_RETRIES` | No | `5` | Retries per failed operation. |
| `RCLONE_LOW_LEVEL_RETRIES` | No | `10` | Low-level HTTP retries. |
| `RCLONE_TIMEOUT` | No | `120s` | Idle timeout for transfers. Generous timeout accounts for E2E decryption latency. |
| `RCLONE_CONTIMEOUT` | No | `30s` | Connection establishment timeout. |
| `RCLONE_NO_CHECKSUM` | No | `true` | Skip checksum verification — Internxt's E2E wrapper can produce false checksum mismatches. |
| `RCLONE_EXTRA_MOUNT_ARGS` | No | *(empty)* | Additional space-separated flags passed to `rclone mount`. Use with caution. |

## Host Volume Paths

| Variable | Required | Default | Description |
|---|---|---|---|
| `UPLOAD_HOST_PATH` | **Yes** | — | Absolute host path for Immich user uploads (e.g. `/data/coolify/immich/upload`). |
| `DB_HOST_PATH` | **Yes** | — | Absolute host path for PostgreSQL data (e.g. `/data/coolify/immich/postgres`). |
| `ML_CACHE_HOST_PATH` | **Yes** | — | Absolute host path for ML model cache (e.g. `/data/coolify/immich/ml-cache`). |
| `REDIS_HOST_PATH` | **Yes** | — | Absolute host path for Redis data (e.g. `/data/coolify/immich/redis`). |

---

## 50 GB Storage Budget Allocation

| Component | Path (host) | Allocation | Notes |
|---|---|---|---|
| PostgreSQL | `$DB_HOST_PATH` | ~2 GB | Grows with library metadata. |
| Immich uploads | `$UPLOAD_HOST_PATH` | ~4 GB | User-uploaded originals. |
| ML model cache | `$ML_CACHE_HOST_PATH` | ~3 GB | Face/recognition models. |
| Redis | `$REDIS_HOST_PATH` | <100 MB | LRU-evicted, negligible. |
| rclone VFS cache | `$RCLONE_HOST_CACHE_PATH` | **~8 GB** | Hard-capped by `RCLONE_VFS_CACHE_MAX_SIZE`. |
| VFS overflow headroom | *(same filesystem)* | ~2 GB | Temp space during cache eviction. |
| Docker images + OS | *(Docker root)* | ~5 GB | Build artifacts + base images. |
| External library | `$RCLONE_HOST_MOUNT_PATH` | **0 GB local** | FUSE mount — files served from Internxt, not stored locally. |
| **Total used** | | **~24 GB** | |
| **Headroom** | | **~26 GB** | Buffer for transcodes if enabled later. |

> **Do NOT set `RCLONE_VFS_CACHE_MAX_SIZE` above 12G.** The host filesystem needs free space for cache eviction, Docker layer builds, and Immich thumbnail generation. The recommended sweet spot is 8G.
