#!/data/data/com.termux/files/usr/bin/sh
# install-service.sh — manage the watchdog v1 runit service (runsv instance).
#
# Design note (2026-09-13): termux-services' own aggregator (runsvdir via
# service-daemon) was observed to die immediately on this device, while
# individual runsv instances survive session teardown. This installer therefore
# launches ONE dedicated `runsv <service-dir>` instance via start-stop-daemon
# and records its PID. `sv status/up/down` still works (it talks to the
# service's supervise/ socket; runsvdir is not required for that).
# The service wraps the existing watchdog.sh (v0) — no sealed script is modified.
set -e
SVC=shizuku-watchdog
SRC="$(cd "$(dirname "$0")" && pwd)/service/$SVC"
USR="${PREFIX:-/data/data/com.termux/files/usr}"
DST="$USR/var/service/$SVC"
PIDFILE="$USR/var/run/$SVC.runsv.pid"
RUNSV="$USR/bin/runsv"

running() {
  [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

case "${1:-install}" in
  install)
    [ -f "$SRC/run" ] || { echo "FAIL: missing $SRC/run"; exit 2; }
    mkdir -p "$DST"
    cp "$SRC/run" "$DST/run"
    chmod 755 "$DST/run"
    echo "installed: $DST (copy of repo service/$SVC/run)"
    echo "next: $0 start   (then: sv status $SVC)"
    ;;
  start)
    command -v runsv >/dev/null 2>&1 || {
      echo "FAIL: runsv missing. Run: pkg install termux-services"; exit 2; }
    if running; then
      echo "already running (runsv pid $(cat "$PIDFILE"))"
    else
      start-stop-daemon -S -b -m -p "$PIDFILE" -x "$RUNSV" -- "$DST"
      sleep 2
      echo "runsv pid: $(cat "$PIDFILE")"
    fi
    # NOTE: in non-login shells SVDIR is unset; use the full path form of sv:
    echo "control (full path, works in any shell): sv status \"$DST\""
    ;;
  stop)
    sv down "$SVC" 2>/dev/null || true
    if [ -f "$PIDFILE" ]; then
      start-stop-daemon -K -p "$PIDFILE" 2>/dev/null || true
      rm -f "$PIDFILE"
    fi
    echo "stopped"
    ;;
  uninstall)
    "$0" stop || true
    rm -rf "$DST"
    echo "uninstalled: $DST"
    ;;
  *)
    echo "usage: $0 [install|start|stop|uninstall]"
    exit 1
    ;;
esac
