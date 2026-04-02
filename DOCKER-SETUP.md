# Docker Standalone Deployment — Setup Guide

Deploy Immich directly with Docker Compose (no Coolify required).

---

## Prerequisite: Install rclone on the Host

SSH into your server once and run:

```bash
git clone -b host-rclone https://github.com/thies2005/immich-rclone-coolify.git
cd immich-rclone-coolify
sudo bash install.sh
```

This builds rclone, sets up your Internxt credentials, and creates a systemd service that auto-mounts on boot. See the [README](README.md) for details.

Verify the mount is working:

```bash
ls /mnt/immich-external-library
```

If you see your Internxt files, proceed.

---

## Step 1: Configure Environment

```bash
cd immich-rclone-coolify
cp .env.example .env
```

Edit `.env` and set at minimum:

```env
DB_PASSWORD=a-strong-random-password
```

Generate one with: `openssl rand -hex 24`

See [`.env.example`](.env.example) and [`ENV-VARIABLES.md`](ENV-VARIABLES.md) for all available variables.

---

## Step 2: Choose a Reverse Proxy (Optional)

By default Immich is accessible on **port 2283** via plain HTTP. For HTTPS, choose one of the three options below. Only enable **one** proxy option.

### Option A: Caddy (automatic HTTPS)

Best for: servers with a public IP and a domain name.

1. In `.env`, set:
   ```env
   DOMAIN=photos.example.com
   CADDY_ACME_EMAIL=admin@example.com
   ```
2. Create a DNS **A record** pointing `photos.example.com` to your server's public IP
3. In `docker-compose.standalone.yml`:
   - **Comment out** the `ports:` section under `immich-server`
   - **Uncomment** the entire `caddy` service block
   - **Uncomment** `caddy_data` and `caddy_config` in the `volumes:` section
4. Caddy automatically provisions and renews Let's Encrypt certificates

### Option B: Cloudflare Tunnel

Best for: hiding your server's IP, no open ports needed.

1. Go to [Cloudflare Zero Trust](https://one.dash.cloudflare.com) and create a tunnel
2. Set the public hostname to your domain and the service URL to `http://immich-server:2283`
3. Copy the tunnel token
4. In `.env`, set:
   ```env
   CLOUDFLARE_TOKEN=your-tunnel-token
   ```
5. In `docker-compose.standalone.yml`:
   - **Comment out** the `ports:` section under `immich-server`
   - **Uncomment** the entire `cloudflared` service block

### Option C: Tailscale Serve

Best for: private access, no public domain needed, works behind NAT/CGNAT.

1. Install [Tailscale](https://tailscale.com) on the host and log in
2. Generate an auth key at [Tailscale admin](https://login.tailscale.com/admin/settings/keys) (check "Reusable")
3. In `.env`, set:
   ```env
   TS_AUTHKEY=tskey-auth-your-key-here
   ```
4. In `docker-compose.standalone.yml`:
   - **Comment out** the `ports:` section under `immich-server`
   - **Uncomment** the entire `tailscale` service block
   - **Uncomment** `ts_state` in the `volumes:` section
5. After starting, check your tailnet URL:
   ```bash
   docker exec immich-tailscale tailscale status
   ```
6. Optionally enable HTTPS via Tailscale's built-in certificates:
   ```bash
   docker exec immich-tailscale tailscale cert immich
   ```

### No Proxy (plain HTTP)

Skip this section entirely. Immich will be available at `http://your-server-ip:2283`. You can change the port with `IMMICH_PORT=8080` in `.env`.

---

## Step 3: Start

```bash
docker compose -f docker-compose.standalone.yml up -d
```

First start takes 1-2 minutes (pulling images). Watch the logs:

```bash
docker compose -f docker-compose.standalone.yml logs -f
```

- **immich-microservices**: Runs DB migrations
- **immich-server**: Starts API + web UI
- **immich-machine-learning**: Starts in parallel

---

## Step 4: Post-Deploy — Immich Setup

### Create Admin Account

Open your URL in a browser:
- **No proxy**: `http://your-server-ip:2283`
- **Caddy**: `https://photos.example.com`
- **Cloudflare Tunnel**: your configured public hostname
- **Tailscale**: your tailnet URL from `tailscale status`

Create the admin account.

### Register the External Library

1. Go to **Administration -> External Libraries**
2. Click **Create Library**
3. Set the **Import Path** to `/mnt/external-library`
4. Save -> Click **Scan**

> **First scan is slow** -- every file downloads from Internxt and decrypts through E2E. 10k photos may take 2-4 hours. Subsequent scans are fast.

---

## Useful Commands

### Check status

```bash
docker compose -f docker-compose.standalone.yml ps
sudo systemctl status immich-rclone       # rclone service
ls /mnt/immich-external-library           # verify mount
```

### View logs

```bash
docker compose -f docker-compose.standalone.yml logs -f immich-server
docker compose -f docker-compose.standalone.yml logs -f immich-microservices
journalctl -u immich-rclone -f            # rclone systemd logs
tail -f /var/log/immich-rclone/rclone.log # rclone file log
```

### Restart

```bash
docker compose -f docker-compose.standalone.yml restart
```

### Stop everything

```bash
docker compose -f docker-compose.standalone.yml down
```

### Update Immich

```bash
docker compose -f docker-compose.standalone.yml pull
docker compose -f docker-compose.standalone.yml up -d
```

### Update rclone

```bash
sudo bash install.sh
```

### Full uninstall

```bash
docker compose -f docker-compose.standalone.yml down -v
sudo systemctl stop immich-rclone
sudo systemctl disable immich-rclone
sudo rm /etc/systemd/system/immich-rclone.service
sudo rm -rf /opt/immich-rclone /etc/immich-rclone /var/cache/immich-rclone /var/log/immich-rclone
sudo systemctl daemon-reload
rm .env
```

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

If the host mount works but containers don't see it, restart:

```bash
docker compose -f docker-compose.standalone.yml restart
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
# Change RCLONE_VFS_CACHE_MAX_SIZE=16G
sudo systemctl restart immich-rclone
```

### Slow scans

- **First scan is always slow** -- E2E encryption requires full file download.
- Subsequent scans only re-download changed files.
- To tune: edit `/etc/immich-rclone/mount.env` and adjust `RCLONE_DIR_CACHE_TIME`, `RCLONE_TRANSFERS`, etc.

### Caddy fails to get certificates

- Verify DNS A record points to your server: `dig photos.example.com`
- Check that ports 80 and 443 are open and not blocked by a firewall
- Check Caddy logs: `docker compose -f docker-compose.standalone.yml logs -f caddy`

### Cloudflare Tunnel not connecting

- Verify the token is valid (re-generate if unsure)
- Check cloudflared logs: `docker compose -f docker-compose.standalone.yml logs -f cloudflared`
- Make sure the tunnel is configured to point to `http://immich-server:2283`

### Tailscale not connecting

- Verify auth key is valid and not expired
- Check Tailscale logs: `docker compose -f docker-compose.standalone.yml logs -f tailscale`
- Make sure `/dev/net/tun` exists on the host: `ls -la /dev/net/tun`

### Update Internxt credentials

```bash
sudo nano /etc/immich-rclone/rclone.conf
sudo systemctl restart immich-rclone
```

Or re-run the install script -- it preserves your settings:

```bash
sudo bash install.sh
```
