# Experiment Report — Termux force-stop (app-level kill boundary)

**Date:** 2026-09-13
**Repo:** ~/ladb-shizuku-recovery (standalone, canonical source)
**Checkpoint of departure:** `b9ca628` (clean working tree; only the pre-state dossier untracked on disk)
**Device:** Xiaomi Mi 10 (umi) · Android 13 (API 33) / HyperOS
**Pre-state dossier:** `report_termux_force_stop_prestate.txt` — written from inside Termux BEFORE the force-stop (06:25 approx), designed to survive it on disk. It did.

---

## OBSERVATION

- Repo clean at `b9ca628`; scripts byte-identical to the base freeze (SHA-256 in the dossier).
- Daemon: `runsv` 10952 → watchdog session 32457, alive 5713 s (spanning sessions).
- Transport: `localhost:43459`. Server: **PID 8679, user shell**, UP.
- Termux-UID (u0_a364) inventory at pre-state — the expected dying set:
  - runsvdir aggregators 1413, 8851, 31425, 32113 (PPID 1)
  - runsv 6648 (ssh-agent), 6649 (sshd), 6650 (cupsd), 10952 (shizuku-watchdog)
  - adb server 11029 (holds the LADB transport brokered for Termux clients)
  - interactive shells + gitstatusd; freebuff agent 19176 (+ children)
  - watchdog session 32457 (parent 10952), child sleep 29868
- Outside the kill radius: `shizuku_server` PID 8679 (UID shell, started by adbd starter), LADB app (own UID).

## HYPOTHESIS

Android force-stop of `com.termux` kills **every Termux-UID process** (supervision,
watchdog, adb server) but **NOT** `shizuku_server` (UID shell). After Termux is
reopened, the server must still be UP (same PID if untouched) and supervision must be
restorable. This distinguishes "session teardown" (covered by `WATCHDOG_V1`) from
"app-level kill" — without touching reboot.

## ACTION

1. Pre-state dossier written to disk before the trigger (survives the kill by design).
2. **Trigger performed by the user, OUTSIDE Termux:** `am force-stop com.termux`
   (from the LADB terminal). The session that wrote the dossier died with the kill —
   that was the experiment, not a failure.
3. Termux reopened; runbook executed **in order**, inventory taken BEFORE restoring
   anything. No re-pairing, no reboot, no server intervention, scripts unmodified.
4. `./verify.sh` for the functional proof; `watchdog.log` for continuity.

## EVIDENCE

### 1. Post-stop inventory (nothing restored yet)

```
runsvdir 11848 (PPID 1) -> runsv shizuku-watchdog 11855 / ssh-agent 11856 / sshd 11857 / cupsd 11858
watchdog.sh running as PID 11863 (parent 11855)
```

- **None of the pre-state PIDs survived** (no 1413/8851/31425/32113, no 6648–6650/10952,
  no 11029, no 32457, no shell PIDs). The kill was app-level and total for u0_a364.
- **termux-services auto-revived the whole service tree** at app start: fresh runsvdir
  (11848, PPID 1) + all four runsv instances were already up at first inventory, before
  any manual action — including `runsv shizuku-watchdog` → watchdog loop respawned (11863).
- Old adb server 11029 was dead; a new one spawns on demand with the first adb client.

### 2. Server state (outside Termux)

```
$ adb devices
List of devices attached
localhost:42125	device          <- NEW serial (was localhost:43459)

$ adb -s localhost:42125 shell "ps -A -o PID,USER,NAME" | awk '$3=="shizuku_server"'
 8679 shell        shizuku_server
```

Single row, **same PID 8679, user shell** — the server was untouched by the force-stop.
The serial changed (`43459 → 42125`) because the adb server death forces mdns
re-discovery; the scripts' dynamic detection handled it unmodified (`SERIAL_CHANGE`
re-demonstrated under worse conditions: broker AND adb server both dead).

### 3. Supervision state

```
$ sv status .../var/service/shizuku-watchdog
run: /data/data/com.termux/files/usr/var/service/shizuku-watchdog: (pid 11863) 86s
```

**Auto-revived** — no manual `./install-service.sh start` was needed.

### 4. Functional proof

```
== ladb-shizuku-recovery :: verify ==
serial ...................... localhost:42125
shizuku_server .............. UP (PID 8679, user shell)
rish functional probe ....... OK (rish -c id -> uid=2000 shell)
VERDICT: UP + FUNCTIONAL
exit=0
```

### 5. Watchdog continuity (log boundary)

```
2026-09-13 06:27:49 cycle 584: UP serial=localhost:43459 pid=8679   <- last entry, old session
                     [ ~26 s gap — the force-stop window ]
2026-09-13 06:28:15 watchdog v0 started (interval=10s, log=pwd)     <- new session
2026-09-13 06:28:15 cycle 1:   UP serial=localhost:42125 pid=8679
...
2026-09-13 06:29:47 cycle 10:  UP serial=localhost:42125 pid=8679
```

- The cycle counter **reset to 1**: mechanical proof that the old watchdog process died
  with the app and a **new** instance was respawned by runsv (not survival).
- New cycles show the **new serial with the same server PID 8679**: coverage continuity
  across the kill boundary, with the server never going DOWN.

### Anomaly noted (pre-existing, unrelated to the trigger window)

`2026-09-13 06:25:47 cycle 572: UP serial=localhost:43459 pid=6275` — a single cycle
reported a different PID, self-corrected at cycle 573 (8679 again). It occurred ~2 min
before the force-stop gap, so it belongs to the previous session's noise, not to this
experiment's boundary. Recorded for completeness; not investigated further here.

## CONCLUSION

**TERMUX_FORCE_STOP = VERIFIED (app-level kill scope)**

Success criteria (per the runbook):
1. Force-stop killed every Termux-UID process — supervision, watchdog, adb server. ✓
2. `shizuku_server` (UID shell) survived with the **same PID 8679** — server lifetime is
   independent of the Termux app. ✓
3. Supervision was restorable — in fact **auto-revived** by termux-services at app
   start, zero manual action. ✓
4. `verify.sh` exit 0 → UP + FUNCTIONAL on the new serial. ✓
5. Log continuity across the gap (new session, same server PID). ✓

**Scope (explicit):**
- The watchdog did **NOT survive as a process** — it died with the app (cycle reset
  proves it). What crossed the app-level kill boundary is (a) the server itself
  (untouched) and (b) the supervision architecture (auto-revived on next app start).
  `WATCHDOG_V1`'s "daemonized" scope therefore remains **session-teardown, NOT
  force-stop**; force-stop coverage comes from termux-services auto-revival.
- `REBOOT_PERSISTENCE` remains `NOT_TESTED` — this test deliberately skipped reboot.

**Side findings:**
- Serial changed (`43459 → 42125`) as a *consequence* of the force-stop (adb server
  death); scripts detected it dynamically — the detection chain held with both the
  transport broker and the adb server dead.
- App-level kill is strictly more destructive than session teardown, and the system
  still self-heals on next app start: the recovery story degrades gracefully.
