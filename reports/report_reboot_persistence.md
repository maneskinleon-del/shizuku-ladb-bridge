# Experiment Report — Reboot persistence (Termux:Boot scope; H3 explicitly NOT tested)

**Date:** reboot 2026-09-14 22:36 (evidence collected ~22:36–22:54); registered 2026-09-15
**Repo:** ~/ladb-shizuku-recovery (standalone, canonical source)
**Checkpoint of departure:** `d191eb4` (clean; only `reboot_boot_evidence.log` untracked on disk — it survived the reboot by design)
**Device:** Xiaomi Mi 10 (umi) · Android 13 (API 33) / HyperOS
**Pre-registration:** `report_reboot_persistence_prestate.txt` (protocol + hypotheses H1–H4, written BEFORE the reboot)
**Addendum:** `report_reboot_persistence_prestate_addendum.txt` (prep ABORTED — com.termux.boot NOT installed; user-directed reboot without prerequisites; tokens must not flip; H2/H3 declared UNTESTABLE for this reboot)
**Companion log:** `reboot_boot_evidence.log` (written by the boot glue at boot, before any interactive session)

---

## 0. What this experiment IS and IS NOT (read before quoting anything)

This was the **user-directed reboot WITHOUT prerequisites** of the addendum: Termux:Boot
was never installed, and the transport was **absent** at reboot time. What it tested,
mechanically, is the **boot-time supervision chain (H2's mechanics via the boot glue +
termux-services)** and the **conservatism of the watchdog while blind (H1-consistent
observation)**. What it did **not** test:

- **H3 / `REBOOT_AUTONOMOUS_RECOVERY` = NOT_TESTED.** No dead post-reboot server was
  ever recovered: the server was already UP (PID 6754) when the transport returned.
  The watchdog never saw a DOWN post-reboot (27 consecutive conservative skips, then
  UP). No recovery was delegated — none was needed, none occurred.
- The server did **not literally survive** as a process: pre-reboot PID was 2593
  (itself recovered from an earlier DOWN that same evening — 8679 was dead before that),
  post-reboot PID was 6754. Correct phrasing: *"Shizuku was functional post-reboot
  without the watchdog having to perform a server recovery during this experiment."*
- The transport was restored **manually by the operator via LADB**. That is a recorded
  MANUAL_INTERVENTION for transport restoration — not an autonomous watchdog recovery.

Per the preregistration logic and the addendum: **no experiment token flips beyond the
scope explicitly recorded here.** `REBOOT_PERSISTENCE = VERIFIED` is claimed ONLY under
the explicitly scoped, documented meaning below — the original H2-as-preregistered
(app-driven Termux:Boot) was inoperative, and H3 was not exercised at all.

## 1. OBSERVATION (pre-reboot state, mechanically captured)

- Repo clean at `d191eb4`. Scripts byte-identical to the base freeze (SHA-256 in the
  dossier). Watchdog: v1 daemonized (runsv), interval 10 s.
- **Boot glue existed and was executable:** `~/.termux/boot/shizuku-watchdog-boot.sh`
  (`-rwx------`, 713 B, mtime Sep 13 12:28 — created at addendum time, INERT then).
- `reboot_boot_evidence.log` did NOT exist yet (created by the boot itself later).
- **Supervision alive:** `runsv shizuku-watchdog` active; `watchdog.sh` running.
- Transport at that point: `localhost:39703` (state `device`).

## 2. HYPOTHESIS (per prestate dossier; abbreviated)

- **H1:** `shizuku_server` does NOT survive the reboot (expected: absent or new PID once
  the transport returns). A same-PID-across-reboot result would be a measurement error.
- **H2 (REBOOT_BOOT_SUPERVISION):** runsvdir/runsv/watchdog already running at first
  post-boot inventory WITHOUT opening Termux interactively.
- **H3 (REBOOT_AUTONOMOUS_RECOVERY):** once the transport returns, the watchdog detects
  the server DOWN and `recover.sh` relaunches it autonomously (new PID, N0–N3, rish OK,
  zero manual recovery commands).
- **H4 (REBOOT_PERSISTENCE):** H2 AND H3 AND full-chain functionality.

**Declared before the fact (addendum):** with Termux:Boot not installed and the
transport down at reboot time, H2 and H3 were **UNTESTABLE this reboot**; H4 must not
flip. The reboot proceeded anyway by explicit user decision.

## 3. ACTION (what actually happened, in order)

1. **Reboot performed by the user, outside Termux** (normal Android reboot). Everything
   Termux-UID died — that was the experiment, not a failure. ~1 minute wait; neither
   Termux nor LADB was opened during that first post-boot window.
2. Termux was opened **only to collect evidence** (no manual starts of anything).
3. LADB was opened afterwards **to restore the transport** — labeled here as
   **MANUAL_INTERVENTION (transport restoration only)**. No manual server action was
   taken at any point; `recover.sh` was never run by hand; no scripts were modified.

## 4. EVIDENCE (all mechanically observed; quoted verbatim)

### 4.1 Boot-time supervision — `REBOOT_BOOT_SUPERVISION = VERIFIED`

`reboot_boot_evidence.log` (written by the boot glue BEFORE any interactive session;
this file is new in the tree):

```
=== boot 2026-09-14 22:36:20 ===
runsvdir started by boot script
run: /data/data/com.termux/files/usr/var/service/shizuku-watchdog: (pid 12658) 3s
```

Post-boot process inventory (observed): `runsvdir` PID 12649 · `runsv shizuku-watchdog`
PID 12651 · `watchdog.sh` PID 12658.

**Distinction recorded:** the preregistered H2 expected **Termux:Boot (com.termux.boot)
app-driven** boot supervision. That app was NOT installed; what ran was the **boot glue
script** in `~/.termux/boot/`, executed by Termux:Boot-plugin infrastructure (Termux
app's boot receiver path) at device boot, before any interactive Termux open. The
token is claimed at this **boot-glue scope** — the Termux:Boot-app-driven variant
(preregistered H2) remains untested and would require installing com.termux.boot.
Mechanically demonstrated: the bootstrap ran from boot, unattended, and started
runsvdir + the watchdog before any operator action.

### 4.2 Transport initially absent — watchdog stayed conservative (no false recovery)

First post-boot `adb devices` (opened in Termux): **empty list** — no ADB transport.

`watchdog.log`, post-boot session (new `watchdog v0 started` at 22:36:21, cycle counter
reset — new process, same mechanics as force-stop):

```
2026-09-14 22:36:21 watchdog v0 started (interval=10s, log=pwd)
2026-09-14 22:36:24 cycle 1: no adb transport — skipping (transport down is NOT server DOWN)
...
2026-09-14 22:40:48 cycle 27: no adb transport — skipping (transport down is NOT server DOWN)
```

27 consecutive conservative skips (~4.5 min) while the transport was absent: the
watchdog did NOT attempt any recovery while blind. The DOWN criterion held —
"transport down is NOT server DOWN".

### 4.3 MANUAL_INTERVENTION — transport restored via LADB

The operator opened LADB; the transport came back as **`localhost:37003`** (third
serial rotation recorded in this series: 43459 → 42125 → 38121 → 39703 → 37003).
This is recorded as a **manual transport restoration**, NOT a watchdog capability and
NOT an autonomous recovery. Nothing else was touched manually.

### 4.4 Server post-reboot — UP when first observable (H1-consistent observation)

With the transport available, the process table showed:

```
 6754 shell        shizuku_server
```

`shizuku_server = PID 6754` — a NEW PID (pre-reboot last-known PID was **2593**; and
2593 was itself the product of a same-evening recovery: PID 8679 had gone DOWN and was
relaunched by the watchdog at 22:32, serial `localhost:39703`). Mechanical conclusion:
the server did not literally persist across the reboot as a process — a fresh instance
was already running when the transport returned. Who started it is **NOT determinable
from the collected evidence** (candidates: Shizuku app autostart path, adbd starter,
operator-adjacent actions around LADB) — recorded as an **unknown, not guessed**, and
immaterial to H3's verdict either way: no recovery was delegated by the watchdog
post-reboot.

Watchdog cycles after transport restoration (log continuity, same watchdog process):

```
2026-09-14 22:40:58 cycle 28: UP serial=localhost:37003 pid=6754
2026-09-14 22:41:08 cycle 29: UP serial=localhost:37003 pid=6754
2026-09-14 22:41:39 cycle 32: UP serial=localhost:37003 pid=6754
```

First observed UP: cycle 28 at 22:40:58 — the watchdog **correctly detected the server
as UP on its first cycle with a transport**, with zero recovery actions in between.

### 4.5 Functional proof — `SHIZUKU_FUNCTIONAL_POST_REBOOT = VERIFIED`

```
== ladb-shizuku-recovery :: verify ==
serial ...................... localhost:37003
shizuku_server .............. UP (PID 6754, user shell)
rish functional probe ....... OK (rish -c id -> uid=2000 shell)
VERDICT: UP + FUNCTIONAL
```

`verify.sh` exit 0. Full chain post-reboot: **transport → UID 2000 → shizuku_server →
rish functional.**

### 4.6 Boundary data (same-evening context, mechanically from watchdog.log)

```
2026-09-13 07:39:21 cycle 418: DOWN ... -> invoking recover.sh
2026-09-13 07:39:21 recovery #1 FAILED (recover.sh exit=1)   [pre-addendum, transport died mid-recovery]
2026-09-14 22:32:18 cycle 136: DOWN serial=localhost:39703 (ps ok, no shizuku_server) -> invoking recover.sh
2026-09-14 22:32:37 recovery #1 OK (new pid=2593)            [pre-reboot, genuine DOWN->recovery]
2026-09-14 22:36:21 watchdog v0 started (interval=10s, log=pwd)   [post-boot, counter reset]
2026-09-14 22:40:58 cycle 28: UP serial=localhost:37003 pid=6754  [first UP, post-transport]
```

The pre-reboot recovery (2593) happened BEFORE the reboot and belongs to the previous
watchdog session; it is context, not part of the reboot boundary. Across the reboot
boundary itself: 27 skips → first UP at 6754 → sustained UP (≥ 60 cycles, 22:40–22:54,
log still growing when evidence was collected). **No DOWN line, no recovery line, no
FAILED line in the entire post-reboot session.**

## 5. CONCLUSION

**REBOOT_PERSISTENCE = VERIFIED (boot-glue supervision scope — explicitly bounded)**
**REBOOT_BOOT_SUPERVISION = VERIFIED (boot-glue scope; Termux:Boot-app variant untested)**
**SHIZUKU_FUNCTIONAL_POST_REBOOT = VERIFIED**
**REBOOT_AUTONOMOUS_RECOVERY = NOT_TESTED**

What is mechanically demonstrated (the five claims that make up the scoped verdict):

1. **Termux:Boot-plugin infrastructure executed the bootstrap** from `~/.termux/boot/`
   at device boot (evidence log written 22:36:20, before any interactive session).
2. **runsvdir + runsv + watchdog started from boot, unattended** (PIDs 12649/12651/12658),
   without opening Termux interactively.
3. **The watchdog remained conservative without a transport** — 27 consecutive skips,
   zero false recoveries while blind.
4. **After the operator manually restored ADB via LADB, the watchdog correctly detected
   the already-running server** (first UP at cycle 28, PID 6754, zero recovery actions).
5. **`verify.sh` confirmed full functionality** post-reboot (UP + FUNCTIONAL, rish OK).

What is explicitly NOT demonstrated:

- **Autonomous recovery of a dead server post-reboot (H3)** — the core scenario the
  original preregistration targeted. A valid future attempt requires, per the
  preregistration: transport alive BEFORE reboot, Termux:Boot (com.termux.boot)
  installed + whitelisted, and the server in a DOWN state when the transport returns.
- **Termux:Boot-app-driven supervision** (preregistered H2 variant).
- **Process survival of the server across reboot** — disproven in the expected
  direction (new PID 6754 ≠ 2593 ≠ 8679), consistent with H1.
- Who launched the post-reboot server instance (no evidence collected; unknown).

**Over-interpretation guard (verbatim policy):** it is NOT correct to say "the watchdog
recovered Shizuku after the reboot", and it is NOT correct to say "Shizuku survived the
reboot as a process". The accurate statement: *"Shizuku was functional post-reboot
without the watchdog having to perform a server recovery during this experiment; boot-
time supervision of the watchdog itself was mechanically verified."*

**Side findings:**

- Serial rotation re-demonstrated under the strongest condition yet (full reboot):
  `39703 → 37003`; dynamic serial detection held unmodified.
- The watchdog session boundary (counter reset to cycle 1 at 22:36:21) is mechanical
  proof that the pre-reboot watchdog process died with the reboot — same signature as
  the force-stop boundary (new process, not survival).
- The boot glue's evidence-before-interaction design worked exactly as intended: the
  very first artifact of the experiment (`reboot_boot_evidence.log`) exists precisely
  because no human opened anything first.
