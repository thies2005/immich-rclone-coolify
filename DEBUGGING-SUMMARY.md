# Debugging Summary: Immich 503 / "No Available Server" via Coolify

## Problem

Accessing `https://immich2.schuelken.uk` in a browser shows a black page with text "no available server".
The domain is deployed on a Coolify v4.0.0-beta.470 instance using Traefik v3.6 as the reverse proxy.

## Environment

- **Host**: VPS at `130.61.239.57` (Hetzner/other provider), Ubuntu Linux
- **Coolify version**: 4.0.0-beta.470
- **Proxy**: Traefik v3.6 (container name: `coolify-proxy`), running as a Docker container
- **DNS**: `immich2.schuelken.uk` → `130.61.239.57` (confirmed correct, NOT behind Cloudflare proxy)
- **Coolify dashboard**: `coolify.schuelken.uk` works correctly from external (for comparison)

## Application Stack (Docker Compose from GitHub: `thies2005/immich-rclone-coolify`)

All 5 services are healthy:

| Container | Image | Status | Port |
|---|---|---|---|
| `immich-server-*` | `ghcr.io/immich-app/immich-server:v2` (v2.6.3) | healthy | 2283 |
| `postgres-*` | `ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0` | healthy | 5432 |
| `redis-*` | `valkey/valkey:9` | healthy | 6379 |
| `immich-machine-learning-*` | `ghcr.io/immich-app/immich-machine-learning:v2` | healthy | 3003 |
| `rclone-*` | custom build from forked rclone | healthy | N/A (FUSE) |

All services are on Docker network `ugu61g8y34hs31n9p99q62xl`.
Traefik (`coolify-proxy`) is on networks: `coolify`, `ctvo56gaegt12ph8uriz8gs5`, `ugu61g8y34hs31n9p99q62xl`, `xmo4iiw8p5xv9v0vglhhpv1o`.

## Root Cause #1 (FIXED): Healthcheck URL was wrong for Immich v2

**Problem**: The `docker-compose.yml` healthcheck for `immich-server` used `/api/server-info/ping` which returned 404 in Immich v2.x. Immich v2 changed the endpoint to `/api/server/ping`.

**Fix applied**: Changed `docker-compose.yml` line 87 from:
```yaml
test: ["CMD", "curl", "-f", "http://localhost:2283/api/server-info/ping"]
```
to:
```yaml
test: ["CMD", "curl", "-f", "http://localhost:2283/api/server/ping"]
```

**Status**: Fixed, committed, pushed to GitHub. Container now reports `healthy`. But the 503/"no available server" persists.

## Root Cause #2 (UNSOLVED): Traefik returns 404/"no available server" for external requests

### Symptoms

| Test | Result |
|---|---|
| `curl -s http://127.0.0.1 -H "Host: immich2.schuelken.uk"` | **302** redirect to HTTPS (WORKS) |
| `curl -sk https://127.0.0.1 -H "Host: immich2.schuelken.uk"` | **Full Immich HTML** (WORKS) |
| `curl -s http://130.61.239.57 -H "Host: immich2.schuelken.uk"` | **404** "page not found" (FAILS) |
| `curl -sk https://130.61.239.57 -H "Host: immich2.schuelken.uk"` | **"no available server"** (FAILS) |
| `curl -s http://130.61.239.57 -H "Host: coolify.schuelken.uk"` | Works (302/HTML) (WORKS) |
| `curl -sk https://130.61.239.57 -H "Host: coolify.schuelken.uk"` | Works (Coolify dashboard HTML) (WORKS) |
| `docker exec coolify-proxy wget -qO- http://immich-server-*:2283/api/server/ping` | `{"res":"pong"}` (WORKS) |
| `curl -s http://130.61.239.57 -H "Host: immich2.schuelken.uk" --connect-to ::172.18.0.2:` | **302** redirect (WORKS when bypassing iptables) |

### Key observation

Traffic from **localhost** is routed correctly to Immich by Traefik. Traffic from the **public IP** (130.61.239.57) returns 404 (HTTP) or "no available server" (HTTPS) — falling through to the catchall noop service. This is despite using the exact same Host header.

The `coolify.schuelken.uk` domain works from BOTH localhost AND public IP through the same Traefik proxy.

When bypassing iptables DNAT with `--connect-to ::172.18.0.2:`, public IP traffic works — suggesting the issue is in the iptables/forwarding path.

### Traefik Configuration

**Startup args** (from `docker inspect coolify-proxy`):
```
--ping=true
--ping.entrypoint=http
--api.dashboard=true
--entrypoints.http.address=:80
--entrypoints.https.address=:443
--entrypoints.http.http.encodequerysemicolons=true
--entryPoints.http.http2.maxConcurrentStreams=250
--entrypoints.https.http.encodequerysemicolons=true
--entryPoints.https.http2.maxConcurrentStreams=250
--entrypoints.https.http3
--providers.file.directory=/traefik/dynamic/
--providers.file.watch=true
--certificatesresolvers.letsencrypt.acme.httpchallenge=true
--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=http
--certificatesresolvers.letsencrypt.acme.storage=/traefik/acme.json
--api.insecure=false
--providers.docker=true
--providers.docker.exposedbydefault=false
```

**Dynamic config** (file at `/data/coolify/proxy/dynamic/default_redirect_503.yaml` on host):
```yaml
http:
  routers:
    catchall:
      entryPoints:
        - http
        - https
      service: noop
      rule: PathPrefix(`/`)
      tls:
        certResolver: letsencrypt
      priority: -1000
  services:
    noop:
      loadBalancer:
        servers: {  }
```

The noop service has empty servers, which causes the "no available server" response when the catchall router matches.

**Caddyfile** at `/data/coolify/proxy/dynamic/Caddyfile`:
```
import /dynamic/*.caddy
```
(No `.caddy` files exist — Caddy is not running, only Traefik.)

### Traefik Labels on immich-server container

```json
{
    "traefik.enable": "true",
    "traefik.http.middlewares.gzip.compress": "true",
    "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme": "https",
    "traefik.http.routers.http-0-ugu61g8y34hs31n9p99q62xl-immich-server.entryPoints": "http",
    "traefik.http.routers.http-0-ugu61g8y34hs31n9p99q62xl-immich-server.middlewares": "redirect-to-https",
    "traefik.http.routers.http-0-ugu61g8y34hs31n9p99q62xl-immich-server.rule": "Host(`immich2.schuelken.uk`) && PathPrefix(`/`)",
    "traefik.http.routers.https-0-ugu61g8y34hs31n9p99q62xl-immich-server.entryPoints": "https",
    "traefik.http.routers.https-0-ugu61g8y34hs31n9p99q62xl-immich-server.middlewares": "gzip",
    "traefik.http.routers.https-0-ugu61g8y34hs31n9p99q62xl-immich-server.rule": "Host(`immich2.schuelken.uk`) && PathPrefix(`/`)",
    "traefik.http.routers.https-0-ugu61g8y34hs31n9p99q62xl-immich-server.tls": "true",
    "traefik.http.routers.https-0-ugu61g8y34hs31n9p99q62xl-immich-server.tls.certresolver": "letsencrypt",
    "caddy_0": "https://immich2.schuelken.uk",
    "caddy_0.encode": "zstd gzip",
    "caddy_0.handle_path": "/*",
    "caddy_0.handle_path.0_reverse_proxy": "{{upstreams}}",
    "caddy_0.header": "-Server",
    "caddy_0.try_files": "{path} /index.html /index.php",
    "caddy_ingress_network": "ugu61g8y34hs31n9p99q62xl"
}
```

Note: Coolify v4 beta generates BOTH Caddy and Traefik labels. Caddy is not running, only Traefik. The Traefik labels appear correct.

### Let's Encrypt Certificate Failure

Traefik log shows the ACME HTTP-01 challenge for `immich2.schuelken.uk` fails:
```
Unable to obtain ACME certificate for domains error="unable to generate a certificate for the domains [immich2.schuelken.uk]: error: one or more domains had a problem:\n[immich2.schuelken.uk] invalid authorization: acme: error: 403 :: urn:ietf:params:acme:error:unauthorized :: 130.61.239.57: Invalid response from http://immich2.schuelken.uk/.well-known/acme-challenge/...: 404\n"
```

This is likely a CONSEQUENCE of the routing issue (ACME challenge can't reach Traefik's challenge handler because the router isn't matching for external traffic). The existing working cert for `mail.schuelken.uk` is in `acme.json`.

### Network/Firewall

```
# iptables NAT
Chain PREROUTING: DNAT tcp dpt:80 → 172.18.0.2:80
Chain PREROUTING: DNAT tcp dpt:443 → 172.18.0.2:443

# iptables FORWARD (policy DROP)
DOCKER-USER → (empty, no rules)
DOCKER-FORWARD → DOCKER-CT, DOCKER-INTERNAL, DOCKER-BRIDGE, ACCEPT rules
REJECT icmp-host-prohibited at end

# No ufw, no nftables, no nginx/apache/caddy running on host
# Docker proxy listening on 0.0.0.0:80 and [::]:80
```

No conflicting web servers on the host. No firewall (ufw not installed).

### Coolify v4 Beta Note

The Coolify version is **4.0.0-beta.470**. Coolify v4 switched from Traefik to Caddy as its default proxy. This installation still uses Traefik (`coolify-proxy` is `traefik:v3.6`). Coolify v4 generates both Caddy labels (`caddy_*`) and Traefik labels (`traefik.*`) on containers. No Caddy container is running. This mismatch between Coolify v4's proxy expectations and the actual Traefik proxy may be relevant.

### Docker Compose (for reference)

```yaml
name: immich
services:
  immich-server:
    image: ghcr.io/immich-app/immich-server:v2  # v2.6.3
    ports:
      - "2283:2283"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:2283/api/server/ping"]
    # ... (depends on rclone, postgres, redis — all healthy)
```

Note: `ports: "2283:2283"` publishes port 2283 to the host, but this port is NOT open in the VPS firewall. All external traffic should go through Traefik on ports 80/443.

## The Core Mystery

Why does Traefik route `Host: immich2.schuelken.uk` correctly when the request comes from localhost/127.0.0.1, but falls through to the catchall noop service ("no available server") when the identical request (same Host header) comes from the public IP 130.61.239.57 — while `Host: coolify.schuelken.uk` works from BOTH?

## Diagnostic Steps Already Performed

1. Verified all containers are healthy
2. Verified immich-server responds to ping (`{"res":"pong"}`) from within the Docker network
3. Verified Traefik can reach immich-server backend from its own container
4. Verified DNS resolves correctly
5. Verified no conflicting web servers on the host
6. Verified iptables DNAT rules for ports 80/443
7. Verified Traefik labels on the immich-server container are correct
8. Verified the `--connect-to` bypass works (routing is correct when bypassing iptables)
9. Verified Coolify dashboard domain works from both localhost and public IP
10. Verified no Caddy container is running (only Traefik)

## Suggested Next Diagnostic Steps

1. **Enable Traefik access logging** to see what router Traefik actually matches for external vs localhost requests:
   - Add `--accesslog=true` to Traefik startup args (via Coolify or edit `/data/coolify/proxy/traefik.toml` if it exists)
   - Or create a file `/data/coolify/proxy/dynamic/accesslog.yaml`:
     ```yaml
     # This won't work for access logs — needs CLI flag
     ```
   - Best: add `--accesslog=true` to the Traefik container args

2. **Test with correct SNI** from the server:
   ```bash
   curl -svk https://immich2.schuelken.uk --resolve immich2.schuelken.uk:443:130.61.239.57 2>&1 | head -20
   ```

3. **Compare Traefik labels** between the working Coolify dashboard container and the immich-server container to find what's different.

4. **Check if Coolify v4 beta has a proxy mode setting** that needs to be switched from Caddy to Traefik.

5. **Try removing the `ports: "2283:2283"` mapping** from docker-compose.yml — it may cause Traefik to get confused about which port to use, since the container has both Traefik labels and an explicit port mapping. Traefik might be routing to port 80 on the host instead of port 2283 on the container.

6. **Investigate Coolify v4 beta + Traefik compatibility** — the beta may have a bug where it doesn't properly generate Traefik configuration for Docker Compose services, or where it generates conflicting Caddy+Traefik labels.
