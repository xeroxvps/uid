# Xerox UID v2

## Termux (Android) — one-line full setup

Run this **inside Termux** on Android:

```bash
pkg install -y curl && curl -fsSLo "$HOME/install-xrixuid.sh" https://raw.githubusercontent.com/xeroxvps/uid/main/install-termux.sh && bash "$HOME/install-xrixuid.sh"
```

Installer downloads the source ZIP and the optimized source patch from this repo, extracts selected source files (excluding archived `.git`, local secrets, runtime data and build artifacts), installs Node.js/pnpm/PostgreSQL, creates a private `.env.termux`, initializes the database, builds both apps, and starts the server.

Open **http://127.0.0.1:3000** on the same phone after successful setup.

To run again after restarting Termux:

```bash
cd ~/xrixuid && source .env.termux && pg_ctl -D "$PREFIX/var/lib/postgresql" status >/dev/null 2>&1 || pg_ctl -D "$PREFIX/var/lib/postgresql" -l "$HOME/xrixuid-postgres.log" start
cd ~/xrixuid && source .env.termux && pnpm run start:deploy
```

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
