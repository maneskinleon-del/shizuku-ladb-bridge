# Experiment Report — Watchdog v1 (daemonized supervision via runit runsv)

**Date:** 2026-09-13
**Repo:** ~/ladb-shizuku-recovery (canonical, standalone)
**Base history:** `3efedb7` (PoC) → `5ded4ee` (serial change) → `83ec34f` (watchdog v0) → `8875abe` (checkpoint consolidation)
**Device:** Xiaomi Mi 10 (umi) · Android 13 (API 33) / HyperOS

---

## OBSERVATION

- Watchdog v0 proved auto-recovery but only as an **in-session** loop: a backgrounded
  watchdog dies when its Termux session tears down (observed in the v0 experiment).
- This increment adds the daemon layer: `service/shizuku-watchdog/run` (runit run
  script) + `install-service.sh`, wrapping the existing `watchdog.sh` — no sealed
  script was modified to add the daemon (one pre-existing bug in `watchdog.sh` was
  found during this experiment and is disclosed below).
- Environment found: `termux-services`/`runit` not installed (installed here:
  termux-services 0.13-1 / runit 2.1.2-4 — first external package added in this series,
  required for the requested daemonization). `termux-wake-lock` was already present.

## HYPOTHESIS

An `sv`/`runsv`-supervised watchdog, launched detached via `start-stop-daemon` and
holding a Termux wake-lock, keeps supervising `shizuku_server` across interactive
session teardown, restarts its own loop if it dies, and autonomously recovers the
server over the dynamic LADB transport — without duplicating any recovery logic.

## ACTION

1. Created `service/shizuku-watchdog/run` (cd to repo, `termux-wake-lock`, `exec
   ./watchdog.sh 10 >> watchdog.log`) and `install-service.sh` (install/start/stop/
   uninstall via `start-stop-daemon` + `sv`).
2. Installed `termux-services`; found its `service-daemon`/`runsvdir` aggregator dies
   instantly on this device (multiple launch methods) while **individual `runsv`
   instances persist** — so the installer launches ONE dedicated `runsv <dir>` per
   service (this design deviation from stock termux-services is documented in the
   installer header).
3. Started the service; validated supervision lifecycle.
4. Ran the DOWN test with the daemon supervising.
5. Investigated and fixed a disclosed defect (below); committed everything.

## EVIDENCE

### A. Daemon survives session teardown (the v0 limitation, now closed)

- `runsv` PID 10952 alive continuously from 04:33 to 04:49+ (~16 min), crossing ~15
  interactive command sessions and their teardowns.
- Watchdog script session PID 10954 reached **845 s** of continuous runtime (sv status)
  before being deliberately killed for test (2).
- `sv status /…/var/service/shizuku-watchdog` → `run: (pid …) Ns` at every probe.
- Wake-lock held by the run script (re-acquired on every start); battery-optimization
  exemption for Termux remains a user-level precondition (documented, not testable here).

### B. runsv restarts the watchdog loop itself

- Test: `kill 10954` (the watchdog script session). Result: runsv respawned it —
  log line `04:47:37 watchdog v0 started (interval=10s)` as a **new session** (PID
  32457). Supervision-of-the-supervisor demonstrated.

### C. Autonomous DOWN detection + recovery by the daemon

```
04:47:37 cycle 1: UP serial=localhost:37215 pid=31371
T0 = operator: rish -c "kill -9 31371"      (no session was tending the server)
04:48:0x  cycle N: DOWN (ps ok, no shizuku_server) -> invoking recover.sh
  recover.sh: N0..N3 = 2442 · stability OK · pid-change OK · rish -> uid=2000(shell)
04:48:26  recovery #1 OK (new pid=2442)
04:48:36+ cycles: UP serial=localhost:37215 pid=2442   (sustained)
direct post-test probe: rish -c "id" -> uid=2000(shell) ...
sv status: run: (pid 32457) 76s   [daemon alive after the whole cycle]
```

Detection ≤ one interval (10 s); full recovery ~19 s (starter wait + N0–N3); all
mechanical + functional criteria enforced by `recover.sh` inside the automated flow.

### D. Conservative transport-down behavior — validated live in daemon mode

While the LADB app was closed (~04:33–04:40), the daemon logged **39+ consecutive
`no adb transport — skipping` cycles and triggered NO recovery** — a transport outage
was correctly not misread as server death.

### E. Disclosed defect found and fixed in this increment (v0 → fixed)

- **Bug:** `watchdog.sh` v0's `detect_serial()` implemented only the first detection
  level (`adb-tls-connect`) despite its comment claiming the full chain. It worked in
  the v0/serial tests because those serials were TLS-format. When the transport
  returned as `localhost:37215` (host:port), the daemon was blind to it (cycles 38–77
  empty) — diagnostic differential (identical environment; single adb server PID
  11029; fresh detached clients saw the transport) isolated the cause to the script.
- **Fix (this increment):** full priority chain (tls-connect → host:port → any
  `device`), matching doctor/recover/verify. Verified live: after runsv respawned the
  loop, first cycle = `UP serial=localhost:37215 pid=31371`.
- Honesty note: the daemon did NOT recover the earlier server death (PID 2624) — that
  happened while the daemon was blind; it was recovered manually via `recover.sh`
  (→ 31371). The daemon-handled DOWN events in this experiment: exactly one (31371 →
  2442).

## CONCLUSION

**WATCHDOG_V1 = VERIFIED (daemonized, single DOWN event)**

Proven:
- [OK] Supervision survives interactive session teardown (runsv + watchdog, 16+ min,
  multiple sessions).
- [OK] runsv auto-restarts the watchdog loop if it dies (observed).
- [OK] Daemon autonomously detected a forced server DOWN and recovered it to a new,
  stable, rish-functional PID via `recover.sh` (385-style criteria all passed).
- [OK] Transport-down conservatively skipped in live daemon operation.
- [OK] Detection now covers both observed serial formats (mDNS/TLS and host:port).

Still NOT tested (explicit):
- `REBOOT_PERSISTENCE = NOT_TESTED` (daemon across device reboot; Termux:Boot).
- `MULTI_EVENT_STORM = NOT_TESTED` (exactly one daemon-handled DOWN event here).
- Force-stop of the Termux app itself / Android killing the app process (wake-lock
  mitigates; not simulated).

Token board update: `WATCHDOG_DAEMON_PERSISTENCE = NOT_TESTED` → **VERIFIED
(session-teardown scope)**; reboot/multi-event limits remain NOT_TESTED. As before:
never summarize as a bare `WATCHDOG = VERIFIED`.

**End state:** the daemon is left RUNNING (`sv status` up) — v1's purpose is exactly
that persistent supervision. `./install-service.sh stop|uninstall` reverts it.
