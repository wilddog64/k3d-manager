# Bug: dispatch stall, child A: a `stalled` state and a watcher that captures, stops and tells the operator

**Status:** OPEN
**Priority:** P2 (operator, 2026-11-14)
**Waiting on:** operator decision — since 2026-11-16 (intent approval)
**Triage:** patch → v1.44.1 (already planned there, operator 2026-11-14) — operator grooming 2026-11-15 ("Accept as shown")
**Approval:** drafted by Sonnet for Claude review 2026-11-14
**Release:** v1.44.1 patch (operator, 2026-11-14: "go with your recommendation"): detect and page only; the kill and the B/C hooks move to the v1.45.0 plan `dispatch-stall-recovery`
**Intent approved:** pending (Acceptance rewritten 2026-11-16)
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

## Scope for v1.44.1 (operator, 2026-11-14) — supersedes the Fix below where they differ; Acceptance rewritten 2026-11-16

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
`<run>/stall-watch.state`; no blob decoding. Settled 2026-11-16 (read-only evidence; host M4 arm64, macOS, sqlite3 3.51.0, 438 run dirs under
`~/.local/share/k3d-manager/worktrees/*/*.run`, 35 completed agy runs with a `session` file, 570 completed codex runs):

- **(a) agy: which db.** Rule: the `*.db` under `~/.gemini/antigravity-cli/conversations/` held open by a descendant of the
  worker pid in `$run/start` (`lsof -Fn -p <pid>` per descendant; live capture 2026-11-16 12:42Z: `agy` pid 84968, child
  of worker 84953, fd 95u on `4be06c42-....db`, with `-wal` and `-shm` beside it). It works for a first run and for a
  resume alike and needs neither `$run/session` nor argv. Fallback when lsof finds none: the db whose birth time is within
  [agy.log birth, +10 s] when exactly one qualifies. Replay over the 35 completed runs: the session db was born 1.1 to
  2.4 s after `agy.log` in 35 of 35; 31 had exactly one candidate in the 10 s window, 4 had two (parallel starts). With
  zero or two candidates and no lsof hit: no steps signal, use the process-count rule alone for that tick.
  Gotcha measured: `sqlite3 'file:<db>?mode=ro'` on an idle WAL db (no `-shm`) fails with "unable to open database file"
  (rc 14), also in a writable scratch copy; with a live holder (`-wal`/`-shm` present) it opens and counts (35 rows).
  `?immutable=1` opens an idle db but ignores the WAL, so it is wrong for a live one. Rule: always `mode=ro`; an open
  failure is "no information", never "stalled". Healthy steps counts of the 35 runs: 28 to 673 (the 13-hour hang db: 3214
  now after resumes).
- **(b) codex.** Rollout file = the single `rollout-*-<session id>.jsonl` under `${CODEX_HOME:-~/.codex}/sessions`, with
  the id from the `session id:` line of the newest `codex*.log`; its mtime equals its last line's timestamp (30 newest
  files, difference 0.0 s). Longest healthy gap between consecutive lines inside each run's window (log birth to log mtime;
  whole-file gaps up to 67196 s are the days between resumes, not silence): 570 completed runs, longest 111 s, next 88, 86, 84 s; median of per-run maxima 20 s, p90 35 s. Threshold 2700 s is 24 times the worst healthy gap.
  Zero or several matches: fall back to the newest `codex*.log` mtime.
- **(c) process limit: not measured.** Only a 3-process idle agy run and the incident (556, 147 bats) are on record; a
  healthy parallel `make test-all` (`PARALLEL=1`, 4 jobs on the M4) was not run because it is a 15-minute heavy job and the
  brief was read-only. Operator decision below; default stays 200 labelled provisional.
- **Where the steps state lives.** Probe, `status`, `open` and `stalled` write nothing. `<run>/stall-watch.state`
  (`db=<id> steps=<n> since=<epoch>`) is written only by the watcher tick, which refreshes it for every live run from a new
  read-only `stalled --live` listing (slug version run worktree). The probe reads that file: stalled by steps when the live
  count equals `steps` and now minus `since` exceeds `K3DM_DISPATCH_STALL_SECONDS`; no state file means no steps signal yet.
  A changed count or db id is a new baseline.
- **Current release version** = the newest `v*` directory under `$_dispatch_worktree_root` by `sort -V`; older directories
  are never reported.

Open operator decisions: see "Open questions" 4 to 6.

## Fix

Where "Scope for v1.44.1" differs, Scope wins: Fix 1 silence comes from the settled rules (not log mtime), Fix 3, Fix 5.5,
Fix 5.8 and the hook env vars of Fix 6 are out.

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
2. **`status`.** In `_dispatch_status`, the running branch becomes: run the probe; if stalled, `state="stalled (silent ${s}s, ${p} procs)"`, else `state=running`. Every other branch is unchanged.
3. **`open`.** `_dispatch_open` keeps its python ledger pass and its exit code (1 when any row printed, `:1308`). After a
   row is produced, for a task whose worktree `$_dispatch_worktree_root/<version>/<slug>` and run `<worktree>.run` both
   exist, no `exit`/`landed` file and a matching worker, append ` stalled (silent Ns, P procs)` when the probe says
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

Contract A: the `state:` line of `codex-dispatch status`. A new value, `stalled (silent Ns, P procs)`, is added.

Writers (grep `state:` over `bin`, `scripts`, `.claude`, `~/.claude/commands`, `Makefile`):
- `bin/k3dm-codex-dispatch:1026` `echo "state: $state"`: the only real writer. Changes: `state` can be the new value, set in
  the running branch at `:1016-1017`.
- Test stubs that imitate it (not production writers): `scripts/tests/bin/codex_land_pending.bats:38` (`echo "state: $STUB_STATE"`),
  `scripts/tests/bin/orbstack_upgrade.bats:251` (`DISPATCH_STATUS='state: running'`). Unchanged.

Readers:
- `bin/k3dm-orbstack-upgrade:51-52`: `grep -Eq '^state: (running|starting)$'`. Today a `stalled` run would NOT match, so an
  OrbStack upgrade would proceed under a live worker. Changes: regex widened (Fix 8); `orbstack_upgrade.bats:250-254` gains a
  `state: stalled (silent 3000s, 5 procs)` case.
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

Contract B: the rows of `codex-dispatch open`. A row may now end with ` stalled (silent Ns, P procs)`.
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

Contract D (v1.44.1 uses only: `K3DM_DISPATCH_STALL_SECONDS`, `K3DM_DISPATCH_STALL_MAX_PROCS`, `K3DM_STALL_DISPATCH_BIN`, `K3DM_STALL_NOTIFY_BIN`, `$run/stall-handled-<id>`, `$run/stall-<ts>/`, `$run/stall-watch.state`, the label; the rest below is v1.45.0). New, no existing readers or writers; `grep -rn 'K3DM_DISPATCH_STALL\|K3DM_STALL_\|dispatch-stall'` found only the
parent bug doc): `K3DM_DISPATCH_STALL_SECONDS`, `K3DM_DISPATCH_STALL_MAX_PROCS`, `K3DM_STALL_DISPATCH_BIN`,
`K3DM_STALL_NOTIFY_BIN`, `K3DM_STALL_KILL_GRACE`, `K3DM_STALL_DRAIN_TIMEOUT`, `K3DM_STALL_DIAGNOSE_TIMEOUT`, `K3DM_STALL_DIAGNOSE_CMD` (child C),
`K3DM_STALL_DRAIN_CMD` (child B), the files `$run/stall-handled-<id>` and `$run/stall-<ts>/` (children B and C read the dir),
and the launchd label `com.k3d-manager.dispatch-stall-watch`.

## Acceptance

Scope: v1.44.1 only (see "Scope for v1.44.1" and "Settled 2026-11-16"). This also fixes the parent bug's symptom
(`docs/bugs/2026-11-14-codex-dispatch-silent-running-raises-no-alert.md`: `running` with no signal and no alert): M1, M2,
M8 to M11 and live E8 are that symptom's acceptance.

```yaml
must:
  M1: a live agy worker whose conversation-db `steps` count is unchanged for more than K3DM_DISPATCH_STALL_SECONDS (state file older than the threshold) makes `status` print `state: stalled (silent Ns, P procs)` with N above the threshold, even when agy.log is fresh or absent
  M2: a live codex worker whose session rollout mtime is older than the threshold makes `status` print the same stalled line, even when codex.log is fresh
  M3: more than K3DM_DISPATCH_STALL_MAX_PROCS processes whose command line contains the worktree path (followed by `/`, space or end of line) make `status` print the stalled line whatever the other signal says; a value of 0 disables the test, a non-numeric value falls back to the default
  M4: the agy db is the one held open by a descendant of the worker pid (first run and `--conversation` resume alike); with no holder, the one db born within 10 s of agy.log; with zero or two candidates there is no steps signal and only M3 applies; a db that cannot be opened read-only counts as no information
  M5: `status`, `dispatch open`, `stalled` and `stalled --live` write, touch or remove nothing under the run dir, the worktree, the ledger or the conversation store; `stall-watch.state` is written only by the watcher tick
  M6: `bin/k3dm-codex-dispatch stalled` prints one TSV line per stalled run (slug version run worktree silent procs), covers only the newest v* directory, is cwd-independent and exits 0 always; `stalled --live` prints slug version run worktree for every live run; both are in the usage text
  M7: one watcher tick on a stalled run writes stall-<UTC ts>/ in the run dir with ps.txt, log-tail.txt, status.txt, diff.patch and summary.txt (a failed step goes to errors.txt and the tick goes on) and leaves every process alive
  M8: the same tick appends exactly one `stall_detected` event to the ledger with ts, version, slug, stall (the stall dir basename), run, reason (silent or procs), silent_s, procs and killed 0
  M9: the same tick sends one plain ASCII notice through K3DM_STALL_NOTIFY_BIN naming slug, version, silence seconds, process count and the evidence path, then writes `notified` in the stall dir
  M10: a notice that fails is logged and retried on the next tick with no second capture, no second ledger event and no second stall dir; a later success writes `notified`
  M11: a second tick on the same incident (`stall-handled-<pid>-<started>`) does nothing; a resumed run (new start marker) that stalls again is a new incident
  M12: scripts/etc/launchd/com.k3d-manager.dispatch-stall-watch.plist.tmpl renders with that label, StartInterval 300, RunAtLoad, the watcher as program, the log path under HOME and a PATH that starts with HOME/.local/bin
  M13: `make install-dispatch-stall-watch` writes the plist under the scratch HOME and boots out then bootstraps only that label; with K3DM_AGENT_LOAD=0 it writes and calls no launchctl; `uninstall-dispatch-stall-watch` boots out that label and removes the plist; dispatch-stall-watch is in the target lists of scripts/tests/bin/makefile_agent_load.bats
  M14: bin/k3dm-orbstack-upgrade refuses on `state: stalled (...)` exactly as on `state: running`
  M15: docs/howto/codex-dispatch.md lists the stalled state, the two env vars, the stall-watch install command, and says plainly that v1.44.1 detects and tells but does not stop anything
must_not:
  N1: a run whose steps count is growing (or whose rollout is fresh) and whose process count is low is reported stalled, including when its agy.log or codex.log is old (positive control, same fixture: freezing the count or aging the rollout makes it stalled)
  N2: the watcher sends any signal to any process: no TERM, KILL or `kill`/`pkill` in bin/k3dm-dispatch-stall-watch, and every fixture pid (target, worktree-lookalike, worker, watcher) is alive after the tick (red-capable: a scratch copy of the watcher with `kill -TERM` added fails the same check)
  N3: the watcher reads, runs or mentions K3DM_STALL_DRAIN_CMD, K3DM_STALL_DIAGNOSE_CMD or their timeouts, and the plist sets any of K3DM_STALL_DRAIN_CMD, K3DM_STALL_DIAGNOSE_CMD or K3DM_HERMES_APPROVAL_DRAIN_URL (red-capable: with the two CMD variables pointing at recorder scripts, a scratch watcher that runs them leaves a record and fails the check)
  N4: a `dispatch open` row of a stalled run differs from the row of the same run when running (control: `status` of that fixture says stalled)
  N5: one incident is captured, ledgered or announced twice (control: a resumed run IS handled once more)
  N6: the agy db is opened read-write or its directory gains or loses a file (a -shm, -wal or journal) because of a probe (red-capable: the same snapshot comparison turns red when the fixture opens the db without mode=ro)
  N7: silence is derived from agy.log or codex.log mtime for a run that has a steps or rollout signal (the frozen-steps run with a fresh log IS stalled; the growing-steps run with a 3000 s old log is NOT)
  N8: a missing or failing notifier, a failing ledger write, a failing git call or an unopenable db stops the tick before the other steps (control: the other steps' outputs exist in the same fixture)
  N9: the ledger event, the Slack notice or summary.txt contains any command-line text, prompt text or credential (the fixture worker argv carries a marker string that must appear in ps.txt only)
  N10: new code reads mtime or time with a BSD flag (`stat -f`, `date -r`, `date -j`); the test PATH carries `stat` and `date` stubs that exit 1 on those flags
  N11: a test or install run touches the real HOME, the real LaunchAgents, the real conversation store, the real ledger or a real launchd label (the fixture asserts its scratch HOME and fake root first)
  N12: the TERM/KILL stop, the drain or diagnose hooks, the `open` row suffix, the K3DM_STALL_KILL_GRACE, K3DM_STALL_DRAIN_TIMEOUT and K3DM_STALL_DIAGNOSE_TIMEOUT variables appear anywhere in the v1.44.1 change (these are v1.45.0 `dispatch-stall-recovery`; N2, N3, N4 are their executable form)
evidence:
  - {id: E1, proves: [M1, M2, M3, M4, N1, N7], kind: offline, intent: "You will see tests that start stub dispatches and read a stalled status in three cases: an agy run whose step count stopped growing, a codex run whose session file went quiet, and a run with far too many processes. A run whose steps keep growing or whose session file is fresh stays running even when its log file is old, and a frozen-steps run is reported stalled even with a fresh log. Database choice is tested with an lsof stub shaped from the 2026-11-16 M4 capture and with a missing or ambiguous database, which must fall back to the process count alone. Today status has no stalled value, so these fail."}
  - {id: E2, proves: [M5, M6, N4, N6], kind: offline, intent: "You will see that asking for status, open, stalled and stalled --live changes nothing: the run folder, the worktree, the ledger and the agent conversation folder are byte-identical before and after, and no extra database file appears. The same comparison turns red when the check is made to open the database for writing or when the watcher runs. Today the subcommand and the stalled value do not exist."}
  - {id: E3, proves: [M7, M8, M9, M11, N2, N5, N9], kind: offline, intent: "You will see one watcher tick on a stalled run save the five evidence files, add one stall_detected line to the ledger with killed 0, and send one short notice, while every process in the test, including a lookalike path, the worker and the watcher, is still alive afterwards. A second tick does nothing, and a resumed run that stalls again is handled as a new incident. The notice and ledger line carry no command-line or prompt text. Today the watcher does not exist, so every case fails."}
  - {id: E4, proves: [M10, N8], kind: offline, intent: "You will see a failed Slack notice logged and retried on the next tick without a second capture or ledger line, and success marked as notified. You will also see the tick finish with its evidence and ledger line even when the notifier is missing, the ledger cannot be written, a git call fails or the database cannot be opened."}
  - {id: E5, proves: [M12, M13, N3, N11], kind: offline, intent: "You will see the plist render with the right label, five-minute interval and a PATH that includes ~/.local/bin, with none of the v1.45.0 hook variables. The install target runs only in a scratch home against a stubbed launchctl: it touches only the dispatch-stall-watch label, writes without loading when K3DM_AGENT_LOAD=0, and the uninstall target removes only that label. The existing agent-load tests now include this target. No real agent is loaded or unloaded."}
  - {id: E6, proves: [M14], kind: offline, intent: "You will see the OrbStack upgrade refuse while a dispatch is stalled, exactly as it refuses while one is running. Today the check ignores the stalled word, so the new case fails."}
  - {id: E7, proves: [N10, N12, M15], kind: offline, intent: "You will see the detector and watcher pass under a PATH whose stat and date reject BSD flags, with a scratch copy that uses stat -f failing the same check, a search showing none of the v1.45.0 stop, hook, timeout or open-suffix names in the change, and the how-to page naming the stalled state, the two settings, the install command and the detect-only behaviour."}
  - {id: E8, proves: [M1, M7, M8, M9, N2], kind: live, intent: "You will see, on the M4 after make install-dispatch-stall-watch, a toy agy dispatch whose step count is frozen (a stub that sleeps) reported as stalled by status after the threshold, then within one 300 s tick: an evidence folder in its run folder, one stall_detected line in the ledger with killed 0, one plain Slack notice, and the sleeping process still alive. This is the 13-hour hang case: the operator is told without asking. Run by the operator or Claude, never Gemini."}
interface:
  - "bin/k3dm-codex-dispatch status|open|stalled|stalled --live (state value `stalled (silent Ns, P procs)`; `stalled` TSV: slug version run worktree silent procs; `stalled --live` TSV: slug version run worktree)"
  - "bin/k3dm-dispatch-stall-watch; make install-dispatch-stall-watch / uninstall-dispatch-stall-watch (K3DM_AGENT_LOAD=0 writes without loading)"
  - "env: K3DM_DISPATCH_STALL_SECONDS (2700), K3DM_DISPATCH_STALL_MAX_PROCS (200, provisional), K3DM_STALL_NOTIFY_BIN, K3DM_STALL_DISPATCH_BIN, CODEX_HOME, K3DM_WORKTREE_ROOT"
  - "run dir: $run/stall-watch.state, $run/stall-handled-<pid>-<started>, $run/stall-<UTC ts>/{ps.txt,log-tail.txt,status.txt,diff.patch,summary.txt,errors.txt,notified}"
  - "ledger.jsonl event stall_detected {ts,event,version,slug,repo,stall,run,reason,silent_s,procs,killed:0} (schema: docs/bugs/2026-11-14-dispatch-stall-d-dashboard.md, Fix 1)"
```

Regression-guard note: M1 to M15 fail on today's tree (no stalled state, subcommand, watcher, template, target or regex).
The must_not items about absent behaviour (N1, N2, N3, N4, N5, N12) are true on today's tree because the feature does
not exist, so each is made red-capable by a control in the same fixture or by a mutation: the aged or frozen run IS
stalled (N1, N7), a scratch watcher copy with `kill -TERM`, with a hook call, or with a row suffix fails the check
(N2, N3, N4), a resumed run IS a new incident (N5), opening the db without `mode=ro` or running the watcher turns the
snapshot comparison red (N6, E2). N10 and N11 are red against a naive implementation through the GNU-first stubs and
the stubbed launchctl. N8 is red against an implementation that exits on the first failed step.

## Files

| File | Change |
|---|---|
| `bin/k3dm-codex-dispatch` | `_dispatch_stall_probe` (steps, rollout, process rules), status branch, `stalled` and `stalled --live`, usage; no `open` change |
| `bin/k3dm-dispatch-stall-watch` | new, mode 0755: state refresh, capture, `stall_detected` event, notice with retry; no stop, no hooks |
| `scripts/etc/launchd/com.k3d-manager.dispatch-stall-watch.plist.tmpl` | new (Fix 6): label, interval, PATH only, no hook variables |
| `Makefile` | `install-dispatch-stall-watch`, `uninstall-dispatch-stall-watch` after `uninstall-repo-sync` |
| `bin/k3dm-orbstack-upgrade` | line 52 regex (Fix 8) |
| `scripts/tests/bin/dispatch_stall_state.bats` | new: E1, E2, the status half of E7 |
| `scripts/tests/bin/dispatch_stall_watch.bats` | new: E3, E4, the watcher half of E7 |
| `scripts/tests/bin/dispatch_stall_watch_install.bats` | new: E5 plist and install (model: `repo_sync_launchd_env.bats`) |
| `scripts/tests/bin/makefile_agent_load.bats` | add `dispatch-stall-watch` to both target lists (E5) |
| `scripts/tests/bin/orbstack_upgrade.bats` | one added case (E6) |
| `docs/howto/codex-dispatch.md` | Fix 9 (E7) |

Test fixtures (all stubbed, from a real read-only capture where one exists):
- Live worker: `load codex_dispatch_helpers`, `dispatch start` with `STUB_SLEEP=60`. Assert the fixture first: scratch HOME,
  `K3DM_WORKTREE_ROOT` and a fake `~/.gemini/antigravity-cli/conversations` and `CODEX_HOME` under `$BATS_TEST_TMPDIR`, and
  `status` says `running` before the signal is aged.
- agy db: a small WAL sqlite file with a `steps` table in the fake store, a `lsof` stub on PATH printing the db for the worker's
  descendant (header comment: shape from `lsof -Fn -p` on the M4, 2026-11-16, agy 84968), the db held open by a real
  `sqlite3` child so `-shm` exists. A second case leaves it idle: `mode=ro` must fail and mean no information (captured
  2026-11-16, M4, sqlite3 3.51.0: rc 14).
- codex rollout: a JSONL file named `rollout-<ts>-<session id>.jsonl` whose mtime is set with `perl -e 'utime($t,$t,$f)'`; the
  `codex.log` first line `session id: <id>`.
- Fake process table: a `ps` stub first on PATH (real `/bin/ps` for `-p`; fixture lines for `-axo pid=,ppid=,command=`;
  header comment: shape captured on macOS, host and date of capture). Real `sleep 300` bystanders and targets are cleaned
  up in teardown after asserting their path starts with `$BATS_TEST_TMPDIR`.
- Stubs on PATH for `launchctl`, `ssh`, `kubectl`, `curl`, `security`, and the GNU-first `stat`/`date`; `K3DM_STALL_NOTIFY_BIN` a recorder;
  `PUSHGATEWAY_URL=http://127.0.0.1:9`. The install test follows `makefile_agent_load.bats` (scratch HOME, stub `launchctl`,
  `id` returning 501).

## Rollout

1. Lands after `docs/plans/v1.44.0-parallel-offline-tests.md` Part B: both edit the Makefile (Part B edits `test-all`; this
   adds two targets), and the dispatch WIP rule allows one dispatch per file.
2. After landing and CI green: the operator runs `make install-dispatch-stall-watch` on the M4 (operator's tmux; it boots
   out and bootstraps the label). Confirm `launchctl print gui/$(id -u)/com.k3d-manager.dispatch-stall-watch` and the log file.
3. Confirm Keychain item `k3dm-slack-webhook` exists on the M4: `security find-generic-password -a k3dm -s k3dm-slack-webhook`
   (no `-w`). If missing, the operator adds it first (`docs/howto/platform-ops-notifications.md:42`).
4. Live check E8 (Claude or operator).
5. Hooks stay unset until children B and C land.

## Open questions

1. Is 200 processes right? It is a default chosen from the incident (556 descendants, 147 bats) and the workaround limit
   (60 `bats-exec`). Nobody has measured a healthy `make test-all` after Part B's parallelism. The worker records the peak
   process count of one healthy parallel run in its report; the operator may raise the default before E7.
2. Does the M4 hold `k3dm-slack-webhook`? `secrets.hub.list:17` declares it for the hub only. Rollout step 3 checks it.
3. Descendants: Fix 5.5 also stops descendants of matching pids, because bats children may not carry the worktree path in
   argv. The parent asked for command-line match only. If the reviewer wants the stricter rule, drop the descendant clause
   and accept orphaned bats processes after a kill.
4. Process-count default (settled item c): keep 200 provisional (recommended; the incident was 556 and healthy parallel
   runs are expected well below) or disable the trigger (`K3DM_DISPATCH_STALL_MAX_PROCS=0`) until Claude measures a
   healthy `make test-all` peak on the M4. Operator decides.
5. Steps signal needs the watcher to have seen the run for 2700 s before `status` can say stalled by silence (state file
   written only by the watcher). Accepted, or let `status` write the state (breaks the read-only rule). Recommended: accepted.
6. Ambiguous or missing db with no lsof hit falls back to process count alone, so a hang with few processes goes
   undetected on that tick. Accepted, or treat as unknown and page after 2700 s of log silence (the old rule). Recommended: accepted.

## Worker definition of done

- Change only the files in the table. Offline tests only: no cluster, no network, no real launchd, no real conversation
  store. Stub `launchctl`, `ssh`, `kubectl`, `curl`, `security` on PATH; scratch `HOME`; `PUSHGATEWAY_URL=http://127.0.0.1:9`.
  Never run `make install-dispatch-stall-watch` or any `install-*` target unstubbed: it boots out by label even with a scratch HOME.
- Do not implement or leave stubs for the TERM/KILL stop, the drain or diagnose hooks, their env vars or the `open` suffix.
- Show E1 to E6 red on today's tree (subcommand, script, template, target and regex absent), then green. Show the E7 guard
  red on a scratch copy that uses `stat -f`; show each of N1 to N7 red on its stated control or mutation.
- Run from the repo root, each command pasted with its rc and the proving lines, every error seen listed:
  `bats scripts/tests/bin/dispatch_stall_state.bats scripts/tests/bin/dispatch_stall_watch.bats scripts/tests/bin/dispatch_stall_watch_install.bats scripts/tests/bin/makefile_agent_load.bats scripts/tests/bin/orbstack_upgrade.bats scripts/tests/bin/codex_dispatch_worker.bats scripts/tests/bin/codex_dispatch_agy.bats scripts/tests/bin/codex_dispatch.bats scripts/tests/bin/codex_dispatch_abandon.bats scripts/tests/bin/codex_land_pending.bats`
  and `shellcheck bin/k3dm-dispatch-stall-watch bin/k3dm-codex-dispatch` if shellcheck is present (report if not).
- Rerun any red outside the worker sandbox before calling it a regression (seatbelt can fake both greens and reds).
- Leave changes uncommitted; do not push; do not run E8 (operator or Claude); do not touch `docs/bugs/`.
