#!/system/bin/sh
# doctor.sh — ladb-shizuku-recovery PoC
# Chain check: adb transport -> uid 2000 -> starter binary -> shizuku_server -> rish.
# Exit codes: 0 = UP (server running), 1 = DOWN/transport fail, 2 = DEGRADED (up, rish blocked)

RISH="$HOME/bin/rish"
STARTER=/data/local/tmp/shizuku
export RISH_APPLICATION_ID=com.termux
export MANAGER_APPLICATION_ID=moe.shizuku.privileged.api

echo "== ladb-shizuku-recovery :: doctor =="

# [1] adb client
ADB_BIN=$(command -v adb 2>/dev/null)
if [ -z "$ADB_BIN" ]; then
  echo "[1/5] adb client ............ FAIL (not in PATH)"
  exit 1
fi
echo "[1/5] adb client ............ OK ($ADB_BIN)"

# [2] LADB transport — dynamic serial, no hardcoded endpoints.
# Priority: *_adb-tls-connect, then local TCP host:port, then any 'device'.
SERIAL=$(adb devices 2>/dev/null | awk '$2=="device"{print $1}' | grep 'adb-tls-connect' | head -n 1)
if [ -z "$SERIAL" ]; then
  SERIAL=$(adb devices 2>/dev/null | awk '$2=="device"{print $1}' | grep ':' | head -n 1)
fi
if [ -z "$SERIAL" ]; then
  SERIAL=$(adb devices 2>/dev/null | awk '$2=="device"{print $1}' | head -n 1)
fi
if [ -z "$SERIAL" ]; then
  echo "[2/5] LADB transport ........ FAIL (no adb device in state 'device')"
  echo "      hint: open LADB and confirm its local shell is running."
  exit 1
fi
echo "[2/5] LADB transport ........ OK (serial=$SERIAL)"

# [3] shell identity
ID_OUT=$(adb -s "$SERIAL" shell id 2>&1)
case "$ID_OUT" in
  *uid=2000*) echo "[3/5] shell identity ........ OK (uid=2000 shell)" ;;
  *) echo "[3/5] shell identity ........ FAIL ($ID_OUT)"; exit 1 ;;
esac

# [4] starter binary
if adb -s "$SERIAL" shell ls -l "$STARTER" >/dev/null 2>&1; then
  echo "[4/5] starter binary ........ OK ($STARTER)"
else
  echo "[4/5] starter binary ........ FAIL ($STARTER not found)"
  exit 1
fi

# [5] server state + functional probe
PID=$(adb -s "$SERIAL" shell "ps -A -o PID,USER,NAME 2>/dev/null" | awk '$3=="shizuku_server"{print $1}' | head -n 1)
if [ -z "$PID" ]; then
  echo "[5/5] shizuku_server ........ DOWN (no process)"
  echo "VERDICT: DOWN -> run ./recover.sh"
  exit 1
fi
echo "[5/5] shizuku_server ........ UP (PID $PID, user shell)"

RISH_OUT=$("$RISH" -c "id" 2>&1)
case "$RISH_OUT" in
  *uid=2000*)
    echo "      rish functional probe . OK (rish -c id -> uid=2000 shell)"
    echo "VERDICT: UP — full chain verified (LADB -> uid 2000 -> shizuku_server -> rish)"
    exit 0 ;;
  *)
    echo "      rish functional probe . BLOCKED ($RISH_OUT)"
    echo "VERDICT: DEGRADED — server up but rish cannot attach"
    exit 2 ;;
esac
