# Experiment Report — LADB Serial Change (dynamic transport detection)

**Date:** 2026-09-13
**Repo:** ~/ladb-shizuku-recovery (standalone, canonical source)
**Checkpoint of departure:** `3efedb79831382c7b2ff6b0a643ae5d284c84c07` (clean working tree, verified before starting)
**Device:** Xiaomi Mi 10 (umi) · Android 13 (API 33) / HyperOS

---

## OBSERVATION

- Starting checkpoint verified: repo clean at `3efedb7` (`git status --short` empty, `git log -1` = `3efedb7`).
- Transport before the test: `SERIAL_OLD = localhost:38639` (state `device`, transport_id 13).
- `shizuku_server` UP at **PID 7793** (carried over from the recovery verified in the base checkpoint).
- Script integrity baseline recorded (SHA-256):
  - `doctor.sh`  `555b1b92e01d286517b014ce20638e42432e2b4956fe0ed99acb8cda7799c2d8`
  - `recover.sh` `b71b1296eb4ea64532e8868bd5168f648f22f1a1f3218590015e3c59c6e1a353`
  - `verify.sh`  `28e7796cf48c366e777a9d0297b341d67423f89ea011b2c3373d2300823358d8`

## HYPOTHESIS

The three scripts detect the LADB serial dynamically (priority: `*adb-tls-connect*` →
`host:port` → any `device`), so they keep working unchanged when LADB restarts and its
serial changes — even if the new serial has a different **format** (mDNS/TLS instead of
host:port).

## ACTION

1. Captured `SERIAL_OLD` via `adb devices` (no hardcoded values).
2. Restarted the LADB app normally on the device (no re-pairing, no settings changes).
3. Polled `adb devices` until the transport returned; captured `SERIAL_NEW`.
4. Compared both serials mechanically.
5. Ran the existing scripts **unmodified**: `./doctor.sh` → `./recover.sh` → `./verify.sh`.
6. Verified script integrity after the run (SHA-256 unchanged).
7. No watchdog, no reboot, no re-pairing, no forced kill, no additional experiments.

## EVIDENCE

### Serial change (mechanical)

```
SERIAL_OLD = localhost:38639                                (transport_id 13)
SERIAL_NEW = adb-d2c6cbda-uWIKtV._adb-tls-connect._tcp.     (transport_id 1)

adb devices after restart:
List of devices attached
adb-d2c6cbda-uWIKtV._adb-tls-connect._tcp.   device   product:umi_global model:Mi_10 device:umi transport_id:1

SERIAL_OLD != SERIAL_NEW  -> observed (string inequality AND format change:
host:port  ->  mDNS/TLS service name)
```

### doctor.sh (on the new serial)

```
== ladb-shizuku-recovery :: doctor ==
[1/5] adb client ............ OK (/data/data/com.termux/files/usr/bin/adb)
[2/5] LADB transport ........ OK (serial=adb-d2c6cbda-uWIKtV._adb-tls-connect._tcp.)
[3/5] shell identity ........ OK (uid=2000 shell)
[4/5] starter binary ........ OK (/data/local/tmp/shizuku)
[5/5] shizuku_server ........ UP (PID 7793, user shell)
      rish functional probe . OK (rish -c id -> uid=2000 shell)
VERDICT: UP — full chain verified (LADB -> uid 2000 -> shizuku_server -> rish)
doctor exit=0
```

The script **printed the new serial itself** — dynamic detection demonstrated, not assumed.

### recover.sh (on the new serial)

```
serial ...................... adb-d2c6cbda-uWIKtV._adb-tls-connect._tcp.
shizuku_server .............. already UP (PID 7793) — nothing to recover
recover exit=0
```

Idempotent branch: the server was already UP (it survived the LADB app restart), so no
relaunch was due. The script correctly assessed server state through the NEW transport.

### verify.sh (on the new serial)

```
serial ...................... adb-d2c6cbda-uWIKtV._adb-tls-connect._tcp.
shizuku_server .............. UP (PID 7793, user shell)
rish functional probe ....... OK (rish -c id -> uid=2000 shell)
VERDICT: UP + FUNCTIONAL
verify exit=0
```

### PID before/after + direct rish

- PID before LADB restart: `7793` · PID after: `7793` (unchanged — server lifetime is
  independent of the LADB app session).
- Direct functional probe: `rish -c "id"` → `uid=2000(shell) ... context=u:r:shell:s0`.

### Integrity

SHA-256 of `doctor.sh`, `recover.sh`, `verify.sh` identical before and after the
experiment — **no script was modified**.

## CONCLUSION

**SERIAL_CHANGE_VERIFIED**

Success criteria:
1. LADB had `SERIAL_OLD` (localhost:38639) — recorded. ✓
2. LADB returned with `SERIAL_NEW` (adb-…adb-tls-connect…tcp.) — observed. ✓
3. `SERIAL_OLD != SERIAL_NEW` — proven (string and format). ✓
4. Scripts detected `SERIAL_NEW` dynamically — doctor printed it. ✓
5. `doctor.sh` exit 0. ✓
6. Recovery procedure worked on the new serial (recover.sh exit 0, correct state
   assessment via idempotent branch — the server never went DOWN in this experiment, so
   the relaunch branch was not exercised here; it remains proven at `3efedb7`). ✓
7. `verify.sh` exit 0 → UP + FUNCTIONAL. ✓
8. `rish` functional after the transport change. ✓

**Scope (explicit):** this experiment proves **dynamic detection of the LADB transport**
only. It does NOT prove a watchdog, does NOT prove persistence across reboot, and does
NOT re-demonstrate a server relaunch (the server stayed UP throughout; that branch was
verified in the base checkpoint `3efedb7`).

**Side findings (documented, not separately experimented):**
- The LADB serial can change format (host:port → mDNS/TLS), which is exactly the case the
  detection priority was designed for.
- `shizuku_server` survived the LADB app restart (PID 7793 unchanged): server lifetime is
  tied to the shell-identity daemon, not to the LADB app session.
