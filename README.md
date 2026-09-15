# shizuku-ladb-bridge

Supervise and recover the [Shizuku](https://github.com/RikkaApps/Shizuku) server
(`shizuku_server`) on a **root-less Android device**, using the on-device ADB
transport provided by **LADB** — no PC, no root, no unlocked bootloader.

This repository publishes a **completed, frozen proof of concept (PoC)**,
executed and audited on the author's own device. The complete experimental
record — scripts, reports, raw evidence and checkpoint — is included here
verbatim, so the project is self-contained and auditable end to end.

- **Experimental record:** frozen at commit `af14a393efc3506f9cafd6cc4d0a83abed7e74e1`, included verbatim in this repository
- **Status:** frozen — no further experiments are planned or required
- **What this repo is:** the scripts that ran, the evidence they produced, and the reports explaining both
- **What this repo is not:** a product, a library, a modification of Shizuku, or a universal Android solution

The project's name reflects the full chain it puts together — the watchdog is
only the piece that keeps the Shizuku end of that bridge alive:

```text
LADB → ADB transport → Termux → Shizuku native starter → shizuku_server → rish
```

## Who is this for?

This PoC may be useful if:

- you run Shizuku without root;
- you use LADB / Wireless Debugging as the ADB transport;
- you have Termux available on the same device;
- Shizuku's server sometimes dies while the ADB transport remains available;
- you want an auditable recovery mechanism rather than manually restarting Shizuku.

This is not intended as a universal Shizuku reliability solution.

---

## 1. The story of the experiment

### 1.1 Starting point: Shizuku

The experiment starts from **Shizuku** — the original (classic) app used during
the PoC, unmodified, **without root**. Shizuku provides privileged access by
running its server (`shizuku_server`) with ADB's `shell` identity (UID 2000)
and exposing it to apps and terminal tools over Binder.

The catch that motivated this work: **Shizuku's life cycle does not
necessarily match the life cycle of the ADB transport used to start it.** The
server can die while the transport is healthy, and the transport can disappear
while the server is perfectly fine. The goal of the PoC was to study whether a
practical recovery mechanism could keep `shizuku_server` available whenever it
stopped being so.

To be explicit: **this is not a modification of the Shizuku project.** Shizuku
is used exactly as distributed; everything built here lives around it.

### 1.2 The execution environment: Termux

**Termux** was the automation and execution environment. Everything that
constitutes the supervision mechanism was implemented from Termux:

- ADB **transport detection** (dynamic, per run);
- `shizuku_server` **process detection** (via the ADB process table);
- **recovery** by launching Shizuku's native starter through ADB;
- **functional checking** via `rish` (`rish -c "id"` → `uid=2000`);
- a **periodic watchdog** (supervision loop);
- a **persistent service** via runit (`runsv`) / termux-services.

Termux is where the watchdog was built; the scripts in this repository are
exactly what ran there.

### 1.3 The transport: LADB / ADB over Wireless Debugging

ADB access was obtained on-device through **LADB** — an app that runs a local
`adbd` on the Android device itself, paired via **Wireless Debugging**, with no
PC involved. This transport provides a shell with **UID 2000**, precisely the
identity needed to run Shizuku's native starter.

A central finding of the PoC: **the ADB endpoint/serial is dynamic.** It
changed in value *and format* across LADB restarts, app force-stops and a
device reboot (`localhost:38639` → `adb-…_adb-tls-connect._tcp.` →
`localhost:42125` → … → `localhost:37003`). For that reason **the watchdog
never depends on a fixed serial** — every script detects the transport
anew on every run, with a documented priority chain.

And the key distinction the whole design rests on:

```text
ADB transport  ≠  Shizuku server
```

A temporary loss of the ADB transport **must not** be interpreted as a death
of Shizuku. The transport can be absent (LADB closed, reboot, port rotation)
while the server keeps running.

### 1.4 Boot-time execution: Termux:Boot

**Termux:Boot** is a Termux companion add-on (available via F-Droid) that runs
scripts placed in `~/.termux/boot/` when the device finishes booting. This PoC
used such a boot script (`shizuku-watchdog-boot.sh`) to raise the supervision
stack at device boot — `runsvdir` → `runsv` → watchdog — so supervision
exists before anyone opens Termux. The execution left direct evidence:
`evidence/reboot_boot_evidence.log` was written by the boot script at
2026-09-14 22:36:20, **before any interactive session existed**.

One clarification so nothing is over-read: during the experiments the
Termux:Boot app itself was never installed — what mechanically ran was the
boot script, executed by the Termux:Boot-plugin infrastructure. That is what
the evidence matrix records as `REBOOT_BOOT_SUPERVISION = VERIFIED`
(**boot-glue scope**), while **Termux:Boot app-driven supervision
(`com.termux.boot`) = NOT_TESTED**. The evidence matrix in §3 is the
authority. This PoC does **not** claim that Termux:Boot guarantees automatic
recovery of Shizuku after any reboot.

### 1.5 What was built: the recovery watchdog

The main element constructed during the experiment is a **Shizuku recovery
watchdog**. Conceptually:

```text
             ┌─────────────────┐
             │   ADB transport │
             └────────┬────────┘
                      │
                 available?
                 /           \
               NO             SÍ
               │               │
            wait          look for server
                               │
                         ┌─────┴─────┐
                         │           │
                      exists      missing
                         │           │
                        UP       recover.sh
                                     │
                              start Shizuku
                              (native starter)
                                     │
                               verify rish
                              (uid=2000 probe)
```

The **deliberately conservative behavior** is an essential part of the design:

```text
ADB not available
        ↓
do NOT assume Shizuku died
        ↓
wait (skip this cycle)
```

Only when a **valid ADB transport exists** *and* **`shizuku_server` is not
present** in the process table does the watchdog attempt recovery. In
`watchdog.sh` the DOWN criterion is mechanical: `adb ps` **succeeds** and shows
**no** `shizuku_server` row. If `adb` itself fails or returns no transport,
that is transport-absence — not evidence of server death — and the cycle is
skipped. During the reboot experiment the watchdog logged **27 consecutive
conservative skip cycles** (~4.5 minutes) while the transport was absent, with
zero false recoveries.

Recovery is delegated entirely to `recover.sh`, which launches Shizuku's
native starter (`/data/local/tmp/shizuku`) through the transport and accepts
success only with mechanical proof: a **new PID** (different from the
previously observed one), **temporally stable** at checks N0/N1/N2/N3, plus a
**functional probe** (`rish -c "id"` → `uid=2000`). Exit codes alone are never
trusted.

### 1.6 Watchdog evolution: v0 → v1

The real evolution, exactly as it happened (no invented versions):

**Watchdog v0** (in-session, commit `83ec34f`):
- direct, foreground execution;
- detection of a missing server (conservative criterion above);
- recovery delegated to `recover.sh`;
- post-recovery verification (new stable PID + functional rish probe).

**Watchdog v1** (daemonized, commit `a1ff0c4`):
- daemonized execution integrated with **runit / termux-services**
  (one dedicated `runsv` instance, installed by `install-service.sh`);
- survives **interactive session teardown** (observed 16+ min across ~15
  sessions);
- `runsv` **respawns the watchdog** if the watchdog itself is killed
  (supervision of the supervisor);
- **automatic recovery** on observed server death over the dynamic transport
  (one autonomous forced-DOWN recovery demonstrated);
- detection of **the full range of ADB transport formats** — v0 had a defect
  where its serial detection only saw mDNS/tls-connect serials (host:port
  serials were invisible; the conservative skip prevented false recoveries
  while blind); v1 fixed `detect_serial()` to the full priority chain and
  verified it live.

The v1 daemon was subsequently validated under a **multi-event failure storm**
(three sequential forced server deaths, one delegated recovery per event,
commit `b9ca628`) and during a **Termux app force-stop** (commit `075ff50`)
and a **device reboot** (commit `af14a39`) — see the evidence matrix below.

---

## 2. Repository layout

| Path | Role |
|---|---|
| `README.md` | This document |
| `CHECKPOINT.md` | Frozen experiment checkpoint (canonical state + integrity manifest) |
| `doctor.sh` | Full-chain check: adb client → transport → uid 2000 → starter → server → rish |
| `watchdog.sh` | Watchdog v0 loop: distinguishes transport-absent from server-absent; delegates recovery |
| `recover.sh` | Recovery: launches the native starter, enforces mechanical + functional proof |
| `verify.sh` | Final verification: server UP + rish functional |
| `install-service.sh` | Manages the watchdog v1 runit service (`runsv` via termux-services) |
| `service/shizuku-watchdog/run` | runsv service definition (watchdog v1, daemonized) |
| `reports/` | All 17 experiment reports and preregistrations (historical evidence, verbatim) |
| `evidence/` | Base-experiment session evidence: `evidence.txt`, `oldpid.txt`, `reboot_boot_evidence.log` |
| `.gitignore` | Keeps the runtime `watchdog.log` out of the tree |

> **Note for reproducers:** `service/shizuku-watchdog/run` and
> `install-service.sh` hardcode the original device layout (a
> `…/home/ladb-shizuku-recovery` path). They are kept byte-identical to what
> ran. If you reuse them, adjust the `HOME_DIR` and `PREFIX` paths to your
> environment.

## 3. What was demonstrated

| Capability | Status | Scope |
|---|---|---|
| LADB recovery | VERIFIED | mechanical recovery |
| Shizuku functional recovery | VERIFIED | "rish -c id" |
| Dynamic serial | VERIFIED | transport changes |
| Watchdog v0 | VERIFIED | in-session recovery |
| Watchdog v1 | VERIFIED | daemonized |
| Multi-event storm | VERIFIED | N=3 sequential |
| Termux force-stop | VERIFIED | app-level scope |
| Reboot boot supervision | VERIFIED | boot-glue |
| Shizuku functional post-reboot | VERIFIED | functional server |
| Reboot persistence | VERIFIED | bounded scope |
| Autonomous recovery after reboot | NOT_TESTED | untested |
| Termux:Boot app-driven supervision | NOT_TESTED | untested |
| Simultaneous failure burst | NOT_TESTED | untested |

Exactly the distinction **VERIFIED / NOT_TESTED** is used throughout.
`NOT_TESTED` means "this was never exercised" — it does **not** mean FAILED,
and it is not a to-do list. The PoC is closed.

Key demonstrated results (full detail in `reports/` and `CHECKPOINT.md`):

1. **LADB provides the ADB transport dynamically** (on-device adbd, no PC) and
   a UID 2000 shell through it can run Shizuku's native starter.
2. **The transport rotates serial/endpoint** (host:port ↔ mDNS/tls-connect)
   across LADB restarts, force-stop and reboot; all scripts detected it
   dynamically, unmodified.
3. **The watchdog v1 runs daemonized** (runit `runsv` via termux-services) and
   survives interactive session teardown.
4. **The watchdog correctly distinguishes** "transport absent" (conservative
   skip — e.g. 27 consecutive skip cycles post-reboot, zero false recoveries)
   from "server Shizuku absent" (DOWN → delegated recovery).
5. **Recovery uses the existing Shizuku starter**; recovery of multiple
   sequential failures (3 in a row) worked with exactly one delegated
   recovery per event.
6. **A Termux force-stop kills every Termux-UID process** (watchdog, runsv
   tree, adb server) **but `shizuku_server` survives** — it runs in the shell
   UID context, not Termux's.
7. **The Termux:Boot boot glue** (`~/.termux/boot/` script executed by the
   Termux:Boot-plugin infrastructure) started runsvdir + the watchdog
   unattended at device boot, before any interactive session.
8. **After the operator manually restored the transport via LADB** post-reboot,
   the watchdog detected the already-running server (zero recovery actions) and
   `verify.sh` confirmed UP + FUNCTIONAL with `rish -c "id"` → `uid=2000`.

## 4. What was NOT demonstrated

These limits are part of the result and must be preserved when quoting it.
This PoC does **not** claim:

- that **Shizuku survives a reboot** — it does not survive as a process
  (post-reboot PID was new);
- that **the watchdog autonomously recovers Shizuku after any reboot** —
  autonomous post-reboot recovery was never exercised (`NOT_TESTED`; in the
  reboot experiment the server was already running when the transport
  returned and the watchdog performed no recovery);
- that **Termux:Boot guarantees automatic recovery** — only boot-time
  *supervision of the watchdog itself* was mechanically verified, at
  boot-glue scope; the app-driven variant is `NOT_TESTED`;
- that it **works on all Android devices** — validated on exactly one
  (Xiaomi Mi 10 / Android 13 / HyperOS); portability was never a goal;
- that it works **independently of the Shizuku version** — validated on
  13.6.0 only; other versions may differ (starter path, mechanism);
- that there are **no differences between manufacturers/ROMs** — OEM power
  management and boot restrictions vary; none were surveyed;
- that **the ADB transport is always restored automatically** — in the reboot
  experiment it was restored **manually** by the operator via LADB (recorded
  as MANUAL_INTERVENTION); Android restoring it by itself was never observed
  or tested;
- that the watchdog **survived the app-level force-stop as a process** — the
  service tree was auto-revived by termux-services at the next Termux start
  (a different claim);
- **simultaneous (non-sequential) failure bursts** — never tested; only
  strictly sequential events (N=3);
- who launched the post-reboot server instance is **unknown** (not
  determinable from the collected evidence; recorded as unknown, not guessed).

The accurate summary phrasing, for quotation: *"Shizuku was functional
post-reboot without the watchdog having to perform a server recovery during
this experiment; boot-time supervision of the watchdog itself was mechanically
verified."*

## 5. Reproducing the result

Environment where the PoC was validated (**descriptive of that experiment, not
universal requirements** — the technique applies wherever the same primitives
exist):

| Item | Value |
|---|---|
| Device | Xiaomi Mi 10 (`umi`) |
| Android | 13 / API 33 |
| HyperOS | V816.0.4.0.TJBMIXM (user-supplied; not recorded in the versioned evidence) |
| Shizuku | 13.6.0.r1086 (classic RikkaApps) |
| LADB | configured via Wireless Debugging (pairing on-device, no PC) |
| Termux | used as the execution/automation environment |
| Termux:Boot | used for boot supervision (boot-glue script in `~/.termux/boot/`) |
| Root | NO |
| ADB shell UID | 2000 (`context=u:r:shell:s0`) |

Prerequisites (as used by the scripts, exactly as written):

1. **Termux** installed on the device, with `adb` (e.g. `pkg install android-tools`)
   and, for the daemonized variant, `pkg install termux-services` (runit).
2. **Shizuku** installed; its native starter present at `/data/local/tmp/shizuku`
   (Shizuku installs this when started through Wireless Debugging).
3. **LADB** installed and paired (Wireless Debugging), providing the local ADB
   transport. Open it — the transport must be up before recovery is possible.
4. **rish kit** exported from the Shizuku app into Termux at `~/bin/rish` +
   `~/bin/rish_shizuku.dex`, with `RISH_APPLICATION_ID` and
   `MANAGER_APPLICATION_ID` exported (the scripts do this). Keep the `.dex`
   read-only (`444`) — mandatory on Android 14+.

Typical sequence (from this directory):

```bash
./doctor.sh                 # full chain check → exit 0 = UP + FUNCTIONAL
./watchdog.sh 5             # foreground supervision (Ctrl-C stops it)
./recover.sh                # manual recovery attempt (idempotent; no-op if UP)
./verify.sh                 # verdict: UP + FUNCTIONAL

# daemonized supervision (watchdog v1):
./install-service.sh install
./install-service.sh start
sv status "$PREFIX/var/service/shizuku-watchdog"
```

To reproduce a specific experiment (force-down cycle, serial change, failure
storm, force-stop, reboot), follow the procedures described in the matching
report under `reports/`. They are preregistered protocols with their observed
results; this repository deliberately ships **no test harness or automation**
beyond the five scripts above.

> **Ethical/operational note:** recovering Shizuku uses only the identities the
> device already grants (shell UID 2000 via ADB). No root is used or obtained,
> nothing is installed system-wide, and no SELinux policy is touched. Run this
> only on devices you own.

## 6. Limits

- **No root is required** — that is the point — but the PoC **depends on
  LADB/ADB and the corresponding Android environment**: on-device adbd
  (LADB), Termux, and Shizuku's starter in place.
- **The ADB serial is dynamic**; every script detects it per run. Hardcoding a
  serial or port breaks immediately (LADB rotates endpoints).
- **The ADB transport can be temporarily absent** (LADB closed, reboot, app
  force-stop). The watchdog **must not recover on a mere transport absence** —
  it waits. Recovery attempts without a transport are impossible by design.
- **The demonstrated recovery uses Shizuku's native starter**
  (`/data/local/tmp/shizuku`), launched via ADB. No `app_process` or
  `CLASSPATH` manipulation is performed.
- **No autonomous post-reboot recovery is demonstrated** (`NOT_TESTED` —
  see §4). The reboot-related VERIFIED tokens are bounded to their recorded
  scopes and must never be quoted without them.
- The scripts assume a device user named `shell` for `shizuku_server` and the
  exact process name `shizuku_server`; they were validated on **one** device
  with **one** Shizuku version (13.6.0). Behavior on other Android versions,
  OEM ROMs or Shizuku builds is untested.
- The five scripts are POSIX `sh` written for Termux's shell; they contain no
  error-retry backoff, no configuration file, no locking — deliberately.

## 7. Evidence provenance

Everything in `reports/` and `evidence/` is the **frozen experimental
record**, preserved verbatim as sealed at commit
`af14a393efc3506f9cafd6cc4d0a83abed7e74e1`:

- `CHECKPOINT.md` — the frozen checkpoint: status tokens, mechanical evidence
  per increment, SHA-256 integrity manifests, directory inventory.
- `reports/report_poc_ladb_shizuku_recovery.md/.txt` — base experiment (Spanish).
- `reports/report_serial_change.*`, `report_watchdog_v0.*`, `report_watchdog_v1.*`,
  `report_multi_event_storm.*`, `report_termux_force_stop.*` (+ prestate),
  `report_reboot_persistence.*` (+ preregistration and abort addendum),
  `reports/…_prestate*.txt` — one report pair per experiment increment.
- `evidence/evidence.txt`, `evidence/oldpid.txt` — base-experiment mechanical
  evidence (PID transition 12057 → 7793, stability N0–N3).
- `evidence/reboot_boot_evidence.log` — boot-glue evidence written at device
  boot (2026-09-14 22:36:20), before any interactive session.

Interpretation discipline: the reports label **what was observed**
(EXPERIMENTAL EVIDENCE: process tables, logs, exit codes, PIDs) separately
from conclusions drawn from it. Where this README adds explanation, it is
marked as such; inferences are never presented as observed facts. Nothing in
the reports was rewritten in a way that changes their meaning — they are
shipped as they were sealed. Note that most reports are written in Spanish;
`CHECKPOINT.md` and the per-experiment facts quoted here are the authoritative
record.

### Report index

| Experiment | Report | Token |
|---|---|---|
| Base recovery (kill → relaunch → prove) | `report_poc_ladb_shizuku_recovery.md/.txt` | `LADB_RECOVERY_MECHANICAL`, `SHIZUKU_FUNCTIONAL_RECOVERY` |
| Serial change (LADB restart) | `report_serial_change.md/.txt` | `SERIAL_CHANGE` |
| Watchdog v0 (in-session) | `report_watchdog_v0.md/.txt` | `WATCHDOG_V0` |
| Watchdog v1 (daemonized) | `report_watchdog_v1.md/.txt` | `WATCHDOG_V1` |
| Multi-event failure storm | `report_multi_event_storm.md/.txt` | `MULTI_EVENT_STORM` |
| Termux force-stop | `report_termux_force_stop.md/.txt` (+ `_prestate.txt`) | `TERMUX_FORCE_STOP` |
| Reboot persistence | `report_reboot_persistence.md/.txt` (+ `_prestate.txt`, `_prestate_addendum.txt`) | `REBOOT_BOOT_SUPERVISION`, `SHIZUKU_FUNCTIONAL_POST_REBOOT`, `REBOOT_PERSISTENCE` (boot-glue scope) |

## 8. Related work

The findings of this experiment were later consolidated, knowledge-transfer
only, into the author's `shizuku-rikka` skill, which references this PoC
frozen at `af14a39`. No dependency exists in either direction; this project
is fully self-contained.

## License / usage

Provided as-is for study and reproduction of the technique on devices you own.
No warranty. See `CHECKPOINT.md` §8 for the restrictions honored during the
original experiments (no root, no system modification, everything reversible).
