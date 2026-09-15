# Experiment report — Multi-event failure storm under watchdog v1 (daemonized)

**Repo:** `~/ladb-shizuku-recovery` (standalone, local-only)
**Base checkpoint:** `a1ff0c4` (watchdog v1) on top of `df7ce59` (token-plate
correction), `8875abe`, `83ec34f`, `5ded4ee`, `3efedb7`
**Date:** 2026-09-13
**Scope of this document:** sequential forced-DOWN events against a live daemon.
This experiment does NOT test reboot persistence (`REBOOT_PERSISTENCE`),
force-stop of Termux (`TERMUX_FORCE_STOP`), or simultaneous/overlapping events.

## OBSERVATION

- Watchdog v1 daemon (`runsv` instance, session pid 32457) had been alive across
  many Termux sessions (`sv status` ≥ 4079 s at test start, 5131 s at end).
- shizuku_server was UP on PID 2442 (the PID recovered autonomously by the
  daemon in the v1 experiment).
- LADB transport had been closed by the operator; after reopening the LADB app
  the daemon re-attached **autonomously** to a third distinct serial:
  `SERIAL_STORM = localhost:43459` (series history: `localhost:38639` →
  `adb-d2c6cbda-…_adb-tls-connect._tcp.` → `localhost:37215` → `localhost:43459`).
- Pre-storm daemon log baseline (whole lifetime, appended across sessions):
  DOWN lines = 2, recovery OK = 2, recovery FAILED = 0 — every one of them
  corresponding to the single DOWN events of v0 (→ 2624) and v1 (→ 2442).
- Known log quirk (documented, not a defect introduced here): the recovery
  counter restarts per watchdog session (two historical `recovery #1` lines
  exist from the v0 and v1 sessions), while the log is append-only. The storm
  therefore logged as recoveries #2, #3, #4.

## HYPOTHESIS

A daemonized watchdog v1 that survives session teardown can also sustain
**repeated** DOWN events: each forced `kill -9` of shizuku_server produces
exactly one DOWN detection and exactly one delegated `recover.sh` recovery,
with no duplicate server processes, no overlapping recoveries, no false
positives, and no daemon degradation.

## ACTION

1. Confirmed T0: daemon alive, transport up (`localhost:43459`), server
   PID 2442, baseline counters captured, script hashes recorded.
2. Executed 3 sequential events, each: NAME-filtered process lookup
   (`awk '$3=="shizuku_server"'` — the same filter the scripts use), gate
   requiring **exactly one** server row, then `kill -9 <pid>`, then wait for
   the daemon's own `recovery #N OK` log line (75 s timeout), then 5 s settle.
3. Post-storm reconciliation from the daemon's log (mechanical, not asserted):
   deltas of DOWN/OK/FAILED lines, daemon `sv status`, single watchdog
   session, NAME-filtered server rows ×4 (N0–N3), `verify.sh`, script hashes.
4. Operator-side honesty note: three previous loop attempts were aborted by
   the loop's own safety gates (log-timing abort, `grep -c` exit-code chain
   halt, and a `ps | grep` self-match producing 5 rows) — **in all three the
   gate fired before any kill command**; zero kills occurred outside the
   three logged events.

## EVIDENCE

Kill chain: `2442 → 6444 → 7671 → 8679`

| Event | Kill (local time) | DOWN detected (cycle) | Recovery line | New PID | Stability | Functional |
|---|---|---|---|---|---|---|
| 1 | 06:11:38 `kill -9 2442` | 06:11:44 (cycle 495, ~6 s) | `recovery #2 OK` 06:12:03 | 6444 | N0–N3 = 6444 | rish `uid=2000(shell)` |
| 2 | 06:12:10 `kill -9 6444` | 06:12:13 (cycle 496, ~3 s) | `recovery #3 OK` 06:12:32 | 7671 | N0–N3 = 7671 | rish `uid=2000(shell)` |
| 3 | 06:12:38 `kill -9 7671` | 06:12:42 (cycle 497, ~4 s) | `recovery #4 OK` 06:13:01 | 8679 | N0–N3 = 8679 | rish `uid=2000(shell)` |

Each `recover.sh` invocation (log-embedded, verbatim in `watchdog.log`) printed
its own verdict `RECOVERY VERIFIED (mechanical + functional)`, with N0=N1=N2=N3
and `rish -c "id"` OK.

Reconciliation (deltas over pre-storm baseline):

- DOWN lines: +3 — one per kill, no extras (no false positives; the
  transport-less period before the experiment produced only `no adb transport
  — skipping` lines, never a DOWN).
- `recovery #N OK`: +3, `FAILED`: +0 — kills == detections == recoveries.
- Cycles strictly sequential: 495 → 496 → 497 (no overlapping recoveries).
- Watchdog sessions: exactly one (`32457`, `runsv 10952`) before, during and
  after the storm; `sv status` alive at 5131 s.
- Post-storm server: single NAME-filtered row, PID 8679, four consecutive
  queries (N0–N3) identical.
- `verify.sh`: exit 0 — `UP (PID 8679, user shell)` + `rish -c id → uid=2000`,
  verdict `UP + FUNCTIONAL`.
- Scripts untouched during the whole experiment (SHA-256 identical to base):
  - `doctor.sh`  `555b1b92e01d286517b014ce20638e42432e2b4956fe0ed99acb8cda7799c2d8`
  - `recover.sh` `b71b1296eb4ea64532e8868bd5168f648f22f1a1f3218590015e3c59c6e1a353`
  - `verify.sh`  `28e7796cf48c366e777a9d0297b341d67423f89ea011b2c3373d2300823358d8`
  - `watchdog.sh` `6f6ed1bd8f343ed4b2a5a144947153948fa716d6f923f993cef098aeda7983a0`

## CONCLUSION

**MULTI_EVENT_STORM = VERIFIED (daemonized).** Three consecutive forced DOWN
events under the live daemon produced exactly three valid recoveries (new PID,
stable N0–N3, functional rish each time), with zero failures, zero duplicate
processes, zero overlapping recoveries and zero false positives.

Explicit limits (NOT covered by this result): persistence across reboot
(`REBOOT_PERSISTENCE`), force-stop of the Termux app itself
(`TERMUX_FORCE_STOP`), and simultaneous rather than sequential failure
bursts (N=3, spacing ≥ one full recovery). The recovery counter being
per-session is a cosmetic log quirk, recorded here for auditability.
