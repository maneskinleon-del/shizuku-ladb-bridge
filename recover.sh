#!/system/bin/sh
# recover.sh — ladb-shizuku-recovery PoC
# If shizuku_server is DOWN: run the native starter (/data/local/tmp/shizuku)
# via the LADB adb transport, then prove mechanical recovery:
#   (a) new PID observed; (b) PID stable at checks N0/N1/N2/N3;
#   (c) new PID != OLD_PID; (d) functional post-recovery probe via rish.
# Idempotent and reversible: does nothing if the server is already UP,
# deletes/overrides nothing.
# Exit codes: 0 = recovered (or already up), 1 = failure.

RISH="$HOME/bin/rish"
STARTER=/data/local/tmp/shizuku
export RISH_APPLICATION_ID=com.termux
export MANAGER_APPLICATION_ID=moe.shizuku.privileged.api

echo "== ladb-shizuku-recovery :: recover =="

# Dynamic serial (same priority as doctor.sh)
SERIAL=$(adb devices 2>/dev/null | awk '$2=="device"{print $1}' | grep 'adb-tls-connect' | head -n 1)
if [ -z "$SERIAL" ]; then
  SERIAL=$(adb devices 2>/dev/null | awk '$2=="device"{print $1}' | grep ':' | head -n 1)
fi
if [ -z "$SERIAL" ]; then
  SERIAL=$(adb devices 2>/dev/null | awk '$2=="device"{print $1}' | head -n 1)
fi
if [ -z "$SERIAL" ]; then
  echo "FAIL: no adb transport (state 'device'). Open LADB first."
  exit 1
fi
echo "serial ...................... $SERIAL"

OLD_PID=$(adb -s "$SERIAL" shell "ps -A -o PID,USER,NAME 2>/dev/null" | awk '$3=="shizuku_server"{print $1}' | head -n 1)
if [ -n "$OLD_PID" ]; then
  echo "shizuku_server .............. already UP (PID $OLD_PID) — nothing to recover"
  exit 0
fi
echo "shizuku_server .............. DOWN (observed)"

if ! adb -s "$SERIAL" shell ls -l "$STARTER" >/dev/null 2>&1; then
  echo "FAIL: starter not found: $STARTER"
  exit 1
fi
echo "starter ..................... present ($STARTER)"

echo "action ...................... launching starter via adb (backgrounded)"
nohup adb -s "$SERIAL" shell "$STARTER" >/dev/null 2>&1 &
LAUNCHER=$!

# N0: wait up to ~20s for the server process to appear
NEW_PID=""
i=0
while [ $i -lt 10 ] && [ -z "$NEW_PID" ]; do
  sleep 2
  NEW_PID=$(adb -s "$SERIAL" shell "ps -A -o PID,USER,NAME 2>/dev/null" | awk '$3=="shizuku_server"{print $1}' | head -n 1)
  i=$((i+1))
done
if [ -z "$NEW_PID" ]; then
  echo "FAIL: no shizuku_server process appeared after starter (~20s)"
  exit 1
fi
echo "N0 .......................... new PID = $NEW_PID"

# N1..N3: temporal stability of the SAME PID
STABLE=1
sleep 5
P1=$(adb -s "$SERIAL" shell "ps -A -o PID,USER,NAME 2>/dev/null" | awk '$3=="shizuku_server"{print $1}' | head -n 1)
echo "N1 .......................... PID = ${P1:-<none>}"
[ "$P1" = "$NEW_PID" ] || STABLE=0
sleep 5
P2=$(adb -s "$SERIAL" shell "ps -A -o PID,USER,NAME 2>/dev/null" | awk '$3=="shizuku_server"{print $1}' | head -n 1)
echo "N2 .......................... PID = ${P2:-<none>}"
[ "$P2" = "$NEW_PID" ] || STABLE=0
sleep 5
P3=$(adb -s "$SERIAL" shell "ps -A -o PID,USER,NAME 2>/dev/null" | awk '$3=="shizuku_server"{print $1}' | head -n 1)
echo "N3 .......................... PID = ${P3:-<none>}"
[ "$P3" = "$NEW_PID" ] || STABLE=0

if [ "$STABLE" = "1" ]; then
  echo "stability ................... OK (same PID at N0..N3)"
else
  echo "stability ................... FAIL (PID changed or died during N0..N3)"
fi

# PID-change criterion (only applies if an OLD_PID was observed)
if [ -n "$OLD_PID" ] && [ "$NEW_PID" = "$OLD_PID" ]; then
  echo "pid-change .................. FAIL (same PID as before: $OLD_PID)"
  STABLE=0
else
  echo "pid-change .................. OK (${OLD_PID:-none} -> $NEW_PID)"
fi

# Functional post-recovery proof (closes the FUNCTIONAL_RECOVERY gap)
RISH_OUT=$("$RISH" -c "id" 2>&1)
case "$RISH_OUT" in
  *uid=2000*) FUNC=OK ;;
  *)          FUNC=FAIL ;;
esac
echo "functional (rish -c id) ..... $FUNC ($RISH_OUT)"

if [ "$STABLE" = "1" ] && [ "$FUNC" = "OK" ]; then
  echo "VERDICT: RECOVERY VERIFIED (mechanical + functional)"
  exit 0
fi
echo "VERDICT: RECOVERY FAILED (see lines above)"
exit 1
