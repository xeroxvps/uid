# Xerox UID v2

## Separate fetch backend on EthioDeploy

XRIXUID now supports a dedicated **second Web Service** while preserving the old frontend API response shape. Both services build from this repository's root `Dockerfile` (branch `main`, root `/`, HTTP port `3000`).

**1. Create the fetch service** (e.g. `uid-fetch`) on EthioDeploy using `xeroxvps/uid`. Add these runtime environment variables:

```env
XRIXUID_SERVICE_MODE=fetch
FETCH_BACKEND_TOKEN=<generate-a-unique-random-secret-of-at-least-24-characters>
PORT=3000
```

The fetch service exposes `GET /api/healthz` without a token, while `/api/fb/*` requires the token in `X-Fetch-Backend-Token`. It does **not** run PostgreSQL migrations, the admin API, or the frontend. No `DATABASE_URL` is necessary on this service.

**2. Connect the existing `uid` web service.** Add to its runtime environment:

```env
FETCH_BACKEND_URL=https://<your-fetch-service-hostname>
FETCH_BACKEND_TOKEN=<the-exact-same-random-secret-as-above>
```

Keep `DATABASE_URL` and `ADMIN_KEY` on the main service only. Redeploy **both** services after setting variables. For example, `https://<fetch-host>/api/healthz` should return `{"status":"ok","service":"xrixuid-fetch"}`; `https://<main-host>/api/fb/health` should return `{"status":"ok"}` after proxying.

The main website continues to send requests to `/api/fb/uid/fetch`; it forwards **only UIDs** to the fetch service. Client-provided cookies, passwords and the backend token are not exposed to the browser. The fetch service uses a bounded queue (one concurrent batch, eight waiting batches), the existing public metadata parser, and explicit detection of login-page / non-image responses. Login challenges are treated as missing data, **not** bypassed by switching cookies. `FETCH_COOKIE`, `FETCH_COOKIE1`, and `FETCH_COOKIE2` are not supported rotation settings.

**Security:** Keep the service token and any authorized account cookie out of Git and screenshots. The fetch service can be deployed without any cookie (public-data-only); any optional `FB_DEFAULT_COOKIE` must be used only when authorized. Stop or reduce batch lookups when third-party services respond with login challenges or rate limits.

**Limitations:** The queue is held in memory, so queued requests are lost if the container restarts. Cloud hosting provider timeouts and external website limits still apply. The build and deployment have not been confirmed on EthioDeploy; use provider build/runtime logs to diagnose failures.


## Deploy XRIXUID on Koyeb (free web service)

[Deploy XRIXUID to Koyeb](https://app.koyeb.com/deploy?type=git&builder=dockerfile&repository=github.com/xeroxvps/uid&branch=main&name=xrixuid&instance_type=free&ports=3000%3Bhttp%3B%2F&regions=fra)

The app is a full-stack Node/Express and React project, not a static site. The root `Dockerfile` extracts the source archive and applies the optimized patch during the image build.

1. Sign in to Koyeb with GitHub and authorize access to `xeroxvps/uid`. Click the deploy link above, or create a Web Service from GitHub and select **Dockerfile**, branch `main`, root work directory `.`.
2. Set **Free** web instance, **Frankfurt (fra)** region, **HTTP port 3000** with route `/`, and health check `/api/healthz`.
3. Create a separate PostgreSQL database before deploying. In Koyeb, select Databases → Create Database Service → Free. Koyeb's free DB is limited to **5 hours active compute per month**, so a separate Neon Free PostgreSQL database may be more appropriate for longer use.
4. On the web service's Environment Variables settings, add `DATABASE_URL` from your database provider and a **strong, unique** `ADMIN_KEY`. Never put passwords or the connection string in GitHub files or screenshots. `NODE_ENV=production` and `PORT=3000` are supplied by the Docker image.
5. Click Deploy. Open the generated `.koyeb.app` URL after the status becomes Healthy. Confirm `/api/healthz` responds with a JSON status. If it fails, check the Koyeb Build/Runtime logs.

*Free instances have significant CPU/RAM and idle-sleep limits; high-volume lookup workloads may be slow or fail. Successful deployment is not guaranteed until the build and HTTP health checks pass.*


## Termux (Android) — one-line full setup

Run this **inside Termux** on Android:

```bash
pkg install -y curl && curl -fsSLo "$HOME/install-xrixuid.sh" https://raw.githubusercontent.com/xeroxvps/uid/main/install-termux.sh && bash "$HOME/install-xrixuid.sh"
```

Installer downloads the source ZIP and the optimized source patch from this repo, extracts selected source files (excluding archived `.git`, local secrets, runtime data and build artifacts), installs Node.js/pnpm/PostgreSQL, creates a private `.env.termux`, initializes the database, builds both apps, and starts the server.

Open **http://127.0.0.1:3000** on the same phone after successful setup.

After a successful install, the launcher starts Node.js inside a detached `tmux` session. Leave Termux using the Android Home button; do not run `exit` inside the tmux server or Force Stop Termux. Android may still kill background processes under battery restrictions, and a phone reboot always requires a restart.

For an **existing installation** that already built successfully, activate the background manager without reinstalling:

```bash
pkg install -y tmux curl && curl -fsSLo "$HOME/xrixuid/run-termux.sh" https://raw.githubusercontent.com/xeroxvps/uid/main/run-termux.sh && bash "$HOME/xrixuid/run-termux.sh" start
```

Commands for later:

```bash
bash ~/xrixuid/run-termux.sh status
bash ~/xrixuid/run-termux.sh logs
bash ~/xrixuid/run-termux.sh stop
bash ~/xrixuid/run-termux.sh start
```

With a new Android session or after restarting the phone, run `bash ~/xrixuid/run-termux.sh start`. If you use `attach`, detach safely with `Ctrl+B`, then `D`. Keep Termux battery usage unrestricted when available.

The optimized changes are stored as a compressed source patch in `patches/xrixuid-optimized.patch.br.b64`; the unmodified original archive remains `xrixuid.zip`. This preserves the original source and makes the optimizations reproducible. The full Termux build must still be tested on a real Android device.


UID management web application.

## Source files

- `xrixuid.zip`: original application archive.
- `unpacked/`: extracted source, synced by the GitHub Actions ZIP workflow when it succeeds.
- `scripts/extract_zip.py`: path-checked, size-limited ZIP extractor. It skips common credential and local database files.
- `backend/`: original Python FastAPI foundation.
- `install-vps.sh`: Ubuntu/Debian VPS installer.

The ZIP extractor never runs archive code. The VPS installer *does* install dependencies and run the detected app, so review the project before deploying.

## Deploy to VPS from Android Termux

On Android:

```bash
pkg update -y
pkg install openssh -y
ssh root@YOUR_VPS_IP
```

Once connected to an **Ubuntu/Debian VPS with systemd**, run:

```bash
apt update && apt install -y curl
curl -fL https://raw.githubusercontent.com/xeroxvps/uid/main/install-vps.sh -o install-vps.sh
bash install-vps.sh
```

The installer downloads the repo, validates/extracts the ZIP to `/opt/xrixuid/repo/unpacked`, builds a detected React/Vite frontend if present, configures a detected FastAPI/Flask backend via systemd, and configures Nginx on port **8088**.

Open `http://YOUR_VPS_IP:8088` once the installer reports success. The VPS provider security group/firewall must allow inbound TCP 8088.

## Inspect service

```bash
systemctl status xrixuid-api --no-pager
journalctl -u xrixuid-api -n 100 --no-pager
nginx -t
curl -I http://127.0.0.1:8088
```

To change HTTP port, run `PORT=9090 bash install-vps.sh`.

**Notes:** The archive app layout may require environment-specific configuration; the project has not been run on your VPS. Do not expose private UID data on plain HTTP without HTTPS, authentication and proper access controls.

## Manual extraction from Termux if GitHub Actions does not start

```bash
pkg install git python -y
curl -fL https://raw.githubusercontent.com/xeroxvps/uid/main/termux-unpack-push.sh -o termux-unpack-push.sh
bash termux-unpack-push.sh
```

This syncs `xrixuid.zip` to `unpacked/` and commits the extracted files. GitHub push requires your own GitHub SSH key or personal access token configured in Termux. Review extracted files before making sensitive data public.
