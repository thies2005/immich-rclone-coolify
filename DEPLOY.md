# How to Deploy on Coolify

Step-by-step guide for deploying this Immich + Internxt stack to Coolify, with screenshots-like navigation of the Coolify UI.

---

## Before You Start

- Have your **Internxt account credentials** ready (email, password, and TOTP secret if 2FA is enabled)
- Generate a **strong random password** for the Immich database (you'll use this as `DB_PASSWORD`)
- If your Internxt account uses 2FA, have your **TOTP secret** ready (see below for how to get it)

> **What is a TOTP secret?** When you set up 2FA on your Internxt account, you scanned a QR code with your authenticator app. Inside that QR code is a `secret=` parameter — a base32 string like `JBSWY3DPEHPK3PXP`. This is NOT a one-time code from your app; it's the permanent secret key that generates new codes every 30 seconds. If you lost it, you must disable and re-enable 2FA on your Internxt account to get a new one.

---

## Step 1: Create a New Resource

1. Log in to your Coolify instance
2. Go to your **Project** (or create a new one)
3. Click **New Resource**
4. Select **Docker Compose (from GitHub)**
5. In the repository search box, type: `thies2005/immich-rclone-coolify`
6. Click the repository when it appears
7. Click **Continue**

The repository will be cloned by Coolify during the first deploy. No need to fork it first — Coolify builds directly from this public repo.

---

## Step 2: Configure the Resource

You'll now see the resource configuration screen. Go through each section:

### General Settings

- **Name**: Enter a name (e.g. `immich-internxt`)
- **Domain**: Leave this empty for now, or enter your desired Immich URL (e.g. `photos.yourdomain.com`). Coolify will handle the reverse proxy.
- **Build Context**: Should be blank (defaults to repo root). The `docker-compose.yml` is in the root directory.
- **Environment Variables**: This is where you'll add all the configuration.

### Add Environment Variables

Click the **Add Variable** button and add each required variable one by one:

| Variable Name | Value to Type | Example Value | Required |
|---|---|---|---|
| `INTERNXT_EMAIL` | Your Internxt email | `you@domain.com` | ✅ Yes |
| `INTERNXT_PASSWORD` | Your Internxt password | `your-internxt-password` | ✅ Yes |
| `INTERNXT_TOTP_SECRET` | Base32 TOTP secret (only if 2FA enabled) | `JBSWY3DPEHPK3PXP` | Optional |
| `DB_PASSWORD` | Strong random password | `a-very-strong-p@ssw0rd!` | ✅ Yes |

After adding the 4 required variables, you can stop here. Everything else has working defaults.

> **Pro tip:** Click **Reveal Value** after adding to verify you typed it correctly.

### Optional Variables (Advanced)

Add these only if you want to customize defaults:

| Variable Name | Default | When to Change |
|---|---|---|
| `INTERNXT_REMOTE_NAME` | `MyInternxt` | If you want a custom remote name |
| `IMMICH_VERSION` | `v2` | Pin a specific version like `v2.1.0` |
| `RCLONE_VFS_CACHE_MAX_SIZE` | `8G` | Reduce to `4G` if disk is tight |
| `RCLONE_DIR_CACHE_TIME` | `5m` | Increase to `30m` to reduce API calls |
| `RCLONE_TIMEOUT` | `120s` | Increase to `300s` for slow connections |

### Verify Your Variables

After adding all variables, review the list:
- All required variables should show a ✅ checkmark or similar indicator
- Click any variable to edit if you need to change it

---

## Step 3: Deploy

1. Scroll to the bottom of the configuration screen
2. Click the big **Deploy** button
3. You'll see a deployment progress screen with build logs

### What Happens During Deployment

| Phase | What You See | Duration |
|---|---|---|
| Clone repository | "Cloning repository..." | ~10 seconds |
| Build rclone image | "Building image..." (Go compilation) | 3–5 minutes |
| Pull Immich images | "Pulling image..." (Immich, postgres, valkey) | 1–2 minutes |
| Create volumes | "Creating volume..." | ~5 seconds |
| Start containers | "Starting container..." | ~10 seconds |
| rclone healthcheck | Healthcheck retries in logs | 30–90 seconds |
| Immich startup | "Immich is starting..." | ~30 seconds |

**Total first deploy time: 5–10 minutes**

The rclone build takes the longest because it compiles Go source code from the custom fork. Subsequent deployments will be faster (the built image is cached).

---

## Step 4: Wait for Healthy Status

After deployment completes, monitor the service status:

1. Go to the resource dashboard for your Immich stack
2. Watch the status indicators:
   - **rclone**: Green checkmark ✅ (mount is active and healthy)
   - **immich-server**: Green checkmark ✅ (web interface is accessible)
   - **postgres**: Green checkmark ✅ (database is running)
   - **redis**: Green checkmark ✅ (cache is running)
   - **immich-machine-learning**: Green checkmark ✅ (AI features are ready)

If any service shows a red ❌ or yellow ⚠️, click it to view logs.

---

## Step 5: Configure Coolify Reverse Proxy (Optional)

If you didn't set a domain in Step 2, do it now:

1. Go to the resource dashboard
2. Click on the **immich-server** service
3. Click **Edit** or **Configure**
4. Scroll to the **Domains** section
5. Enter your domain (e.g. `photos.yourdomain.com`)
6. Click **Update** or **Save Changes**

Coolify will automatically:
- Generate a free Let's Encrypt SSL certificate
- Configure Traefik to route traffic to port `2283`
- Apply the domain to the Immich web interface

---

## Step 6: Access Immich and Create Admin

1. Open your browser and go to your domain (or Coolify's direct URL)
2. You should see the Immich login screen
3. Click **Sign Up** to create your admin account
4. Enter your email and password
5. Complete the onboarding wizard

Your admin account is now created locally — this is stored in the Immich database, not on any external service.

---

## Step 7: Add the External Library

1. Log in to Immich as the admin account
2. Click the **User icon** in the bottom-left corner
3. Select **Administration**
4. Go to **External Libraries** (in the left sidebar)
5. Click **Create Library**
6. Fill in:
   - **Name**: `Internxt Photos` (or any name you want)
   - **Import Paths**: `/mnt/external-library`
7. Click **Create Library**
8. Click the **Scan** button for your new library

### First Scan Behavior

The first scan will be **slow**. Here's what's happening:

| What Immich Does | Time per Photo | Total for 10k Photos |
|---|---|---|
| Requests file list from rclone | <1 second | ~10 seconds |
| rclone downloads file from Internxt | 2–5 seconds | 5–14 hours (E2E decrypt is slow) |
| rclone decrypts file (E2E) | 1–2 seconds | 3–6 hours |
| Immich reads metadata | <1 second | ~3 hours |
| Immich generates thumbnail | 2–5 seconds | 6–28 hours (in parallel) |

**Total first scan: 2–4 hours** for 10,000 photos. This is expected due to Internxt's end-to-end encryption. Every file must be fully downloaded and decrypted before Immich can read it.

### Subsequent Scans

After the first scan completes, subsequent scans are much faster:
- Only changed or new files are re-downloaded
- Directory listings are cached by rclone
- Thumbnails are already generated
- **Typical incremental scan: 5–15 minutes** for 10k photos

---

## Step 8: Upload Your First Photos

1. In Immich, click the **+** button or drag photos to upload
2. Photos are uploaded to the **Immich upload volume** (stored locally)
3. After upload, Immich processes them (thumbnails, face detection, etc.)
4. You can now browse both:
   - **Local uploads** — stored on your Coolify host
   - **External library** — mounted from Internxt

Your photo library is now a hybrid: some photos stored locally, others served from Internxt encrypted storage.

---

## Monitoring Your Deployment

### Check Logs

In Coolify, go to your resource → click any service → **Logs** tab:

| Service | What to Look For | Normal Behavior |
|---|---|---|
| **rclone** | "Generating rclone.conf", "Starting rclone mount", "mount is healthy" | Occurs on every start |
| **immich-server** | "Immich is starting", "Listening on port 2283" | Occurs on every start |
| **postgres** | "database system is ready to accept connections" | Occurs on every start |
| **redis** | "Ready to accept connections" | Occurs on every start |

### Monitor Disk Usage

In Coolify, go to **Servers → select your server → Storage**:

| Volume | Size Check | Alert If Exceeds |
|---|---|---|
| `immich-rclone-coolify_postgres_data` | <5 GB | >8 GB |
| `immich-rclone-coolify_rclone_cache` | <8 GB | >12 GB (this should never happen due to hard cap) |
| `immich-rclone-coolify_upload_data` | <6 GB | >10 GB |
| `immich-rclone-coolify_ml_cache` | <4 GB | >6 GB |

---

## Troubleshooting Common Issues

### "Deploy failed to build"

- **Cause**: GitHub is slow or rclone build failed
- **Fix**: Click **Redeploy** with **Force Rebuild** enabled. Check the build logs for specific errors.

### "rclone service keeps restarting"

- **Cause**: Wrong Internxt credentials or TOTP secret
- **Fix**:
  1. Check rclone logs in Coolify
  2. Look for "authentication failed" or "invalid totp_secret"
  3. Update `INTERNXT_EMAIL`, `INTERNXT_PASSWORD`, or `INTERNXT_TOTP_SECRET` in Coolify
  4. Redeploy

### "FUSE mount not found"

- **Cause**: `/dev/fuse` is missing on the host
- **Fix**: This is extremely rare. Run `sudo modprobe fuse` on the Coolify host. Most modern Linux kernels have this built-in.

### "Cannot access external library"

- **Cause**: FUSE mount propagation issue
- **Fix**:
  1. Check the `docker-compose.yml` hasn't been edited
  2. Verify the bind mount uses `propagation: shared` for rclone and `propagation: slave` for immich-server
  3. Redeploy

### "Scan takes forever"

- **Cause**: Normal for first scan with E2E encryption
- **Fix**: Nothing to fix. Let it run. Check progress in Immich's External Libraries section (shows number of files processed).

---

## Updating Your Deployment

### Change Internxt Password

1. Change your password on the Internxt website
2. Go to Coolify → Edit your resource
3. Update `INTERNXT_PASSWORD`
4. Click **Deploy**
5. rclone will use the new password on next container restart

### Enable 2FA on Your Internxt Account

1. Enable 2FA on the Internxt website
2. Save the **TOTP secret** (the `secret=` value from the QR code)
3. Go to Coolify → Edit your resource
4. Add `INTERNXT_TOTP_SECRET` with the secret value
5. Click **Deploy**

### Change Immich Admin Password

1. Log in to Immich
2. Go to **Administration → Users**
3. Click on your admin account
4. Change password locally (this is separate from `DB_PASSWORD`)

### Scale Up for More Storage

1. In Coolify, go to **Servers → Select your server**
2. Increase disk allocation
3. Redeploy (Coolify will recreate volumes if path mapping changes)

---

## Next Steps After Deployment

- [ ] Configure Immich backup (separate from this external library setup)
- [ ] Set up Immich mobile app (point to your Coolify domain)
- [ ] Configure Immich photo sharing (enable public galleries)
- [ ] Monitor rclone cache usage over first week (watch `rclone_cache` volume)
- [ ] Tune `RCLONE_VFS_CACHE_MAX_SIZE` if cache is too small/large

---

## Need Help?

- Check [`COOLIFY-SETUP.md`](COOLIFY-SETUP.md) for detailed troubleshooting
- Review [`ENV-VARIABLES.md`](ENV-VARIABLES.md) for all configuration options
- Open an issue on [GitHub](https://github.com/thies2005/immich-rclone-coolify/issues)
