#!/data/data/com.termux/files/usr/bin/bash
# XRIXUID Termux installer — original source archive + optimized patch.
set -Eeuo pipefail
REPO='https://raw.githubusercontent.com/xeroxvps/uid/main'
log() { printf '\n\033[1;36m[XRIXUID]\033[0m %s\n' "$*"; }
fail() { printf '\n\033[1;31m[XRIXUID ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
trap 'printf "\nXRIXUID setup failed (line %s). Check the error above.\n" "$LINENO" >&2' ERR
[[ -n "${PREFIX:-}" && -x "$PREFIX/bin/pkg" ]] || fail 'Run directly inside Termux (not Ubuntu/proot).'
log 'Installing dependencies...'
pkg update -y
pkg install -y curl python git nodejs postgresql
command -v pnpm >/dev/null 2>&1 || npm install -g pnpm

WORK="$(mktemp -d "${TMPDIR:-$PREFIX/tmp}/xrixuid.XXXXXXXX")"
trap 'rm -rf "$WORK"' EXIT
log 'Downloading XRIXUID source and optimization patch...'
curl -fL --retry 3 "$REPO/xrixuid.zip" -o "$WORK/project.zip"
curl -fL --retry 3 "$REPO/patches/xrixuid-optimized.patch.br.b64" -o "$WORK/patch.br.b64"

python - "$WORK/project.zip" "$WORK/xrixuid" <<'PY'
import pathlib, stat, sys, zipfile
source, target = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
root_files = {'.npmrc', '.gitignore', 'README.md', 'package.json', 'pnpm-lock.yaml',
              'pnpm-workspace.yaml', 'tsconfig.json', 'tsconfig.base.json',
              'render.yaml', 'replit.md', 'replit.nix'}
denied = {'dist', 'build', 'node_modules', '.git', '.env', '.venv', '.cache',
          '__pycache__', '.local', 'tmp', 'coverage'}
def allowed(name):
    p = pathlib.PurePosixPath(name)
    if p.is_absolute() or '..' in p.parts or len(p.parts) == 0: return False
    if name in root_files: return True
    if p.parts[0] not in {'artifacts', 'lib', 'scripts'}: return False
    return not any(x in denied for x in p.parts) and not name.endswith(('.tsbuildinfo', '.zip', '.migrated'))
total, count = 0, 0
with zipfile.ZipFile(source) as archive:
    for item in archive.infolist():
        name = item.filename
        if not name.startswith('xrixuid/') or item.is_dir(): continue
        rel = name[len('xrixuid/'):]
        if not allowed(rel): continue
        if stat.S_IFMT(item.external_attr >> 16) == stat.S_IFLNK:
            raise SystemExit('Refusing archive symlink: ' + name)
        if item.file_size > 20_000_000: raise SystemExit('Unexpected large file: ' + name)
        total += item.file_size
        if total > 100_000_000: raise SystemExit('Unexpected archive size')
        path = target / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(archive.read(item))
        count += 1
if count < 150: raise SystemExit(f'Incomplete source archive ({count} files)')
print(f'Extracted {count} selected files')
PY

node - "$WORK/patch.br.b64" "$WORK/optimized.patch" <<'JS'
const fs = require('fs');
const zlib = require('zlib');
fs.writeFileSync(process.argv[3], zlib.brotliDecompressSync(
  Buffer.from(fs.readFileSync(process.argv[2], 'utf8').trim(), 'base64')));
JS
(cd "$WORK/xrixuid" && git apply --check "$WORK/optimized.patch" && git apply "$WORK/optimized.patch")

log 'Enabling Android ARM64 native dependencies...'
python - "$WORK/xrixuid/pnpm-workspace.yaml" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); lines = p.read_text().splitlines()
p.write_text('\n'.join(line for line in lines
                     if not ('android-' in line and line.rstrip().endswith((': "-"', ": '-'")))) + '\n')
PY

mkdir -p "$HOME/xrixuid"
cp -R "$WORK/xrixuid/." "$HOME/xrixuid/"
cd "$HOME/xrixuid"

log 'Installing pnpm dependencies...'
pnpm install --no-frozen-lockfile

log 'Starting PostgreSQL...'
PGDATA="$PREFIX/var/lib/postgresql"
mkdir -p "$PGDATA"
if [[ ! -f "$PGDATA/PG_VERSION" ]]; then
    initdb -D "$PGDATA" --encoding=UTF8 --no-instructions
fi
pg_ctl -D "$PGDATA" status >/dev/null 2>&1 || pg_ctl -D "$PGDATA" -l "$HOME/xrixuid-postgres.log" start
if [[ "$(psql -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='xrixuid'")" != '1' ]]; then
    createdb xrixuid
fi

if [[ ! -f .env.termux ]]; then
    log 'Generating private local configuration...'
    umask 077
    ADMIN_KEY="$(python -c 'import secrets; print(secrets.token_urlsafe(32))')"
    printf 'export DATABASE_URL=%q\nexport ADMIN_KEY=%q\nexport NODE_ENV=production\nexport PORT=3000\n' \
       "postgresql://$(id -un)@127.0.0.1:5432/xrixuid" "$ADMIN_KEY" > .env.termux
fi
chmod 600 .env.termux
source .env.termux
log 'Creating database schema and building web/API...'
pnpm --filter @workspace/db run push
pnpm run build:deploy
log 'READY! Open http://127.0.0.1:3000; stop with Ctrl+C.'
log 'Start later: cd ~/xrixuid && source .env.termux && pnpm run start:deploy'
exec pnpm run start:deploy
