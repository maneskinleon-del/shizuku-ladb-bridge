# CHECKPOINT — LADB Shizuku Recovery PoC

**Frozen on:** 2026-09-13 (post-experiment, documentation freeze; sealed as a standalone Git repository)
**Consolidated:** 2026-09-13 — post serial-change (`5ded4ee`) and watchdog v0 (`83ec34f`) documentation consolidation (this edit only; no experiments run for it)
**Consolidated (2):** 2026-09-13 — post force-stop (`075ff50`) documentary consolidation: real commit chain (§9), manifest refreshed to the current tree (§12), inventory matched to `git ls-files` (§13). Documentation only; NO experiments run for it.
**Consolidated (3):** 2026-09-15 — post reboot-persistence registration (reboot executed 2026-09-14 22:36): result report + boot evidence registered, token plate updated (§9/§12b). The commit carrying this edit is itself the experiment-result commit; NO new experiments were run for this registration.
**Status:** `LADB_RECOVERY_MECHANICAL = VERIFIED` · `SHIZUKU_FUNCTIONAL_RECOVERY = VERIFIED` · `SERIAL_CHANGE = VERIFIED` · `WATCHDOG_V0 = VERIFIED (in-session)` · `WATCHDOG_V1 = VERIFIED (daemonized, session-teardown scope)` · `MULTI_EVENT_STORM = VERIFIED (daemonized)` · `TERMUX_FORCE_STOP = VERIFIED (app-level kill scope)` · `REBOOT_BOOT_SUPERVISION = VERIFIED (boot-glue scope)` · `SHIZUKU_FUNCTIONAL_POST_REBOOT = VERIFIED`
**Explicit limits:** `REBOOT_AUTONOMOUS_RECOVERY = NOT_TESTED` (no dead-server recovery post-reboot was exercised) · `REBOOT_PERSISTENCE` is VERIFIED ONLY at boot-glue supervision scope (§12b — never quote it as an absolute)
**Buffy:** NOT modified · **Watchdog:** v0 in-session (`83ec34f`) + v1 daemonized (`a1ff0c4`) VERIFIED; died at force-stop as predicted and was auto-revived (`075ff50`); at reboot it started from boot via the boot glue (supervision VERIFIED) but performed no server recovery (none was needed — server already UP when the transport returned; autonomous recovery NOT_TESTED)
**Companion reports:** `report_poc_ladb_shizuku_recovery.md/.txt` (Spanish, base experiment), `report_serial_change.md/.txt`, `report_watchdog_v0.md/.txt`, `report_watchdog_v1.md/.txt`, `report_multi_event_storm.md/.txt`, `report_termux_force_stop.md/.txt`, `report_reboot_persistence.md/.txt` (latest, §12b) + reboot prestate dossier and abort addendum (`report_reboot_persistence_prestate.txt`, `report_reboot_persistence_prestate_addendum.txt`)

---

## 1. PoC objective

Minimal proof that, when `shizuku_server` dies, a UID 2000 shell reachable through LADB
(on-device adbd, no PC) can relaunch it via the native starter — verified mechanically
(new, distinct, temporally stable PID) and functionally (rish post-recovery probe).

## 2. Initial state (verified before touching anything)

| Item | Value |
|---|---|
| Device | Xiaomi Mi 10 (umi), Android 13 / HyperOS, aarch64 |
| Runtime | Termux on the device itself + LADB local transport |
| Transport | `localhost:38639` (state `device`) — *current run's port, not a constant* |
| Shell identity | `uid=2000(shell)` · `context=u:r:shell:s0` |
| Starter | `/data/local/tmp/shizuku` (16,680 B, executable, owner `shell`) |
| Server | `shizuku_server` UP at **PID 12057** (the same PID from the manual 2026-09-12 demo, cycle 5704 → 12057) |
| rish | `~/bin/rish` + `rish_shizuku.dex` (exported kit), pattern `rish -c "cmd"` |

## 3. Executed experiment (with explicit user approval)

1. `doctor.sh` → exit 0, full chain UP (PID 12057, rish OK).
2. Forced DOWN cycle (approved): `rish -c "kill -9 12057"` → `ps` confirmed **absence**.
3. `recover.sh` → starter launched via adb (nohup, background) → new PID observed.
4. Stability checks N0/N1/N2/N3 → same PID at all four.
5. `verify.sh` → exit 0, UP + FUNCTIONAL.
6. Evidence written: `evidence.txt`, `oldpid.txt`.

## 4. Mechanical evidence

- **PID transition:** `12057 → 7793` (new ≠ old, criterion met).
- **Temporal stability:** `N0 = N1 = N2 = N3 = 7793` (checks at 0 s, +5 s, +10 s, +15 s).
- Server absence after kill confirmed by `ps -A -o PID,USER,NAME` (ground truth: process
  table, not exit codes).
- Exit codes: doctor 0 · recover 0 · verify 0.

## 5. Functional evidence

Post-recovery probe closed the gap left by the 2026-09-12 watchdog demo (which ended at
`SHIZUKU_FUNCTIONAL_RECOVERY = NOT_TESTED`):

```
rish -c "id" → uid=2000(shell) gid=2000(shell) ... context=u:r:shell:s0
```

Full chain proven in a single session: **LADB → UID 2000 → starter → shizuku_server → rish functional**.

## 6. Dynamic LADB serial (design invariant)

No script hardcodes an endpoint. Detection priority (identical in all three scripts):
1. serial matching `adb-tls-connect`;
2. local TCP `host:port` (contains `:`);
3. any device in state `device`.

Observed this run: `localhost:38639`. Historically observed fallback port: `37685`
(differs per LADB session — never treat as fixed).

## 7. Operational lessons discovered

1. `rish` **requires** `RISH_APPLICATION_ID` and `MANAGER_APPLICATION_ID` in the
   environment; without them it aborts without executing anything (hit on first kill attempt).
2. rish `exit 255` after killing the server is **expected** (its transport dies with the
   server). Truth lives in `ps`, not in exit codes.
3. `adb shell` (UID 2000) **cannot** kill the server (different uid): kill only via rish.
4. LADB port changes between sessions; scripts must keep dynamic serial detection.
5. Exported rish kit pattern is always `rish -c "cmd"`; without `-c` the server treats the
   command as a script path and dies with exit 127 (`RISH: exited with 127`).

## 8. Restrictions honored

- Buffy: NOT modified.
- No apps installed.
- No root used or obtained.
- No PC involved (everything ran on-device: Termux + LADB).
- No `app_process`/`CLASSPATH` intervention.
- No unnecessary architecture: three flat POSIX scripts + evidence files (a fourth,
  `watchdog.sh`, was added later in its own increment — see §10/§12b).
- Reversible: nothing deleted or overwritten; the kill/relaunch cycle mirrors the already
  demonstrated manual procedure.

## 9. Final status

```
LADB_RECOVERY_MECHANICAL                    = VERIFIED
SHIZUKU_FUNCTIONAL_RECOVERY                 = VERIFIED
SERIAL_CHANGE                               = VERIFIED
WATCHDOG_V0                                 = VERIFIED (in-session)
WATCHDOG_V1                                 = VERIFIED (daemonized, session-teardown scope)
MULTI_EVENT_STORM                           = VERIFIED (daemonized)
TERMUX_FORCE_STOP                           = VERIFIED (app-level kill scope)
REBOOT_BOOT_SUPERVISION                     = VERIFIED (boot-glue scope)
SHIZUKU_FUNCTIONAL_POST_REBOOT              = VERIFIED
REBOOT_AUTONOMOUS_RECOVERY                  = NOT_TESTED
REBOOT_PERSISTENCE                          = VERIFIED (boot-glue supervision scope — exact boundaries in §12b)
```

Success criterion met: **LADB → UID 2000 → starter → shizuku_server → successful verification.**

Sealing: this directory is a standalone Git repository (own `.git`, no parent repo mixed in).
Commit chain (real hashes, chronological — verifiable via `git log --oneline`):

```
3efedb7  checkpoint: LADB-Shizuku recovery PoC VERIFIED            (base freeze)
5ded4ee  experiment: LADB serial change — SERIAL_CHANGE_VERIFIED
83ec34f  experiment: watchdog v0 — WATCHDOG_V0 VERIFIED (in-session)
8875abe  docs: consolidate CHECKPOINT.md after serial-change + watchdog v0
a1ff0c4  experiment: watchdog v1 — daemonized supervision via runsv, WATCHDOG_V1 VERIFIED
df7ce59  docs: align token plate with canonical names
b9ca628  experiment: multi-event failure storm — MULTI_EVENT_STORM VERIFIED (daemonized)
075ff50  experiment: termux force-stop — TERMUX_FORCE_STOP VERIFIED (app-level kill scope)
cd2163c  docs: post-force-stop documentary consolidation — commit chain sealed
3760a65  experiment preregistration: REBOOT_PERSISTENCE protocol + pre-state dossier — PLANNED, NOT EXECUTED
d191eb4  preregistration ADDENDUM: user-directed reboot WITHOUT prerequisites — prep aborted, tokens must not flip
```

The reboot-result commit (this consolidation: `report_reboot_persistence.md/.txt` +
`reboot_boot_evidence.log` + this CHECKPOINT update) completes the chain above; its hash
is the HEAD after this commit and is recorded in the report of the session.

Commits `8875abe` and `df7ce59` are documentary-only consolidations (no experiment ran
inside them); their function is token-plate alignment and post-experiment sealing. This
file is a post-increment documentary consolidation of that history.

## 10. Watchdog v0: implemented and VERIFIED (in-session)

Canonical status token: `WATCHDOG_V0 = VERIFIED (in-session)` — introduced in commit
`83ec34f` (`watchdog.sh`, `.gitignore`, `report_watchdog_v0.md/.txt`). The original
deliberate decision to keep the base PoC watchdog-free is preserved in commit `3efedb7`.

Executed result (data from `report_watchdog_v0.md`; nothing was re-executed for this
consolidation):

- Forced DOWN event: `rish -c "kill -9 385"` (single event, operator-forced).
- Detection: watchdog cycle 5, within ~one interval (~3 s), using the conservative
  mechanical criterion — adb `ps` succeeds AND no `shizuku_server` row (a transport
  outage is NOT treated as server death).
- Recovery delegated entirely to `recover.sh` (zero duplicated logic).
- PID transition: `385 → 2624` · stability `N0=N1=N2=N3=2624` ·
  `rish -c "id"` → `uid=2000(shell)`.
- Sustained state: 16 consecutive UP cycles (~1 min) after recovery.
- Watchdog stopped in a controlled way by exact PID (1769), confirmed dead.

What this does NOT demonstrate:

- watchdog persistence as a daemon;
- survival across Termux session teardown (a backgrounded run was observed to die there);
- persistence across reboot;
- recovery across multiple events or a failure storm.

At the v0 freeze those limits were explicit: `WATCHDOG_DAEMON_PERSISTENCE`,
`REBOOT_PERSISTENCE`, `MULTI_EVENT_STORM` (all NOT_TESTED). The first was later
covered at session-teardown scope by `WATCHDOG_V1` (§12b); the token itself is
retired from the plate.

## 11. Roadmap after completed experiments

Executed and verified (chronology in §12b):

- **LADB serial change** — commit `5ded4ee` → `SERIAL_CHANGE = VERIFIED` (serial changed
  in value AND format: `localhost:38639` → `adb-…_adb-tls-connect._tcp.`; scripts ran
  unmodified and detected it dynamically).
- **Watchdog v0** — commit `83ec34f` → `WATCHDOG_V0 = VERIFIED (in-session)` (§10).

Planned, NOT EXECUTED (no run performed as of this consolidation):

- **Watchdog v1 (daemonization)** — **[2026-09-13: EXECUTED and VERIFIED as
  `WATCHDOG_V1` — see §12b; commit `a1ff0c4`.]** Original plan text kept for
  traceability: survive Termux session teardown (Termux:service / wake-lock); result:
  `WATCHDOG_V1 = VERIFIED (daemonized, session-teardown scope)`.
- **Multi-event / failure-storm behavior** — **[2026-09-13: EXECUTED and VERIFIED as
  `MULTI_EVENT_STORM = VERIFIED (daemonized)` — see §12b and
  `report_multi_event_storm.md`; commit `b9ca628`.]**
- **Force-stop of the Termux app itself** — **[2026-09-13: EXECUTED and VERIFIED as
  `TERMUX_FORCE_STOP = VERIFIED (app-level kill scope)` — see §12b and
  `report_termux_force_stop.md`; commit `075ff50`.]**
- **Reboot persistence (Termux:Boot)** — **[2026-09-14 22:36: EXECUTED — reboot performed
  by the user WITHOUT prerequisites (prep had been aborted per the addendum:
  com.termux.boot NOT installed, transport ABSENT at reboot); registered 2026-09-15.
  Result: `REBOOT_BOOT_SUPERVISION = VERIFIED (boot-glue scope)` ·
  `SHIZUKU_FUNCTIONAL_POST_REBOOT = VERIFIED` · `REBOOT_AUTONOMOUS_RECOVERY = NOT_TESTED`
  (server was already UP when the transport returned — no recovery exercised) ·
  `REBOOT_PERSISTENCE = VERIFIED (boot-glue supervision scope)`. See §12b,
  `report_reboot_persistence.md`, preregistration `report_reboot_persistence_prestate.txt`
  + abort addendum.]** Sequence boundary now: session teardown VERIFIED · multi-event
  VERIFIED · force-stop VERIFIED · reboot boot-glue supervision VERIFIED · autonomous
  post-reboot recovery NOT_TESTED.
- **rish kit relocation** — kept as a future regression probe (dex 444 rule on Android
  14+; currently Android 13).

The original serial-change plan (goal, hypothesis, procedure, pass criterion) is
preserved verbatim in this file's history at commit `3efedb7`; it was executed as
planned at `5ded4ee`.

## 12b. Addendum (2026-09-13, later increments — chronological log)

- **Serial change (commit `5ded4ee`):** `SERIAL_CHANGE_VERIFIED` — normal LADB restart
  changed the serial in value AND format (`localhost:38639` →
  `adb-…_adb-tls-connect._tcp.`); scripts detected it dynamically, unmodified. Scope:
  transport detection only (relaunch branch not exercised — server stayed UP).
- **Watchdog v0 (commit `83ec34f`, `report_watchdog_v0.md`):** `WATCHDOG_V0 = VERIFIED`
  — single forced DOWN event (`rish -c "kill -9 385"`) detected by `watchdog.sh` within
  ~3 s, recovery delegated to `recover.sh` → new PID 2624, stable N0–N3, rish functional,
  16 consecutive UP cycles after. The `WATCHDOG` token is superseded by the precise form
  `WATCHDOG_V0 = VERIFIED (in-session)` — never a bare `WATCHDOG = VERIFIED`. Still NOT
  tested at that point: `WATCHDOG_DAEMON_PERSISTENCE` (later covered by
  `WATCHDOG_V1`), `REBOOT_PERSISTENCE`, `MULTI_EVENT_STORM`.
- **Watchdog v1 (daemonization, commit `a1ff0c4`):** `WATCHDOG_V1 = VERIFIED (daemonized, single DOWN
  event)` — runit `runsv` instance (launched detached via `start-stop-daemon`, one
  dedicated supervisor for the service) keeps the watchdog alive across interactive
  session teardown: 16+ min observed across ~15 sessions, and `runsv` respawned the
  watchdog loop after a deliberate kill of its session. The daemon autonomously
  recovered one forced DOWN event (PID 31371 → 2442, N0–N3, rish functional) over the
  dynamic transport, and conservatively skipped cycles while the LADB transport was
  genuinely absent (no false recovery). Required installing `termux-services` 0.13-1 /
  `runit` 2.1.2-4 (first external package in this series). Disclosed defect fixed in
  this increment: `watchdog.sh` v0's `detect_serial()` implemented only the tls-connect
  detection level (host:port serials were invisible to the daemon — the conservative
  skip prevented false recoveries while blind); fixed to the full priority chain and
  verified live. See `report_watchdog_v1.md`. Never summarize as a bare
  `WATCHDOG = VERIFIED`.
- **Multi-event failure storm (commit `b9ca628`, `report_multi_event_storm.md`):**
  `MULTI_EVENT_STORM = VERIFIED (daemonized)` — three sequential forced DOWN
  events under the live daemon (kill -9 chain `2442 → 6444 → 7671 → 8679` on
  serial `localhost:43459`): DOWN detections at cycles 495–497, strictly
  sequential (~3–6 s after each kill); exactly one delegated `recover.sh` per
  event, each with stable N0–N3 and functional `rish -c "id"`; log deltas
  +3 DOWN / +3 OK / +0 FAILED (no false positives, no overlapping recoveries,
  no duplicate processes); `verify.sh` exit 0 afterwards (`UP + FUNCTIONAL`,
  PID 8679); scripts byte-identical throughout. NOT covered by this result:
  `REBOOT_PERSISTENCE`, `TERMUX_FORCE_STOP`, simultaneous (non-sequential)
  failure bursts.
- **Termux force-stop (commit `075ff50`; `report_termux_force_stop.md`, pre-state dossier
  `report_termux_force_stop_prestate.txt`):** `TERMUX_FORCE_STOP = VERIFIED (app-level
  kill scope)` — `am force-stop com.termux` (performed by the user OUTSIDE Termux) killed
  every Termux-UID process (runsv tree, watchdog, adb server — none of the pre-state PIDs
  survived), but `shizuku_server` (UID shell) survived with the SAME PID 8679; serial
  changed `localhost:43459 → localhost:42125` as a consequence (adb-server death → mdns
  re-discovery) and scripts detected it dynamically; termux-services AUTO-REVIVED the
  whole service tree at next app start (watchdog respawned, cycle counter reset to 1 —
  new process, not survival); `verify.sh` exit 0 → UP + FUNCTIONAL; log continuity
  across the ~26 s gap. Explicit distinction: the watchdog did NOT survive the
  force-stop as a process ("daemon survived force-stop" is NOT proven and remains
  unproven/NOT_TESTED at app-kill scope); what IS proven is that the service was
  AUTOMATICALLY RESTORED when Termux started again (auto-revival by termux-services).
  NOT covered: watchdog survival as a process (WATCHDOG_V1's
  "daemonized" scope stays session-teardown, NOT force-stop), `REBOOT_PERSISTENCE`.
- **Reboot persistence (reboot 2026-09-14 22:36, registered 2026-09-15;
  `report_reboot_persistence.md/.txt` + `reboot_boot_evidence.log`; preregistration
  `report_reboot_persistence_prestate.txt`, abort addendum
  `report_reboot_persistence_prestate_addendum.txt`):** The prep had been ABORTED
  (addendum): com.termux.boot NOT installed, transport ABSENT at reboot; the reboot
  proceeded by explicit user decision, with tokens frozen in advance. What happened,
  mechanically: (1) the boot glue `~/.termux/boot/shizuku-watchdog-boot.sh` (created at
  addendum time, inert then) WAS executed at device boot —
  `reboot_boot_evidence.log` written at 22:36:20 BEFORE any interactive session:
  `runsvdir started by boot script`, `runsv shizuku-watchdog: (pid 12658) 3s`; post-boot
  PIDs runsvdir 12649 / runsv 12651 / watchdog.sh 12658 →
  `REBOOT_BOOT_SUPERVISION = VERIFIED (boot-glue scope)` (NOTE: the preregistered H2
  expected Termux:Boot-APP-driven supervision; the app was never installed, so the token
  is claimed at boot-glue scope only — the app-driven variant remains untested);
  (2) transport initially absent — first post-boot `adb devices` EMPTY, watchdog logged
  27 consecutive conservative skip cycles (22:36:24–22:40:48, "transport down is NOT
  server DOWN"), zero false recoveries while blind; (3) MANUAL_INTERVENTION: the operator
  opened LADB and the transport returned as `localhost:37003` (fifth rotation of the
  series; 39703 was pre-reboot) — recorded as manual transport restoration, NOT a
  watchdog capability; (4) server post-reboot: `shizuku_server` UP at PID 6754 when the
  transport returned — a NEW PID (pre-reboot last-known PID was 2593, itself recovered
  from a genuine DOWN→recovery at 22:32 that same evening; 8679 was the pre-addendum
  era) → H1-consistent; who launched it is NOT determinable from the collected evidence
  (recorded as unknown, not guessed) and immaterial to H3 either way — the watchdog
  logged NO DOWN and NO recovery post-reboot (first UP at cycle 28, 22:40:58, zero
  recovery actions) → `REBOOT_AUTONOMOUS_RECOVERY = NOT_TESTED`;
  (5) `verify.sh` exit 0: `UP + FUNCTIONAL`, PID 6754, rish `uid=2000(shell)` →
  `SHIZUKU_FUNCTIONAL_POST_REBOOT = VERIFIED`. Umbrella:
  `REBOOT_PERSISTENCE = VERIFIED (boot-glue supervision scope)` — exactly what is proven:
  Termux:Boot-plugin infrastructure executed the bootstrap; runsvdir + watchdog started
  from boot unattended; the watchdog stayed conservative without a transport; after the
  manual transport restoration it correctly detected the already-running server;
  functionality confirmed. What is NOT proven: autonomous recovery of a dead server
  post-reboot (the preregistration's core H3 scenario — a valid future attempt requires
  transport alive BEFORE reboot, com.termux.boot installed + whitelisted, server DOWN
  when the transport returns); Termux:Boot-app-driven supervision; process survival of
  the server across reboot (disproven in the expected direction: 6754 ≠ 2593 ≠ 8679).
  Verbatim policy: it is NOT correct to say "the watchdog recovered Shizuku after the
  reboot" nor "Shizuku survived the reboot as a process" — the accurate statement is
  "Shizuku was functional post-reboot without the watchdog having to perform a server
  recovery during this experiment; boot-time supervision of the watchdog itself was
  mechanically verified". Never summarize as a bare `REBOOT = VERIFIED`.
- Tokens now (canonical plate, aligned §9/top/§12b): `LADB_RECOVERY_MECHANICAL =
  VERIFIED` · `SHIZUKU_FUNCTIONAL_RECOVERY = VERIFIED` · `SERIAL_CHANGE = VERIFIED` ·
  `WATCHDOG_V0 = VERIFIED (in-session)` · `WATCHDOG_V1 = VERIFIED (daemonized,
  session-teardown scope)` · `MULTI_EVENT_STORM = VERIFIED (daemonized)` ·
  `TERMUX_FORCE_STOP = VERIFIED (app-level kill scope)` · `REBOOT_BOOT_SUPERVISION =
  VERIFIED (boot-glue scope)` · `SHIZUKU_FUNCTIONAL_POST_REBOOT = VERIFIED` ·
  `REBOOT_AUTONOMOUS_RECOVERY = NOT_TESTED` · `REBOOT_PERSISTENCE = VERIFIED
  (boot-glue supervision scope)`.

## 12. Integrity manifest — base freeze (SHA-256 at the `3efedb7` freeze)

```
555b1b92e01d286517b014ce20638e42432e2b4956fe0ed99acb8cda7799c2d8  doctor.sh
b71b1296eb4ea64532e8868bd5168f648f22f1a1f3218590015e3c59c6e1a353  recover.sh
28e7796cf48c366e777a9d0297b341d67423f89ea011b2c3373d2300823358d8  verify.sh
e2b9d0272ff1536388203439a615d694198ff630d3c8b9df065a9b2b8f0f2def  evidence.txt
d381f545386590daca763678b1947fc1612d6939c6c9db6be1b214230d6d4fca  oldpid.txt
```

Self-hash note: a file cannot contain its own SHA-256 without changing it. This
CHECKPOINT.md's hash is therefore computed **after** this freeze and published in the
final report of the session; the `/sdcard/Download` copies are byte-identical to this file.
Verify with: `sha256sum CHECKPOINT.md` inside `~/ladb-shizuku-recovery/`.

### Current manifest (consolidation, 2026-09-13 — hashes computed mechanically, post-`83ec34f` tree)

```
# base-freeze artifacts — unchanged since 3efedb7
555b1b92e01d286517b014ce20638e42432e2b4956fe0ed99acb8cda7799c2d8  doctor.sh
b71b1296eb4ea64532e8868bd5168f648f22f1a1f3218590015e3c59c6e1a353  recover.sh
28e7796cf48c366e777a9d0297b341d67423f89ea011b2c3373d2300823358d8  verify.sh
e2b9d0272ff1536388203439a615d694198ff630d3c8b9df065a9b2b8f0f2def  evidence.txt
d381f545386590daca763678b1947fc1612d6939c6c9db6be1b214230d6d4fca  oldpid.txt

# added at 5ded4ee (serial change)
899265ad59056f9fccb2887ec418d185b932d3b6db833a607224204061219459  report_serial_change.md
ab002d4504c289c97a7541db8ecb8bcc56a76f3ab668e24a054c6565588395ae  report_serial_change.txt

# added at 83ec34f (watchdog v0)
53c9a6d2087bf5ebb367a4aefd9008b2fbe55b43d6f27b0ec074b3d2b6a75b02  watchdog.sh
566662d19e77b30f92d49e034d08ce90248e77cbf9a679ac3b747c41f9e47d35  .gitignore
eda171aff0f807dd1e1ff82c5b31ddb630ca4eb0265407a645da559b71172733  report_watchdog_v0.md
a41450f26b42a93cff8a1c37e8846c5f864da3424a0edcfbf342c2729cb38e26  report_watchdog_v0.txt
```

All hashes were computed with `sha256sum` during this consolidation; the three original
scripts remain byte-identical to the base freeze. `CHECKPOINT.md` cannot contain its own
hash (self-reference problem): its hash changes with every edit and must be verified
externally via `sha256sum CHECKPOINT.md` after each commit. The `report_poc_*` and
`report_watchdog_v0` Spanish/plain companion files are also versioned (sizes in §13).

### Current manifest (2026-09-13, post-`075ff50` tree — all 22 tracked files plus this document; hashes via `sha256sum` over `git ls-files`)

```
# base freeze (3efedb7) — unchanged in the working tree ever since
555b1b92e01d286517b014ce20638e42432e2b4956fe0ed99acb8cda7799c2d8  doctor.sh
b71b1296eb4ea64532e8868bd5168f648f22f1a1f3218590015e3c59c6e1a353  recover.sh
28e7796cf48c366e777a9d0297b341d67423f89ea011b2c3373d2300823358d8  verify.sh
e2b9d0272ff1536388203439a615d694198ff630d3c8b9df065a9b2b8f0f2def  evidence.txt
d381f545386590daca763678b1947fc1612d6939c6c9db6be1b214230d6d4fca  oldpid.txt
0ad175c4d20c662e8743868bf4d56bc36d6d3860b7c0359cfd9637439fa2e377  report_poc_ladb_shizuku_recovery.md
7ccef8b322e75fa018f76de33eeebea02000b21febd6a27d3ff37945429f475a  report_poc_ladb_shizuku_recovery.txt

# added at 83ec34f (watchdog v0)
566662d19e77b30f92d49e034d08ce90248e77cbf9a679ac3b747c41f9e47d35  .gitignore
53c9a6d2087bf5ebb367a4aefd9008b2fbe55b43d6f27b0ec074b3d2b6a75b02  watchdog.sh  (blob at 83ec34f)
eda171aff0f807dd1e1ff82c5b31ddb630ca4eb0265407a645da559b71172733  report_watchdog_v0.md
a41450f26b42a93cff8a1c37e8846c5f864da3424a0edcfbf342c2729cb38e26  report_watchdog_v0.txt

# added at a1ff0c4 (watchdog v1 — daemonization; watchdog.sh modified: detect_serial full chain)
6f6ed1bd8f343ed4b2a5a144947153948fa716d6f923f993cef098aeda7983a0  watchdog.sh  (current tree)
baffe148fba4c11fd8bb4a787527378d7e48bc2c86300a7b87f309fd99c71edb  install-service.sh
47a587dc575515094999249459e42496d122424a0a3f6347fbbe180f371988b3  service/shizuku-watchdog/run
6008ffbb3b8f588b281223037b00b5bb0389d7af1fbf9338bbc9cac971cf2201  report_watchdog_v1.md
aadd01378618de8e459ecccfa272150cef0b476a34d01dc81dc1bdef1ae5dcd2  report_watchdog_v1.txt

# added at b9ca628 (multi-event storm)
e8a63cecac97629c14ba64770cbd7301d238a592406bd86f339f708df1755f64  report_multi_event_storm.md
a41ec5e2d96c86565eae575cee0ea5200a38f82ac52d23c8491ed3c94269c882  report_multi_event_storm.txt

# added at 075ff50 (termux force-stop)
543a4a6a0e5dde80a02b6a364c15f39ef24fc00e9f7ee50a77f43cb84b31da9d  report_termux_force_stop.md
879ad79d27c665e8d48e4774d405170c33e61054eb681e011c37c1e5e35c7099  report_termux_force_stop.txt
76cdf5bda94714f9bcb35191714c70fd377a838e8cd7cfbd09d85de4b09da058  report_termux_force_stop_prestate.txt
```

### Current manifest (2026-09-15, post-reboot-registration tree — hashes via `sha256sum`; base scripts byte-identical since the base freeze, nothing modified in this consolidation)

```
# state at d191eb4 (pre-registration + abort addendum, committed before the reboot)
7a947948dca4eb073050103b581e4e427e7758875b761e57fbea55852d57c56e  report_reboot_persistence_prestate.txt
8b785e018ba521ce90fcff1bad24c2ac95e4d23882067d5af2b17bafc6a7932f  report_reboot_persistence_prestate_addendum.txt

# added at this consolidation (reboot evidence + result report; reboot 2026-09-14 22:36)
92e5d6439be997b583a66fa5ca86ae1055b50eb2768dcfdbe815ab332a089619  reboot_boot_evidence.log
3a7c8790c1464bf6396869038ca93102e0d55329eac13a35b60baeb61c1cf68b  report_reboot_persistence.md
806088b0c656f81f12a2a818ec76614709056b8a72b505ce012921fd110d648d  report_reboot_persistence.txt
```

All hashes computed with `sha256sum` during this consolidation. The boot evidence log
had been deliberately kept untracked until the post-experiment commit (same pattern as
the force-stop prestate dossier); it survived the reboot on internal storage. The
preregistration still hashes `7a947948…` exactly as pinned in the addendum
(byte-unchanged). The three base scripts (`doctor.sh`, `recover.sh`, `verify.sh`) and
`watchdog.sh` remain byte-identical to their last verified state — no script was touched
in this increment. The earlier manifests above are preserved verbatim as freeze-time
records; this block is the current state.

`watchdog.sh` appears twice by design: `53c9a6d2…` is its blob **at the v0 freeze**
(verified via `git show 83ec34f:watchdog.sh | sha256sum`), `6f6ed1bd…` is the **current
tree** version after the `detect_serial()` fix committed at `a1ff0c4`. The three base
scripts (`doctor.sh`, `recover.sh`, `verify.sh`) hash identically at `3efedb7` and in
the current tree — byte-identical since the base freeze, verified both from git blobs
and from the working tree. The two historical manifests above are preserved verbatim as
freeze-time records; this block is the current state.

## 13. Directory inventory (current — mechanically obtained via `git ls-files` + `wc -c`, 2026-09-15 post-reboot-registration)

All 23 tracked files verified against `git ls-files`; sizes via `wc -c`; "Introduced"
verified mechanically via `git log --diff-filter=A -- <file>`.

| File | Size | Introduced | Role |
|---|---|---|---|
| `.gitignore` | 93 B | `83ec34f` | Keeps `watchdog.log` out of the canonical tree |
| `CHECKPOINT.md` | (changes with each consolidation) | `3efedb7` | This document |
| `doctor.sh` | 2,561 B | `3efedb7` | Full-chain check (exit 0/1/2) |
| `evidence.txt` | 2,357 B | `3efedb7` | Base-experiment session evidence log |
| `install-service.sh` | 2,109 B | `a1ff0c4` | Installs/starts the `shizuku-watchdog` runsv service (termux-services) |
| `oldpid.txt` | 14 B | `3efedb7` | `OLD_PID=12057` |
| `recover.sh` | 3,880 B | `3efedb7` | Recovery with mechanical + functional criteria |
| `reboot_boot_evidence.log` | 147 B | this consolidation | Boot-glue evidence written at device boot (2026-09-14 22:36:20), before any interactive session; kept untracked until the post-experiment commit |
| `report_multi_event_storm.md` / `.txt` | 5,593 / 3,806 B | `b9ca628` | Multi-event failure-storm experiment report |
| `report_poc_ladb_shizuku_recovery.md` / `.txt` | 6,841 / 5,977 B | `3efedb7` | Base full report (Spanish) |
| `report_serial_change.md` / `.txt` | 5,387 / 4,877 B | `5ded4ee` | Serial-change experiment report |
| `report_termux_force_stop.md` / `.txt` | 6,758 / 5,112 B | `075ff50` | Termux force-stop experiment report |
| `report_termux_force_stop_prestate.txt` | 4,590 B | `075ff50` | Pre-state dossier written before the force-stop (survived it on disk) |
| `report_reboot_persistence.md` / `.txt` | 12,590 / 10,851 B | this consolidation | Reboot-persistence result report (O→H→A→E→C) |
| `report_reboot_persistence_prestate.txt` | 9,814 B | `d191eb4` | Reboot preregistration (protocol + H1–H4), written BEFORE the reboot |
| `report_reboot_persistence_prestate_addendum.txt` | 5,014 B | `d191eb4` | Pre-reboot abort addendum (prep aborted; user-directed reboot; H2/H3 declared UNTESTABLE) |
| `report_watchdog_v0.md` / `.txt` | 4,098 / 3,665 B | `83ec34f` | Watchdog v0 experiment report |
| `report_watchdog_v1.md` / `.txt` | 6,514 / 4,278 B | `a1ff0c4` | Watchdog v1 (daemonization) experiment report |
| `service/shizuku-watchdog/run` | 757 B | `a1ff0c4` | runsv run script for the daemonized watchdog |
| `verify.sh` | 1,459 B | `3efedb7` | Final verification (exit 0/1/2) |
| `watchdog.sh` | 3,228 B | `83ec34f` | v0 in-session supervisor; `detect_serial()` fixed to the full chain at `a1ff0c4`; delegates to `recover.sh` |

The freeze-time inventory (base artifacts only) is preserved in git history at commit
`3efedb7`. Total versioned payload excluding this file at consolidation time: 145,958 B
(`wc -c` over `git ls-files` minus `CHECKPOINT.md`).
