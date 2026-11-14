# Bug: dispatch stall, child A: a `stalled` state and a watcher that captures, stops and tells the operator

**Status:** OPEN
**Priority:** P2 (operator, 2026-11-14)
**Waiting on:** operator decision — since 2026-11-14 (spec intent)
**Approval:** drafted by Sonnet for Claude review 2026-11-14
**Release:** v1.44.1 patch (operator, 2026-11-14: "go with your recommendation"): detect and page only; the kill and the B/C hooks move to the v1.45.0 plan `dispatch-stall-recovery`
**Intent approved:** pending
**Introduced by:** pre-existing
**Should have been caught by:** none
**Prior art:** docs/bugs/2026-11-14-codex-dispatch-silent-running-raises-no-alert.md (parent) — child spec
**Parent:** docs/bugs/2026-11-14-codex-dispatch-silent-running-raises-no-alert.md

## Symptom

Parent doc, "What happened": a `running` agy dispatch sat silent for about 13 hours with 147 bats processes (556
descendants of the agy process) and nobody was told. This child is the detector half (parent "Chosen direction" steps 1
and 2, plus the notice). Children B (approval) and C (diagnosis) plug into it through two hooks and are not in scope.

## Root cause

`_dispatch_status` (`bin/k3dm-codex-dispatch:1003`) turns a live worker into `running` and stops there (`:1016-1017`:
`_dispatch_worker_matches_start` then `state=running`). Nothing compares the log's last write or the worktree's process
count with a limit, and no job exists that looks. `dispatch open` (`:1275`) reads only the ledger, so it cannot tell a
live run from a stuck one either. The existing `stall` gate (`:389-412`) counts finished unsuccessful attempts and is a
different thing; do not reuse its name or code.

## Scope for v1.44.1 (operator, 2026-11-14) — supersedes the Fix below where they differ; Acceptance to be rewritten

**In:** the probe, `status` and the `stalled` subcommand (Fix 1, 2, 4), limited to the current release version; the
watcher's capture (`ps.txt`, `log-tail.txt`, `status.txt`, `diff.patch`, `summary.txt`) and one Slack notice per
incident with retry (Fix 5 minus the stop); the plist and install targets (Fix 6, 7); the OrbStack guard (Fix 8);
docs (Fix 9). The watcher appends one `stall_detected` ledger event per incident (schema in
`docs/bugs/2026-11-14-dispatch-stall-d-dashboard.md`, Fix 1, with `killed: 0`), so the v1.45.0 dashboard has history.

**Out (to v1.45.0 `dispatch-stall-recovery`):** the TERM/KILL stop (Fix 5.5), the drain and diagnose hooks with their
timeouts and env vars, the `open` row suffix (Fix 3). M3, M5's stop, M6, M9, N2 and N6's hook half are dropped.

**Liveness signal: not the log.** agy writes its log only at exit (`bin/k3dm-codex-dispatch:232`); a healthy run,
`v1.43.15/hub-promote-keeps-promoter-commits-r4.run`, had a 2-line log written 3438 s after start. The agy conversation
store records every step. Proof, M4, 2026-11-14 ~15:30Z, agy conversation
`~/.gemini/antigravity-cli/conversations/3d708e68-6aae-4d59-bc3b-c38bef0fb521.db` (Part B, 1435 rows in `steps`),
step timestamps read from the `steps.metadata` blobs: one 803-minute gap from 2026-11-14 01:38:44Z, four minutes after
correction 3 started (the 13-hour hang); the next longest gaps 21 and 13 minutes; at the same moment `agy-5.log` was
1630 s old while the newest step was about 7 minutes old. Rule for agy: stalled when `select count(*) from steps`
(read-only, `mode=ro`) has not grown for `K3DM_DISPATCH_STALL_SECONDS` (default 2700), tracked across ticks in
`<run>/stall-watch.state`; no blob decoding. Open before dispatch:
- which conversation db a first agy run uses: `$run/session` is written only at exit (`:167-170`), and resumes carry
  `--conversation <id>` in argv; a first run needs a rule (for example, the db created after `$run/start` whose argv
  match is unique), or falls back to the process-count rule alone;
- codex: the session rollout under `~/.codex/sessions/` appends one JSON line per event; capture a past dispatch's
  longest healthy gap before using its mtime;
- the process-count rule stays as a second trigger, its 200 default replaced by a measured value.

## Fix

1. **Probe (dispatcher, read-only).** New function `_dispatch_stall_probe <worktree> <run>` in
   `bin/k3dm-codex-dispatch`. Called only from the running branch, after `_dispatch_worker_matches_start` succeeds. It
   prints `<silent_seconds> <proc_count>` and returns 0 when stalled, 1 when not. It writes nothing anywhere.
   - `silent_seconds` = now minus the mtime of the newest of `$run/agy.log`, `$run/agy-[0-9]*.log`, `$run/codex.log`,
     `$run/codex-[0-9]*.log` (the names `_dispatch_worker` writes, `:230,:253`); if none exists, the mtime of `$run/start`.
   - `proc_count` = processes whose command line contains the worktree path followed by `/`, whitespace or end of line (so
     `.../one` does not match `.../one-two`). Read from `ps -axo pid=,ppid=,command=`. Pass the path to awk or perl through
     the environment, not argv, and drop the probe's own pid and its descendants, or the probe counts itself.
   - Stalled when `silent_seconds > K3DM_DISPATCH_STALL_SECONDS` (default 2700) or `proc_count >
     K3DM_DISPATCH_STALL_MAX_PROCS` (default 200). A value of 0 disables that test; a non-numeric value falls back to the
     default.
   - Defaults: 2700 s is 45 minutes, the parent's number, and sits above the 1800 s `alarm` cap the correction prompts now
     put on every `make`/`bats` command. 200 processes: the incident was 556 descendants and 147 bats processes; the
     operator's workaround limit was 60 `bats-exec` processes. 200 is above that watcher and well under the incident.
     It has not been measured against a healthy parallel `make test-all` (Part B of v1.44.0 adds one); see Open question 1.
   - mtime with `perl -e 'print time-(stat shift)[9]'`, never `stat -f` or `date -r`: on the M4 GNU coreutils come first
     on PATH, so `stat` and `date` are GNU and the BSD flags fail.
2. **`status`.** In `_dispatch_status`, the running branch becomes: run the probe; if stalled, `state="stalled (log
   silent ${s}s, ${p} procs)"`, else `state=running`. Every other branch is unchanged.
3. **`open`.** `_dispatch_open` keeps its python ledger pass and its exit code (1 when any row printed, `:1308`). After a
   row is produced, for a task whose worktree `$_dispatch_worktree_root/<version>/<slug>` and run `<worktree>.run` both
   exist, no `exit`/`landed` file and a matching worker, append ` stalled (log silent Ns, P procs)` when the probe says
   stalled. Rows without a worktree (a ledger-only row) are untouched.
4. **`stalled` subcommand.** `bin/k3dm-codex-dispatch stalled` is read-only, cwd-independent and covers every
   `<version>` directory under `$_dispatch_worktree_root`. One tab-separated line per stalled run: `slug version run
   worktree silent procs`. Exit 0 always. Add it to `_dispatch_usage` (`:292-300`) and to `main` (`:1542-1561`). The watcher
   uses it so the threshold logic lives in one place.
5. **`bin/k3dm-dispatch-stall-watch`** (new, `set -euo pipefail`, public-style functions without underscore only where
   CLAUDE.md allows, private `_` helpers, no inline comments). One tick:
   1. Read `stalled` from `K3DM_STALL_DISPATCH_BIN` (default `bin/k3dm-codex-dispatch` beside the script).
   2. For each stalled run, incident id = `<pid>-<started>` read from `$run/start` (`:93` writes `pid=`, `started=`). If
      `$run/stall-handled-<id>` exists, skip capture and kill (but see 7). A resume writes a new start marker, so a
      second stall of a resumed run is a new incident.
   3. Claim: write `$run/stall-handled-<id>` containing the stall dir path, before anything else.
   4. Capture into `$run/stall-<UTC YYYYmmddTHHMMSSZ>/`: `ps.txt` (`ps -axo pid,ppid,etime,command` rows for the
      worktree), `log-tail.txt` (last 200 lines of the newest log), `status.txt` (`git -C <worktree> status --short`),
      `diff.patch` (`git -C <worktree> diff`), `summary.txt` (slug, version, silent, procs, thresholds). Each git call under
      `perl -e 'alarm shift; exec @ARGV' 60`. A failed capture step writes its error to `errors.txt` in the dir and the tick
      continues: a partial capture beats leaving the run stuck.
   5. Stop: targets are the pids from `ps` whose command line contains the worktree path (same match as the probe) plus
      their descendants by ppid, minus (a) the worker pid from `$run/start`, (b) the watcher's own pid and ancestors.
      Send TERM, wait `K3DM_STALL_KILL_GRACE` seconds (default 10), send KILL to survivors. Never match by name, never use
      `pkill -f`, never touch a pid outside that set. The worker (`k3dm-codex-dispatch _worker`) is left alone on purpose:
      in the real kill the worker exited by itself once its agy child died and recorded `exited nonzero (1)`, which is the
      exit record the later children need.
   6. Notice: `printf '%s\n' <message> | "$K3DM_STALL_NOTIFY_BIN"` (default `bin/k3dm-slack-notify`, which posts through
      `post_summary`, `scripts/lib/hermes/slack.py:26`, with the relay URL from Keychain item `k3dm-slack-webhook`,
      `bin/k3dm-slack-notify:14`). One plain ASCII line: slug, version, silent seconds, procs, count killed, evidence
      path. On success write `<stall dir>/notified`.
   7. Notice retry: for every `stall-handled-<id>` whose stall dir has no `notified`, retry the notice only (no capture, no
      kill). A failed notice is also written to the log; silence was the original bug.
   8. Hooks, absent means skip, failure is logged and never fails the tick. The drain runs under
      `alarm ${K3DM_STALL_DRAIN_TIMEOUT:-240}`; the diagnosis under `alarm ${K3DM_STALL_DIAGNOSE_TIMEOUT:-1200}`, which must stay above
      child C's own 900 s wall clock (Claude review 2026-11-14: one shared 240 s limit would kill every diagnosis). If `K3DM_STALL_DRAIN_CMD` names an executable, run it every tick, stalled
      runs or not, with no arguments (child B); if `K3DM_STALL_DIAGNOSE_CMD` names an executable, run it once per new
      incident with the stall dir as its only argument, after the notice (child C).
   Exit 0 on a clean tick even when a step failed and was logged; non-zero only for a usage or environment error.
6. **`scripts/etc/launchd/com.k3d-manager.dispatch-stall-watch.plist.tmpl`**: copy of
   `com.k3d-manager.repo-sync.plist.tmpl` with label `com.k3d-manager.dispatch-stall-watch`, program
   `{{REPO_ROOT}}/bin/k3dm-dispatch-stall-watch`, `StartInterval` 300, `RunAtLoad`, log
   `{{HOME}}/.local/share/k3d-manager/logs/dispatch-stall-watch.log`, no `PUSHGATEWAY_URL`. EnvironmentVariables (Claude review
   2026-11-14: without them launchd never runs children B and C): PATH = `{{HOME}}/.local/bin:` + repo-sync's PATH (`claude` is
   `~/.local/bin/claude` on the M4); `K3DM_STALL_DRAIN_CMD={{REPO_ROOT}}/bin/k3dm-dispatch-recover`;
   `K3DM_STALL_DIAGNOSE_CMD={{REPO_ROOT}}/bin/k3dm-dispatch-stall-diagnose`; `K3DM_HERMES_APPROVAL_DRAIN_URL` with the value in
   `com.k3d-manager.hermes.plist.tmpl:25-26`. Setting them before B and C land is safe: a missing executable is skipped (M9).
   A test renders the plist and asserts all four keys.
7. **Makefile**: `install-dispatch-stall-watch` and `uninstall-dispatch-stall-watch` copied from `install-repo-sync` /
   `uninstall-repo-sync` (`Makefile:70-92`) with the label, plist and log names changed, honoring `K3DM_AGENT_LOAD=0`.
8. **`bin/k3dm-orbstack-upgrade:52`**: widen the regex to `^state: (running|starting|stalled)`, so a stalled but live
   worker still blocks an OrbStack upgrade (see Contract readers).
9. **Docs**: `docs/howto/codex-dispatch.md:57` gains the `stalled` sentence and the two env vars; a short "stall watch"
   paragraph with the install command and the hooks.

## Contract readers

Contract A: the `state:` line of `codex-dispatch status`. A new value, `stalled (log silent Ns, P procs)`, is added.

Writers (grep `state:` over `bin`, `scripts`, `.claude`, `~/.claude/commands`, `Makefile`):
- `bin/k3dm-codex-dispatch:1026` `echo "state: $state"`: the only real writer. Changes: `state` can be the new value, set in
  the running branch at `:1016-1017`.
- Test stubs that imitate it (not production writers): `scripts/tests/bin/codex_land_pending.bats:38` (`echo "state: $STUB_STATE"`),
  `scripts/tests/bin/orbstack_upgrade.bats:251` (`DISPATCH_STATUS='state: running'`). Unchanged.

Readers:
- `bin/k3dm-orbstack-upgrade:51-52`: `grep -Eq '^state: (running|starting)$'`. Today a `stalled` run would NOT match, so an
  OrbStack upgrade would proceed under a live worker. Changes: regex widened (Fix 8); `orbstack_upgrade.bats:250-254` gains a
  `state: stalled (log silent 3000s, 5 procs)` case.
- `bin/k3dm-codex-land-pending:79-80`: `grep -qx 'state: exited successfully'`, then dies "has not exited successfully". A
  stalled run is correctly refused. No change; `codex_land_pending.bats:67-72` covers the `running` form.
- `docs/howto/codex-dispatch.md:57`: lists the states; gains `stalled`.
- `Makefile:509-510` `codex-status`: prints status verbatim. No change.
- `bin/k3dm-codex-dispatch:1077,1343` (`start`/`resume` guard "Codex is still running") and `:1523` (`prune`, "worker running")
  read the worker marker directly, not the state line. A stalled run still blocks resume until the watcher has stopped it. No change.
- Tests that assert other states and must stay green: `scripts/tests/bin/codex_dispatch_worker.bats:38,60,86,95,115,124`,
  `codex_dispatch_agy.bats:26`. Their runs have a fresh log and a handful of processes.
- `bin/k3dm-dispatch-metrics:896,915,923` and its dashboards (`scripts/tests/bin/test_dispatch_metrics.py:394-405`,
  `scripts/tests/plugins/grafana_dashboard_bugs.bats:1025`): derive `running` from ledger events, not from the state line. A
  stalled run still shows `running` there. Not changed; noted for a later child.
- Claude session watchers (until-loops on `status` that wait for a state other than `running`; see memory
  `feedback_watch_every_dispatch_exit.md`): not in the repo. They stop on `stalled`, which is wanted.
- No reader in `.claude/hooks/` (only `remind-clear-after-land.sh`), `AGENTS.md`, `GEMINI.md` or `.github`.

Contract B: the rows of `codex-dispatch open`. A row may now end with ` stalled (log silent Ns, P procs)`.
- Writer: `bin/k3dm-codex-dispatch:1275-1309` `_dispatch_open`.
- Readers: `~/.claude/commands/post-merge.md:166`, `~/.claude/commands/release-groom.md:54` (human-read lists; no parsing),
  `scripts/tests/bin/codex_dispatch.bats:17-20` and `scripts/tests/bin/codex_dispatch_abandon.bats:83-96` (match `*"v9.9.9
  pending "*" codex_exit"*`; ledger-only rows get no suffix, so unchanged).

Contract C: Keychain item `k3dm-slack-webhook` (the Slack relay URL), read by this child through `bin/k3dm-slack-notify`.
- Readers (all `_keychain_secret("k3dm-slack-webhook")` or its list entry): `bin/k3dm-slack-notify:14`,
  `bin/k3dm-hermes:429,443,453,980,1114`, `bin/k3dm-hermes-setup:31`, `scripts/lib/foundation/scripts/lib/system.sh:2282`,
  `scripts/etc/machine/secrets.hub.list:17`; plus `bin/k3dm-sandbox-reaper:14` (the same helper). New reader: the watcher.
- Writers: `docs/howto/platform-ops-notifications.md:42` (operator `security add-generic-password`); `secrets.hub.list:17`
  declares it for the hub (M5) only. Whether the M4 has the item is unconfirmed (Open question 2). Nothing is written by this child.

Contract D (new, no existing readers or writers; `grep -rn 'K3DM_DISPATCH_STALL\|K3DM_STALL_\|dispatch-stall'` found only the
parent bug doc): `K3DM_DISPATCH_STALL_SECONDS`, `K3DM_DISPATCH_STALL_MAX_PROCS`, `K3DM_STALL_DISPATCH_BIN`,
`K3DM_STALL_NOTIFY_BIN`, `K3DM_STALL_KILL_GRACE`, `K3DM_STALL_DRAIN_TIMEOUT`, `K3DM_STALL_DIAGNOSE_TIMEOUT`, `K3DM_STALL_DIAGNOSE_CMD` (child C),
`K3DM_STALL_DRAIN_CMD` (child B), the files `$run/stall-handled-<id>` and `$run/stall-<ts>/` (children B and C read the dir),
and the launchd label `com.k3d-manager.dispatch-stall-watch`.

## Acceptance

```yaml
must:
  M1: with a live worker whose newest log is older than K3DM_DISPATCH_STALL_SECONDS, `status` prints `state: stalled (log silent Ns, P procs)` with N above the threshold
  M2: with a live worker, a fresh log and more than K3DM_DISPATCH_STALL_MAX_PROCS processes whose command line contains the worktree path, `status` prints the same stalled line
  M3: `dispatch open` ends the row of that task with ` stalled (log silent Ns, P procs)`, and a ledger-only row (no worktree) is unchanged
  M4: computing the state (status, open, stalled) changes nothing under the run dir, the worktree or the ledger
  M5: one watcher tick on a stalled run creates stall-<UTC ts>/ with ps.txt, log-tail.txt, status.txt, diff.patch and summary.txt, then stops the processes whose command line contains the worktree path
  M6: after the stop the worker records the exit and `status` reports `exited nonzero`, not stalled; the watcher exits 0
  M7: the tick posts exactly one notice through K3DM_STALL_NOTIFY_BIN naming slug, silence, process count and the evidence path; a second tick on the same incident posts none and creates no second stall dir
  M8: a failed notice is retried on the next tick without a second capture or kill; success writes `notified`
  M9: an executable K3DM_STALL_DRAIN_CMD runs every tick and K3DM_STALL_DIAGNOSE_CMD runs once per new incident with the stall dir as argument; an absent or non-executable one is skipped with exit 0; a failing one is logged and the tick still exits 0
  M10: the plist template renders with label com.k3d-manager.dispatch-stall-watch, StartInterval 300 and the watcher as program; `make install-dispatch-stall-watch` writes it under HOME and bootouts and bootstraps that label only; K3DM_AGENT_LOAD=0 writes without loading
  M11: bin/k3dm-orbstack-upgrade refuses on `state: stalled (...)` as it does on `state: running`
must_not:
  N1: a run with a fresh log and a low process count is reported stalled (vacuous on today's code, which has no stalled state; positive control is M1 in the same fixture with the log aged)
  N2: the watcher signals any pid whose command line does not contain the worktree path: a bystander whose path is `<worktree>-other`, the worker pid, or the watcher itself (vacuous today, no watcher; positive control: a matching process in the same fixture IS terminated)
  N3: the same incident is captured, killed or announced twice (vacuous today; positive control: a resumed run, new start marker, IS handled as a new incident)
  N4: status, open or stalled write, touch or remove anything (vacuous today; positive control: the watcher on the same fixture does write, and the same snapshot comparison turns red)
  N5: the new code reads mtime or time with a BSD flag (`stat -f`, `date -r`, `date -j`) so it fails under GNU-first PATH (red-capable: the test PATH carries a `stat` and `date` stub that exit 1 on those flags; a scratch script using `stat -f` fails the same check)
  N6: a missing hook, a failing hook or a failing notice stops the tick before capture, kill or the other hook
  N7: any test or install run touches the real HOME, the real LaunchAgents or a real launchd label other than a stubbed launchctl call
evidence:
  - {id: E1, proves: [M1, M2, M3, M4, N1, N4], kind: offline, intent: "You will see tests that start a stub dispatch, age its log or add fake process lines, and read `stalled (log silent Ns, P procs)` from status and open, while a fresh-log run and a ledger-only row stay as they were and the run directory is byte-identical before and after. Today status has no stalled value, so the stalled cases fail."}
  - {id: E2, proves: [M5, M6, M7, M8, N2, N3], kind: offline, intent: "You will see a watcher tick capture the five evidence files, terminate only the process that carries the worktree path while a lookalike path, the worker and the watcher survive, post one notice, and do nothing the second time and a retry-only run after a failed notice. Today the watcher does not exist, so every case fails."}
  - {id: E3, proves: [M9, N6], kind: offline, intent: "You will see the drain hook run on every tick, the diagnose hook run once per incident with the stall directory, missing and failing hooks skipped, and the tick still finish. Today there is no watcher to run them."}
  - {id: E4, proves: [M10, N7], kind: offline, intent: "You will see the install target write the plist into a scratch HOME and call a stubbed launchctl with only the dispatch-stall-watch label, with no real agent unloaded or loaded. Today the target and template do not exist."}
  - {id: E5, proves: [M11], kind: offline, intent: "You will see the OrbStack upgrade refuse with a stalled dispatch status exactly as it does with a running one. Today the regex ignores `stalled`, so the new case fails."}
  - {id: E6, proves: [N5], kind: offline, intent: "You will see the detector and watcher run under a PATH whose stat and date reject BSD flags, still pass, and a scratch copy using `stat -f` fail the same check, so the guard cannot pass for the wrong reason."}
  - {id: E7, proves: [M1, M5, M6, M7], kind: live, intent: "You will see, on the M4 after `make install-dispatch-stall-watch`, a staged toy dispatch whose log is made silent (mtime moved back 50 minutes) reported stalled by status, then within one 300 s tick: an evidence directory in its run folder, its worktree processes gone, status `exited nonzero`, and one plain notice in Slack. Run by operator or Claude, never Gemini."}
interface:
  - "bin/k3dm-codex-dispatch status|open|stalled (state value `stalled (log silent Ns, P procs)`; `stalled` TSV: slug version run worktree silent procs)"
  - "bin/k3dm-dispatch-stall-watch; make install-dispatch-stall-watch / uninstall-dispatch-stall-watch"
  - "env: K3DM_DISPATCH_STALL_SECONDS (2700), K3DM_DISPATCH_STALL_MAX_PROCS (200), K3DM_STALL_KILL_GRACE (10), K3DM_STALL_DRAIN_TIMEOUT (240), K3DM_STALL_DIAGNOSE_TIMEOUT (1200), K3DM_STALL_DIAGNOSE_CMD, K3DM_STALL_DRAIN_CMD, K3DM_STALL_NOTIFY_BIN, K3DM_STALL_DISPATCH_BIN"
  - "run dir: $run/stall-handled-<pid>-<started>, $run/stall-<UTC ts>/{ps.txt,log-tail.txt,status.txt,diff.patch,summary.txt,errors.txt,notified}"
```

Regression-guard note: M1 to M11 fail on today's tree (no stalled state, no watcher, no template, no target, regex).
N1 to N4 are vacuously true there because nothing can stall or be killed yet, so each carries a positive control inside the
same fixture (the aged-log run IS stalled, the matching process IS killed, the resumed run IS a new incident, the watcher
DOES change the snapshot). N5 and N7 are red-capable against a naive implementation through the GNU-first stubs and the stubbed
launchctl. N6 is red against an implementation that runs the hooks before capture and lets one fail.

## Files

| File | Change |
|---|---|
| `bin/k3dm-codex-dispatch` | `_dispatch_stall_probe`, status branch, open suffix, `stalled` subcommand, usage |
| `bin/k3dm-dispatch-stall-watch` | new (Fix 5), mode 0755 |
| `scripts/etc/launchd/com.k3d-manager.dispatch-stall-watch.plist.tmpl` | new (Fix 6) |
| `Makefile` | `install-dispatch-stall-watch`, `uninstall-dispatch-stall-watch` after `uninstall-repo-sync` |
| `bin/k3dm-orbstack-upgrade` | line 52 regex (Fix 8) |
| `scripts/tests/bin/dispatch_stall_state.bats` | new: E1, and the status half of E6 |
| `scripts/tests/bin/dispatch_stall_watch.bats` | new: E2, E3, the watcher half of E6 |
| `scripts/tests/bin/dispatch_stall_watch_install.bats` | new: E4 (model: `repo_sync_launchd_env.bats`, `launchd_reload.bats`) |
| `scripts/tests/bin/orbstack_upgrade.bats` | one added case (E5) |
| `docs/howto/codex-dispatch.md` | Fix 9 |

Test fixtures (all stubbed, from a real read-only capture where one exists):
- Live worker: `load codex_dispatch_helpers`, `dispatch start` with `STUB_SLEEP=60`, then age the log with `perl -e 'utime($t,$t,$f)'`
  (captured note: M4, GNU `stat`/`date` first on PATH, 2026-11-14, parent doc). Assert the fixture first: the worktree is under
  `$BATS_TEST_TMPDIR`, `status` says `running` before aging.
- Fake process table: a `ps` stub first on PATH. For `-p` calls (used by `_dispatch_process_start`) it execs the real
  `/bin/ps`; for `-axo pid=,ppid=,command=` it prints the fixture lines `<pid> <ppid> <command>`. Header comment: shape
  captured from `ps -axo pid=,ppid=,command=` on macOS, host and date of the capture.
- Real bystander and target: `sleep 300` processes started with the worktree path and `<worktree>-other` as an argument; the
  test cleans them up in teardown and asserts the path starts with `$BATS_TEST_TMPDIR`.
- Stubs on PATH for `launchctl`, `ssh`, `kubectl`, `curl`, `security`; `K3DM_STALL_NOTIFY_BIN` a recorder script; scratch
  `HOME`; `PUSHGATEWAY_URL=http://127.0.0.1:9`.

## Rollout

1. Lands after `docs/plans/v1.44.0-parallel-offline-tests.md` Part B: both edit the Makefile (Part B edits `test-all`; this
   adds two targets), and the dispatch WIP rule allows one dispatch per file.
2. After landing and CI green: the operator runs `make install-dispatch-stall-watch` on the M4 (operator's tmux; it boots
   out and bootstraps the label). Confirm `launchctl print gui/$(id -u)/com.k3d-manager.dispatch-stall-watch` and the log file.
3. Confirm Keychain item `k3dm-slack-webhook` exists on the M4: `security find-generic-password -a k3dm -s k3dm-slack-webhook`
   (no `-w`). If missing, the operator adds it first (`docs/howto/platform-ops-notifications.md:42`).
4. Live check E7 (Claude or operator).
5. Hooks stay unset until children B and C land.

## Open questions

1. Is 200 processes right? It is a default chosen from the incident (556 descendants, 147 bats) and the workaround limit
   (60 `bats-exec`). Nobody has measured a healthy `make test-all` after Part B's parallelism. The worker records the peak
   process count of one healthy parallel run in its report; the operator may raise the default before E7.
2. Does the M4 hold `k3dm-slack-webhook`? `secrets.hub.list:17` declares it for the hub only. Rollout step 3 checks it.
3. Descendants: Fix 5.5 also stops descendants of matching pids, because bats children may not carry the worktree path in
   argv. The parent asked for command-line match only. If the reviewer wants the stricter rule, drop the descendant clause
   and accept orphaned bats processes after a kill.

## Worker definition of done

- Change only the files above. Offline tests only: no cluster, no network, no real launchd. Stub `launchctl`, `ssh`,
  `kubectl`, `curl`, `security` on PATH; scratch `HOME`; `PUSHGATEWAY_URL=http://127.0.0.1:9`. Never run
  `make install-dispatch-stall-watch` or any `install-*` target unstubbed: the install boots out by label even with a scratch HOME.
- Show E1 to E5 red on today's tree (new subcommand, script, template, target and regex absent), then green. Show the E6
  guard red on a scratch copy that uses `stat -f` and green on the real files; show N1 to N4 positive controls red when the
  condition is inverted.
- Run from the repo root, each command pasted with its rc and the proving lines, every error seen listed:
  `bats scripts/tests/bin/dispatch_stall_state.bats scripts/tests/bin/dispatch_stall_watch.bats scripts/tests/bin/dispatch_stall_watch_install.bats scripts/tests/bin/orbstack_upgrade.bats scripts/tests/bin/codex_dispatch_worker.bats scripts/tests/bin/codex_dispatch_agy.bats scripts/tests/bin/codex_dispatch.bats scripts/tests/bin/codex_dispatch_abandon.bats scripts/tests/bin/codex_land_pending.bats`
  and `shellcheck bin/k3dm-dispatch-stall-watch bin/k3dm-codex-dispatch` if shellcheck is present (report if not).
- Rerun any red outside the worker sandbox before calling it a regression (seatbelt can fake both greens and reds).
- Leave changes uncommitted; do not push; do not run E7 (operator or Claude); do not touch `docs/bugs/`.
