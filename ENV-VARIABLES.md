# Environment Variables

Only **`DB_PASSWORD`** is required. Everything else has working defaults.

---

## Database

| Variable | Required | Default | Description |
|---|---|---|---|
| `DB_PASSWORD` | **Yes** | -- | PostgreSQL password. **Set a strong random password.** |
| `DB_USERNAME` | No | `immich` | PostgreSQL user. |
| `DB_DATABASE_NAME` | No | `immich` | PostgreSQL database name. |

---

## Immich

| Variable | Required | Default | Description |
|---|---|---|---|
| `IMMICH_VERSION` | No | `v2` | Immich image tag. Pin to a version (e.g. `v2.1.0`) for reproducibility. |
| `IMMICH_PORT` | No | `2283` | Host port for direct HTTP access (standalone deployment only). |

---

## Machine Learning Balancer (Coolify and standalone)

Use a single internal URL in Immich: `http://immich-ml-balancer:80`.

| Variable | Required | Default | Description |
|---|---|---|---|
| `ML_LB_METHOD` | No | `round_robin` | Balancing mode: `round_robin`, `weighted`. Uses `split_clients` for hash-based distribution. |
| `ML_LB_KEEPALIVE` | No | `32` | Upstream keepalive connections. |
| `ML_BACKEND_MAX_FAILS` | No | `2` | Passive-fail threshold before backend is marked failed. |
| `ML_BACKEND_FAIL_TIMEOUT` | No | `10s` | Time window for fail counting and temporary backend disablement. |
| `ML_PROXY_CONNECT_TIMEOUT` | No | `3s` | Connect timeout to backend. |
| `ML_PROXY_SEND_TIMEOUT` | No | `300s` | Send timeout to backend. |
| `ML_PROXY_READ_TIMEOUT` | No | `300s` | Read timeout from backend. |
| `ML_PROXY_NEXT_UPSTREAM_TRIES` | No | `3` | Retry attempts on failure (same backend). |
| `ML_BACKEND_1` | No* | `immich-machine-learning:3003` | Backend target: `host:port`, `http://host:port`, or `https://host`. |
| `ML_BACKEND_1_WEIGHT` | No | `1` | Used when `ML_LB_METHOD=weighted`. |
| `ML_BACKEND_2` ... `ML_BACKEND_10` | No | empty | Additional backend targets `host:port`. |
| `ML_BACKEND_2_WEIGHT` ... `ML_BACKEND_10_WEIGHT` | No | `1` | Additional backend weights. |
| `MACHINE_LEARNING_WORKERS` | No | `1` | Number of ML worker processes. Keep `1` unless host has ample RAM. |
| `MACHINE_LEARNING_REQUEST_THREADS` | No | `1` | ML request thread pool size. Lower values reduce memory pressure. |
| `MACHINE_LEARNING_MODEL_INTER_OP_THREADS` | No | `1` | Parallel model ops thread count. |
| `MACHINE_LEARNING_MODEL_INTRA_OP_THREADS` | No | `1` | Threads per model operation. |
| `MACHINE_LEARNING_WORKER_TIMEOUT` | No | `300` | Worker kill timeout (seconds) before restart. |

*At least one backend should be configured.

---

## Reverse Proxy (standalone deployment only)

These variables are used when deploying with `docker-compose.standalone.yml`. Coolify handles its own reverse proxy via Traefik.

### Caddy (Option A)

| Variable | Required | Default | Description |
|---|---|---|---|
| `DOMAIN` | Yes* | -- | Your domain name (e.g. `photos.example.com`). DNS must point to your server. |
| `CADDY_ACME_EMAIL` | Yes* | -- | Email for Let's Encrypt certificate notifications. |

*Required when using the Caddy service.

### Cloudflare Tunnel (Option B)

| Variable | Required | Default | Description |
|---|---|---|---|
| `CLOUDFLARE_TOKEN` | Yes* | -- | Tunnel token from [Cloudflare Zero Trust](https://one.dash.cloudflare.com). |

*Required when using the Cloudflare Tunnel service.

### Tailscale Serve (Option C)

| Variable | Required | Default | Description |
|---|---|---|---|
| `TS_AUTHKEY` | Yes* | -- | Auth key from [Tailscale admin](https://login.tailscale.com/admin/settings/keys). Enable "Reusable". |

*Required when using the Tailscale service.

---

## rclone (configured on the host)

rclone settings are NOT Docker env vars. They live in:

| File | Purpose |
|---|---|
| `/etc/immich-rclone/rclone.conf` | Internxt credentials (email, password, TOTP) |
| `/etc/immich-rclone/mount.env` | Mount settings (cache size, timeouts, etc.) |

To change rclone settings, edit those files on the host and run `sudo systemctl restart immich-rclone`.

### Host rclone settings (in `/etc/immich-rclone/mount.env`)

| Variable | Default | Description |
|---|---|---|
| `RCLONE_VFS_CACHE_MAX_SIZE` | `32G` | Hard ceiling for VFS cache. |
| `RCLONE_VFS_CACHE_MAX_AGE` | `48h` | Evict cached files after this idle duration. |
| `RCLONE_BUFFER_SIZE` | `128M` | Per-file read buffer. |
| `RCLONE_READ_AHEAD` | `256M` | Sequential read-ahead for photo/video scanning. |
| `RCLONE_DIR_CACHE_TIME` | `30m` | Directory listing cache TTL. |
| `RCLONE_ATTR_CACHE_TIME` | `30m` | File attribute cache TTL. |
| `RCLONE_TRANSFERS` | `2` | Parallel file transfers. Keep low to avoid Internxt rate limits. |
| `RCLONE_CHECKERS` | `4` | Parallel file checkers. |
| `RCLONE_RETRIES` | `5` | Retries per failed operation. |
| `RCLONE_LOW_LEVEL_RETRIES` | `10` | Low-level HTTP retries. |
| `RCLONE_TIMEOUT` | `300s` | Idle timeout. |
| `RCLONE_CONTIMEOUT` | `30s` | Connection timeout. |

---

## Quick Start

### Standalone Docker deployment

```bash
cp .env.example .env
# Edit .env -- set DB_PASSWORD at minimum
docker compose -f docker-compose.standalone.yml up -d
```

### Coolify deployment

Set `DB_PASSWORD` in the Coolify resource settings. That's it.

Internxt credentials are configured during `install.sh` on the host, not in Docker/Coolify.

---

## Storage Budget

| Component | Location | Allocation | Notes |
|---|---|---|---|
| PostgreSQL | `postgres_data` | ~2 GB | Grows with metadata. |
| Immich uploads | `upload_data` | ~4 GB | User originals. |
| ML model cache | `ml_cache` | ~3 GB | Face/recognition models. |
| Redis | `redis_data` | <100 MB | |
| rclone VFS cache | `/var/cache/immich-rclone/` | **~32 GB** | Hard-capped on host. |
| External library | FUSE mount | **0 GB** | Served from Internxt. |
| Docker + OS | Docker root | ~5 GB | Build artifacts. |
| **Total used** | | **~42 GB** | |
| **Headroom** | | **~8 GB** | |
