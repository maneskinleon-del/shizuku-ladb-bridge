#!/system/bin/sh
# watchdog.sh — ladb-shizuku-recovery PoC :: watchdog v0
# Supervises shizuku_server through the dynamic LADB adb transport and,
# when the server is observed DOWN, delegates recovery to recover.sh.
# This script never relaunches the starter itself: recover.sh remains
# the single source of recovery logic (mechanical + functional proof).
#
# Usage (from the repo directory):
#   ./watchdog.sh [interval_seconds]          foreground (Ctrl-C stops it)
#   nohup ./watchdog.sh 5 >watchdog.log 2>&1 &   background, log to file
#
# DOWN criterion (mechanically correct): adb "ps" SUCCEEDS and shows NO
# shizuku_server process. If the adb call itself fails or times out, the
# transport is unavailable — that is NOT evidence that the server died,
# so the watchdog skips the cycle (no recovery is triggered).
# Recovery is delegated to ./recover.sh, which enforces its own criteria:
# new PID observed, stability N0..N3, functional rish probe.
#
# Exit codes: 0 = stopped by signal · 1 = bad usage · 2 = missing artifacts

INTERVAL="${1:-5}"
case "$INTERVAL" in
  ''|*[!0-9]*) echo "usage: $0 [interval_seconds]"; exit 1 ;;
esac
[ "$INTERVAL" -ge 1 ] || INTERVAL=1

HERE=$(cd "$(dirname "$0")" && pwd)
[ -x "$HERE/recover.sh" ] || { echo "FAIL: $HERE/recover.sh not found (run from the repo dir)"; exit 2; }
command -v adb >/dev/null 2>&1 || { echo "FAIL: adb not in PATH"; exit 2; }

CYCLE=0
RECOVERIES=0

detect_serial() {
  # Full priority chain (matches doctor.sh/recover.sh/verify.sh):
  # tls-connect -> local host:port -> any device in state 'device'.
  # (v0 bug: only the tls-connect level existed here; a host:port serial like
  # localhost:37215 was invisible to the daemon. Fixed in the v1 increment.)
  SERIAL=$(adb devices 2>/dev/null | awk '$2=="device"{print $1}' | grep 'adb-tls-connect' | head -n 1)
  [ -z "$SERIAL" ] && SERIAL=$(adb devices 2>/dev/null | awk '$2=="device"{print $1}' | grep ':' | head -n 1)
  [ -z "$SERIAL" ] && SERIAL=$(adb devices 2>/dev/null | awk '$2=="device"{print $1}' | head -n 1)
  echo "$SERIAL"
}

server_pid() {
  # Prints PID only when adb works AND the process exists. Empty otherwise.
  adb -s "$1" shell "ps -A -o PID,USER,NAME 2>/dev/null" 2>/dev/null | awk '$3=="shizuku_server"{print $1; exit}'
}

echo "$(date '+%F %T') watchdog v0 started (interval=${INTERVAL}s, log=pwd)"

while :; do
  CYCLE=$((CYCLE+1))
  SERIAL=$(detect_serial)
  if [ -z "$SERIAL" ]; then
    echo "$(date '+%F %T') cycle $CYCLE: no adb transport — skipping (transport down is NOT server DOWN)"
  else
    PID=$(server_pid "$SERIAL")
    if [ -n "$PID" ]; then
      echo "$(date '+%F %T') cycle $CYCLE: UP serial=$SERIAL pid=$PID"
    else
      # ps succeeded (serial exists) but no process row -> mechanically DOWN
      echo "$(date '+%F %T') cycle $CYCLE: DOWN serial=$SERIAL (ps ok, no shizuku_server) -> invoking recover.sh"
      RECOVERIES=$((RECOVERIES+1))
      if (cd "$HERE" && ./recover.sh); then
        NEWPID=$(server_pid "$SERIAL")
        echo "$(date '+%F %T') recovery #$RECOVERIES OK (new pid=${NEWPID:-unknown})"
      else
        echo "$(date '+%F %T') recovery #$RECOVERIES FAILED (recover.sh exit=$?)"
      fi
    fi
  fi
  sleep "$INTERVAL"
done
