# Environment Variables — Coolify Deployment

Only **`DB_PASSWORD`** is required. Everything else has working defaults.

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
| `IMMICH_VERSION` | No | `v2` | Immich image tag. Pin to a version (e.g. `v2.1.0`) for reproducibility. |

---

## rclone (configured on the host)

rclone settings are NOT Docker env vars in this setup. They live in:

| File | Purpose |
|---|---|
| `/etc/immich-rclone/rclone.conf` | Internxt credentials (email, password, TOTP) |
| `/etc/immich-rclone/mount.env` | Mount settings (cache size, timeouts, etc.) |

To change rclone settings, edit those files on the host and run `sudo systemctl restart immich-rclone`.

### Host rclone settings (in `/etc/immich-rclone/mount.env`)

| Variable | Default | Description |
|---|---|---|
| `RCLONE_VFS_CACHE_MAX_SIZE` | `8G` | Hard ceiling for VFS cache. |
| `RCLONE_VFS_CACHE_MAX_AGE` | `48h` | Evict cached files after this idle duration. |
| `RCLONE_BUFFER_SIZE` | `64M` | Per-file read buffer. |
| `RCLONE_READ_AHEAD` | `128M` | Sequential read-ahead for photo/video scanning. |
| `RCLONE_DIR_CACHE_TIME` | `5m` | Directory listing cache TTL. |
| `RCLONE_TRANSFERS` | `2` | Parallel file transfers. Keep low to avoid Internxt rate limits. |
| `RCLONE_CHECKERS` | `4` | Parallel file checkers. |
| `RCLONE_RETRIES` | `5` | Retries per failed operation. |
| `RCLONE_LOW_LEVEL_RETRIES` | `10` | Low-level HTTP retries. |
| `RCLONE_TIMEOUT` | `120s` | Idle timeout. |
| `RCLONE_CONTIMEOUT` | `30s` | Connection timeout. |

---

## Minimum Configuration (copy-paste into Coolify)

```
DB_PASSWORD=a-strong-random-password
```

That's it. Everything else has working defaults.

Internxt credentials are configured during `install.sh` on the host, not in Coolify.

---

## Storage Budget

| Component | Location | Allocation | Notes |
|---|---|---|---|
| PostgreSQL | `postgres_data` | ~2 GB | Grows with metadata. |
| Immich uploads | `upload_data` | ~4 GB | User originals. |
| ML model cache | `ml_cache` | ~3 GB | Face/recognition models. |
| Redis | `redis_data` | <100 MB | |
| rclone VFS cache | `/var/cache/immich-rclone/` | **~8 GB** | Hard-capped on host. |
| External library | FUSE mount | **0 GB** | Served from Internxt. |
| Docker + OS | Docker root | ~5 GB | Build artifacts. |
| **Total used** | | **~22 GB** | |
| **Headroom** | | **~28 GB** | |
