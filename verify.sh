#!/system/bin/sh
# verify.sh — ladb-shizuku-recovery PoC
# Verification: shizuku_server process present + functional rish probe.
# Exit codes: 0 = UP + FUNCTIONAL, 1 = DOWN/transport fail, 2 = UP but rish blocked.

RISH="$HOME/bin/rish"
export RISH_APPLICATION_ID=com.termux
export MANAGER_APPLICATION_ID=moe.shizuku.privileged.api

echo "== ladb-shizuku-recovery :: verify =="

SERIAL=$(adb devices 2>/dev/null | awk '$2=="device"{print $1}' | grep 'adb-tls-connect' | head -n 1)
if [ -z "$SERIAL" ]; then
  SERIAL=$(adb devices 2>/dev/null | awk '$2=="device"{print $1}' | grep ':' | head -n 1)
fi
if [ -z "$SERIAL" ]; then
  SERIAL=$(adb devices 2>/dev/null | awk '$2=="device"{print $1}' | head -n 1)
fi
if [ -z "$SERIAL" ]; then
  echo "FAIL: no adb transport (state 'device')"
  exit 1
fi
echo "serial ...................... $SERIAL"

PID=$(adb -s "$SERIAL" shell "ps -A -o PID,USER,NAME 2>/dev/null" | awk '$3=="shizuku_server"{print $1}' | head -n 1)
if [ -z "$PID" ]; then
  echo "shizuku_server .............. DOWN"
  echo "VERDICT: DOWN"
  exit 1
fi
echo "shizuku_server .............. UP (PID $PID, user shell)"

RISH_OUT=$("$RISH" -c "id" 2>&1)
case "$RISH_OUT" in
  *uid=2000*)
    echo "rish functional probe ....... OK (rish -c id -> uid=2000 shell)"
    echo "VERDICT: UP + FUNCTIONAL"
    exit 0 ;;
  *)
    echo "rish functional probe ....... BLOCKED ($RISH_OUT)"
    echo "VERDICT: UP (server alive) but rish blocked"
    exit 2 ;;
esac
