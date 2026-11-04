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
    # A tmux session existing does not mean the Node.js app is listening.
    # Wait briefly for an HTTP response, detecting an early exit immediately.
    ready=false
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      if ! is_running; then
        break
      fi
      http_code="$(curl -sS --max-time 1 -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/ 2>/dev/null || true)"
      if [[ "$http_code" =~ ^[1-5][0-9][0-9]$ ]]; then
        ready=true
        break
      fi
      sleep 1
    done
    if [[ "$ready" == true ]]; then
      info 'HTTP server responding.'
      info 'Website: http://127.0.0.1:3000'
      info "Logs: bash $SCRIPT logs"
      info 'Minimize Termux; do not Force Stop the Android app.'
    else
      info 'Server did not become ready. The tmux session may have exited.'
      info 'Latest server logs (look for Error, EADDRINUSE, module errors, signal 9):'
      tail -n 45 "$LOG" 2>/dev/null || true
      info "Full logs: bash $SCRIPT logs"
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
