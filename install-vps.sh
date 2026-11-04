#!/usr/bin/env bash
# Xerox UID — Ubuntu/Debian VPS deployment (run as root).
# Extracts xrixuid.zip, builds a detected frontend, and runs a Python API via systemd.
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

REPO="https://github.com/xeroxvps/uid.git"
ROOT="/opt/xrixuid"
SRC="$ROOT/repo/unpacked"
WWW="/var/www/xrixuid"
USER_NAME="xrixuid"
PORT="${PORT:-8088}"
API_PORT="${API_PORT:-18088}"

say() { printf '\n[Xerox UID] %s\n' "$*"; }
die() { echo "[ERROR] $*" >&2; exit 1; }
trap 'echo "[ERROR] Failure at line $LINENO" >&2' ERR

[[ "$EUID" -eq 0 ]] || die "Use: sudo bash install-vps.sh"
[[ -d /run/systemd/system ]] || die "A systemd-enabled Ubuntu/Debian VPS is required"
[[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1024 && PORT <= 65535 )) || die "Invalid PORT"
[[ "$API_PORT" =~ ^[0-9]+$ ]] && (( API_PORT >= 1024 && API_PORT <= 65535 )) || die "Invalid API_PORT"
[[ "$PORT" != "$API_PORT" ]] || die "PORT and API_PORT must differ"

say "Installing system dependencies"
apt-get update
apt-get install -y git python3 python3-venv python3-pip python3-dev nginx curl unzip ca-certificates build-essential
id "$USER_NAME" &>/dev/null || useradd --system --user-group --shell /usr/sbin/nologin --home-dir "$ROOT" "$USER_NAME"
mkdir -p "$ROOT" "$WWW"
if [[ -d "$ROOT/repo/.git" ]]; then
  git -C "$ROOT/repo" fetch --depth=1 origin main
  git -C "$ROOT/repo" reset --hard FETCH_HEAD
else
  git clone --depth=1 --branch main "$REPO" "$ROOT/repo"
fi
cd "$ROOT/repo"
unzip -tqq xrixuid.zip || die "ZIP is corrupt"
say "Validating and extracting ZIP"
python3 scripts/extract_zip.py xrixuid.zip unpacked
[[ -d "$SRC" ]] || die "Extraction failed"

# Find a Python app without importing or running untrusted files at detection time.
BACKEND_FILE=""
while IFS= read -r p; do
  if grep -Eq 'FastAPI\(|Flask\(' "$p"; then BACKEND_FILE="$p"; break; fi
done < <(find "$SRC" -maxdepth 7 -type f \( -name app.py -o -name main.py \) \
  -not -path "*/node_modules/*" -not -path "*/.venv/*" | sort)
if [[ -z "$BACKEND_FILE" && -f "$ROOT/repo/backend/app.py" ]]; then
  BACKEND_FILE="$ROOT/repo/backend/app.py"
  say "No app in archive; using repository's basic API skeleton"
fi

# Detect frontend build from package.json. Also support a prebuilt static index.html.
FRONT=""
while IFS= read -r p; do
  if grep -Eq '"build"[[:space:]]*:' "$p"; then FRONT="$(dirname "$p")"; break; fi
done < <(find "$SRC" -maxdepth 7 -name package.json -type f \
  -not -path "*/node_modules/*" | sort)
if [[ -n "$FRONT" ]]; then
  say "Building frontend in $FRONT"
  curl -fsSL --retry 3 https://deb.nodesource.com/setup_22.x -o /tmp/xrixuid-node-setup.sh
  bash /tmp/xrixuid-node-setup.sh
  apt-get install -y nodejs
  chown -R "$USER_NAME:$USER_NAME" "$SRC"
  if [[ ! -f "$FRONT/.env.production" ]]; then
    printf 'VITE_API_URL=/api\nVITE_API_BASE_URL=/api\n' > "$FRONT/.env.production"
    chown "$USER_NAME:$USER_NAME" "$FRONT/.env.production"
  fi
  if [[ -f "$FRONT/package-lock.json" ]]; then
    runuser -u "$USER_NAME" -- sh -c 'cd "$1" && npm ci --no-audit --no-fund' sh "$FRONT"
  else
    runuser -u "$USER_NAME" -- sh -c 'cd "$1" && npm install --no-audit --no-fund' sh "$FRONT"
  fi
  runuser -u "$USER_NAME" -- sh -c 'cd "$1" && npm run build' sh "$FRONT"
  for d in "$FRONT/dist" "$FRONT/build"; do
    if [[ -f "$d/index.html" ]]; then cp -a "$d/." "$WWW/"; break; fi
  done
else
  while IFS= read -r p; do
    if [[ "$p" == */dist/index.html || "$p" == */build/index.html ]]; then
      cp -a "$(dirname "$p")/." "$WWW/"
      say "Copied existing static site"
      break
    fi
  done < <(find "$SRC" -maxdepth 7 -name index.html -type f | sort)
fi

if [[ -n "$BACKEND_FILE" ]]; then
  say "Configuring Python API: $BACKEND_FILE"
  BACKEND_DIR="$(dirname "$BACKEND_FILE")"
  MOD="$(basename "$BACKEND_FILE" .py)"
  python3 -m venv "$ROOT/venv"
  "$ROOT/venv/bin/pip" install --upgrade pip
  if [[ -f "$BACKEND_DIR/requirements.txt" ]]; then
    "$ROOT/venv/bin/pip" install -r "$BACKEND_DIR/requirements.txt"
  fi
  if grep -q 'Flask(' "$BACKEND_FILE" && ! grep -q 'FastAPI(' "$BACKEND_FILE"; then
    "$ROOT/venv/bin/pip" install gunicorn flask
    CMD="$ROOT/venv/bin/gunicorn --workers 2 --bind 127.0.0.1:$API_PORT $MOD:app"
  else
    "$ROOT/venv/bin/pip" install fastapi uvicorn
    CMD="$ROOT/venv/bin/uvicorn $MOD:app --host 127.0.0.1 --port $API_PORT"
  fi
  chown -R "$USER_NAME:$USER_NAME" "$ROOT" "$WWW"
  cat >/etc/systemd/system/xrixuid-api.service <<SERVICE
[Unit]
Description=Xerox UID API
After=network-online.target
Wants=network-online.target
[Service]
User=$USER_NAME
Group=$USER_NAME
WorkingDirectory=$BACKEND_DIR
Environment=PYTHONUNBUFFERED=1
Environment=ENVIRONMENT=production
Environment=DATABASE_URL=sqlite:////opt/xrixuid/xerox_uid.db
ExecStart=$CMD
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ReadWritePaths=$ROOT
[Install]
WantedBy=multi-user.target
SERVICE
  systemctl daemon-reload
  systemctl enable --now xrixuid-api
fi

if [[ ! -f "$WWW/index.html" && -z "$BACKEND_FILE" ]]; then
  die "No runnable frontend or Python backend identified in ZIP. Check app structure."
fi

if [[ -f "$WWW/index.html" ]]; then
  ROOT_ROUTE='try_files $uri $uri/ /index.html;'
else
  ROOT_ROUTE="proxy_pass http://127.0.0.1:$API_PORT;"
fi

cat >/etc/nginx/sites-available/xrixuid <<NGINX
server {
    listen $PORT;
    server_name _;
    root $WWW;
    index index.html;
    client_max_body_size 30m;
    location /api/ {
        proxy_pass http://127.0.0.1:$API_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    location / {
        $ROOT_ROUTE
    }
}
NGINX
ln -sfn /etc/nginx/sites-available/xrixuid /etc/nginx/sites-enabled/xrixuid
nginx -t
systemctl enable --now nginx
systemctl reload nginx
if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then
  ufw allow "$PORT/tcp"
fi
say "Deployment finished. Open http://YOUR_VPS_IP:$PORT"
say "API logs: journalctl -u xrixuid-api -f"
say "For public deployment, add HTTPS and authentication before using private UID data."
