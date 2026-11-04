#!/data/data/com.termux/files/usr/bin/bash
# XRIXUID Termux background manager. Run with start|stop|restart|status|logs|attach|foreground
set -Eeuo pipefail

APP="$HOME/xrixuid"
SCRIPT="$APP/run-termux.sh"
SESSION="xrixuid-server"
PGDATA="$PREFIX/var/lib/postgresql"
LOG="$HOME/xrixuid-server.log"
PGLOG="$HOME/xrixuid-postgres.log"

info() { printf '[XRIXUID] %s\n' "$*"; }
die() { printf '[XRIXUID] ERROR: %s\n' "$*" >&2; exit 1; }

ensure_project() {
  [[ -d "$APP" && -f "$APP/.env.termux" ]] ||
    die "Project not installed at $APP. Run install-termux.sh first."
}

ensure_database() {
  command -v pg_ctl >/dev/null 2>&1 || die 'PostgreSQL is not installed.'
  [[ -f "$PGDATA/PG_VERSION" ]] || die 'PostgreSQL is not initialized. Run full setup first.'
  if ! pg_ctl -D "$PGDATA" status >/dev/null 2>&1; then
    info 'Starting PostgreSQL...'
    pg_ctl -D "$PGDATA" -l "$PGLOG" start
  fi
}

is_running() { tmux has-session -t "=$SESSION" 2>/dev/null; }

case "${1:-start}" in
  start)
    ensure_project
    command -v tmux >/dev/null 2>&1 || die 'Install tmux: pkg install tmux -y'
    if is_running; then
      info 'Already running in tmux.'
      info 'Website: http://127.0.0.1:3000'
      exit 0
    fi
    ensure_database
    command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock >/dev/null 2>&1 || true
    [[ -f "$SCRIPT" ]] || die "Missing $SCRIPT"
    info 'Starting background tmux session...'
    tmux new-session -d -s "$SESSION" -c "$APP" "bash '$SCRIPT' foreground"
    sleep 2
    if is_running; then
      info 'Server session running.'
      info 'Website: http://127.0.0.1:3000'
      info "Logs: bash $SCRIPT logs"
      info 'You may minimize Termux or detach; do not Force Stop the Android app.'
    else
      info 'Server quit during startup. Most recent output:'
      tail -n 30 "$LOG" 2>/dev/null || true
      exit 1
    fi
    ;;
  foreground)
    ensure_project
    cd "$APP"
    # shellcheck disable=SC1091
    source .env.termux
    info 'Starting XRIXUID (foreground inside tmux)...' >> "$LOG"
    exec pnpm run start:deploy >> "$LOG" 2>&1
    ;;
  stop)
    command -v tmux >/dev/null 2>&1 || die 'tmux is not installed.'
    if is_running; then
      tmux kill-session -t "=$SESSION"
      info 'Stopped XRIXUID tmux server.'
    else
      info 'XRIXUID tmux server was not running.'
    fi
    ;;
  restart)
    bash "$0" stop
    bash "$0" start
    ;;
  status)
    command -v tmux >/dev/null 2>&1 || die 'tmux is not installed.'
    if is_running; then
      info 'tmux process: RUNNING'
    else
      info 'tmux process: STOPPED'
    fi
    if command -v curl >/dev/null 2>&1; then
      http_code="$(curl --max-time 3 -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/ || true)"
      info "HTTP status: ${http_code:-unreachable}"
    fi
    ;;
  logs)
    [[ -f "$LOG" ]] || die "No logs yet. Run: bash $SCRIPT start"
    tail -n 80 "$LOG"
    ;;
  attach)
    command -v tmux >/dev/null 2>&1 || die 'tmux is not installed.'
    tmux attach-session -t "=$SESSION"
    ;;
  *)
    echo "Usage: bash $SCRIPT {start|stop|restart|status|logs|attach}"
    exit 2
    ;;
esac
