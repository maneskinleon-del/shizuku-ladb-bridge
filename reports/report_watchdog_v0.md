# Experiment Report — Watchdog v0 (auto-recovery of shizuku_server)

**Date:** 2026-09-13
**Repo:** ~/ladb-shizuku-recovery (canonical, standalone)
**Base checkpoints:** `3efedb7` (PoC VERIFIED) → `5ded4ee` (SERIAL_CHANGE_VERIFIED)
**Device:** Xiaomi Mi 10 (umi) · Android 13 (API 33) / HyperOS

---

## OBSERVATION

- Repo clean at `5ded4ee` before starting; `doctor.sh`/`recover.sh`/`verify.sh` untouched
  (SHA-256 baseline re-verified at commit time).
- Transport: `adb-d2c6cbda-uWIKtV._adb-tls-connect._tcp.` (the mDNS/TLS serial validated
  in the serial-change experiment).
- Pre-test state: server DOWN (an operational incident outside this experiment — a
  monitoring session died mid-command and its manual recovery never ran). Restored via
  `recover.sh` → PID **385**, stable N0–N3, rish OK. That manual run is state restoration,
  not part of the watchdog test; it incidentally re-validated the relaunch branch on the
  new-format serial.

## HYPOTHESIS

A minimal loop that (a) detects the serial dynamically, (b) applies the mechanically
correct DOWN criterion — adb `ps` succeeds AND no `shizuku_server` row, treating an
unavailable transport as NOT server death — and (c) delegates recovery entirely to the
existing `recover.sh`, restores the server without manual intervention and without
duplicating recovery logic.

## ACTION

1. Added `watchdog.sh` (v0): interval loop; DOWN = ps-ok-without-server; on DOWN it
   invokes `./recover.sh` and logs the resulting PID. Added `.gitignore` for its runtime log.
2. Started watchdog (3 s interval), observed UP cycles.
3. Forced one DOWN event exactly as in the approved base experiment: `rish -c "kill -9 <pid>"`.
4. Watchdog (not the operator) detected DOWN and recovered.
5. Stopped the watchdog by exact PID; verified scripts unmodified; committed.

## EVIDENCE (watchdog.log, one single session)

```
03:46:11 watchdog v0 started (interval=3s)
03:46:11 → 03:46:21  cycles 1-4: UP pid=385
T0 = 03:46:22  rish -c "kill -9 385"        (forced DOWN, operator)
03:46:24 cycle 5: DOWN (ps ok, no shizuku_server) -> invoking recover.sh
  recover.sh: DOWN observed -> starter -> N0=2624 · N1=2624 · N2=2624 · N3=2624
              stability OK · pid-change OK · rish -c "id" -> uid=2000(shell)
              VERDICT: RECOVERY VERIFIED (mechanical + functional)
03:46:43 recovery #1 OK (new pid=2624)
03:46:46 → 03:47:34  cycles 6-21 (16 consecutive): UP pid=2624
PID before=385 / after=2624
direct rish after the cycle: uid=2000(shell) ...
watchdog stopped by exact PID 1769 — confirmed dead
```

Key numbers: detection latency ≤ one interval (~3 s); full auto-recovery ~19 s
(detection + starter wait + N0..N3 stability checks); sustained UP for 16 further
cycles (~1 min) post-recovery.

## CONCLUSION

**WATCHDOG_V0 = VERIFIED** (single forced DOWN event, in-session run).

Proven:
- DOWN detected mechanically (ps-based, transport-down correctly excluded from DOWN).
- Recovery delegated to `recover.sh` — zero duplicated starter logic; recover.sh's own
  mechanical + functional criteria all passed inside the automated flow.
- New PID (2624 ≠ 385), stable (N0–N3) and rish-functional after unattended recovery.

Not proven (out of scope for v0):
- **Daemon persistence:** a backgrounded watchdog dies when its Termux session tears
  down (observed earlier while setting up this test). v0 is an in-session supervisor;
  real daemonization (Termux:service / termux-wake-lock) is future work.
- Reboot persistence of either the server or the watchdog.
- Multi-event/failure-storm behavior (one event was in scope).

Scope sentence (canonical): `WATCHDOG_V0 = VERIFIED` — auto-recovery on a single forced
DOWN event verified in-session; daemonization, reboot persistence and multi-event
behavior not tested in this increment.

## Integrity

- `doctor.sh` / `recover.sh` / `verify.sh`: SHA-256 unchanged from the base checkpoint
  (re-verified at commit time) — the watchdog adds a new file, it does not modify them.
- New artifacts: `watchdog.sh`, `.gitignore`, this report, CHECKPOINT.md addendum.
