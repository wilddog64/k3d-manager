# Bug: a dispatch that stays `running` with a silent log raises no alert

**Status:** OPEN
**Priority:** P2 (operator, 2026-11-14; was P3)
**Waiting on:** operator decision — since 2026-11-14 (spec intent)
**Approval:** captured by Claude 2026-11-14; operator 2026-11-14 chose the design below: headless Claude diagnosis paid by the API credit, gated by a Slack approval ("if we want to make this safe then we can post an approval request to slack"). Spec not yet written or approved
**Introduced by:** pre-existing
**Should have been caught by:** none
**Prior art:** exact-slug glob: none; `make find-similar-docs` unavailable (vector store needs the hub context, not on the M4); grep of codex-dispatch bug docs for stuck/hang/silent: 2026-10-09 metrics, scope, land and stdout docs, read, different root cause

## What happened

Correction 3 of `parallel-offline-tests-b` (agy, gemini-3.8-flash-medium) started 2026-11-13 17:34 PST. Its test
`makefile_test_all.bats` called `make test-all` with STAGE_* overrides, but the serial path ignored them and re-ran
`bats scripts/tests/bin`, which ran the same test again: 37 nested levels, 147 bats processes, 556 descendants of the
agy process, load average about 2. `agy-4.log` stopped at "root agent idle; waiting for 1 background task(s) to
finish". `codex-dispatch status` reported `running` for about 13 hours, until Claude killed the tree on 2026-11-14
around 15:00Z when the operator asked about progress.

Three Claude watchers (until-loops on `status`) were running the whole time and never fired, because they only checked
for a state other than `running`.

## Why it matters

`status` only learns about a run when the worker exits. Nothing compares the log's last write, or the size of the
process tree, with a limit. The `stall` gate in `bin/k3dm-codex-dispatch` (~389-412) counts unsuccessful attempts that
already finished, so it cannot see a run that never finishes. A stuck run uses up a WIP slot and machine time without
anyone noticing.

## Workaround in use

Claude's per-dispatch watcher now also stops on log silence (log mtime older than 45 minutes) and on a runaway process
count (more than 60 `bats-exec` processes under the worktree). Get the log mtime with `perl -e 'print
time-(stat shift)[9]'`: on the M4, GNU `stat` and `date` come first on PATH, so the BSD flags fail. Correction prompts
now require every `make`/`bats` command to run under `perl -e 'alarm shift; exec @ARGV' 1800`.

## Chosen direction (operator, 2026-11-14) — to be specified

The operator should not have to be the detector. Phase 1, approval-gated:

1. **Detect** — a launchd job on the dispatch host (M4) every 5 minutes: a dispatch still `running` whose log is silent
   for more than 45 minutes, or whose worktree has more than a set number of processes, is stalled. `status` and
   `dispatch open` report `stalled` with log age and process count.
2. **Capture, then stop** — save process tree, log tail and `git diff` into the `.run` directory, then kill only the
   processes under that slug's worktree so `status` records the exit.
3. **Diagnose** — headless `claude -p` in the repo, API key from Keychain `k3dm-anthropic-api-key` into the
   environment (never argv), tools limited to read plus writing one correction prompt, a turn cap, tokens logged to the
   agent-cost dashboard. Output: a diagnosis and `correction-N.md`.
4. **Approve in Slack** — new Hermes repair `r10` "Resume stalled dispatch with Claude's correction", posted with
   `post_interactive` / `interactive_blocks` (`scripts/lib/hermes/slack.py:47`, `approvals.py:57`). Its precondition,
   re-checked on approval: the dispatch is exited, same run number, worktree unchanged since the correction was
   written. One attempt per incident (existing `repairs.py` rule): a second stall pages the operator, no proposal.
5. **Resume** — on Approve, `codex-dispatch resume --reason correction` with that prompt. Landing still needs the
   normal independent verify.

Phase 2 (auto-resume without approval) only after several phase-1 corrections the operator approved unchanged.

Host (operator, 2026-11-14): detector and headless diagnosis run on the M4; the operator adds an M4 Keychain copy of the key. Open for the spec:
every reader of `k3dm-anthropic-api-key` (contract readers rule). Key expires about 2026-12-13 and the credit
2026-12-08: a 401 must surface as a rotate-key alert, not a silent failure.

## Decomposition (Claude, 2026-11-14; complex-bug decomposition trial)

Three subsystems, so three child specs and one integration check. Children land in this order; each is useful alone.

| Child | Spec | Scope |
|---|---|---|
| A | `docs/bugs/2026-11-14-dispatch-stall-a-detector.md` | `stalled` state in `bin/k3dm-codex-dispatch` status/open; `bin/k3dm-dispatch-stall-watch` on launchd every 5 min on the M4: detect, capture evidence into `<run>/stall-<ts>/`, kill only that worktree's processes, post a plain Slack notice; runs the drain from B and the diagnosis from C when present. Only child that edits the Makefile (install target), so it waits for Part B. |
| B | `docs/bugs/2026-11-14-dispatch-stall-b-approval.md` | Relay accepts a `d<N>-<hex8>` action id beside Hermes's `r<N>-<hex8>` (`workers/slack-relay/index.js:4`); `fetch_approvals` gets an id-pattern parameter, Hermes's default unchanged (`scripts/lib/hermes/approvals.py:14,23`); M4 drain posts the proposal with `post_interactive`, re-checks the precondition on Approve, one attempt per stall, then `codex-dispatch resume --reason correction`. Relay redeploy by the operator. |
| C | `docs/bugs/2026-11-14-dispatch-stall-c-diagnose.md` | Headless `claude -p --bare --output-format json --max-budget-usd <cap> --permission-mode dontAsk --allowedTools ...` reading the stall evidence, writing `correction.md` and a diagnosis; key from the M4 Keychain `k3dm-anthropic-api-key` into the environment; usage logged for the agent-cost dashboard; 401 and budget-hit surface as Slack lines. CLI flags proven from Claude Code 2.1.323 `--help`, captured on the M4 2026-11-14. |

Integration check (live, Claude and operator): a staged toy dispatch that hangs, on the M4, end to end to a Slack approval and a resumed run.

## Spec review 2026-11-14 (Fable; blockers checked by Claude)

Verdict: A and C not dispatchable, B needs fixes; D (dashboard, added 2026-11-14 at the operator's request) defines
the stall ledger events that A, B and C must each write.

- **A blocker, confirmed.** agy writes its log only at exit (`--output-format json >"$run/agy.log"`,
  `bin/k3dm-codex-dispatch:232`). A healthy run, `v1.43.15/hub-promote-keeps-promoter-commits-r4.run`, had a 2-line
  log written 3438 s after start, so a 45-minute silence rule would have killed it. Liveness must come from another
  signal (newest mtime under the worktree and `$run/state`, or process-tree CPU time). Replay the rule against existing
  `*.run` dirs before dispatch, and capture agy's TERM behaviour (prove-external-behaviour rule).
- **C blocker, confirmed.** `--add-dir <directories...>` takes several values (Claude Code 2.1.323 `--help`, line 11),
  so a prompt after it is read as a directory. Use stdin or a tool-less single turn: inline the evidence and pass
  `--tools ""`, which also removes the Read-anywhere injection path (finding 8).
- **A major, open.** Matching by worktree path in argv also kills editors, verifier `git -C` runs and other agy
  dispatches whose prompt names the path. Target the worker pid's descendants instead.
- **A major, open.** Rescans can kill the worker's own `git rev-parse HEAD` (`:253`), which writes `violation`.
- **A/B major, open.** An agy run killed before its final JSON has no `$run/session` (`:1353`, `:167-170`), so resume
  fails. Size the grace from a measured TERM-to-JSON time, and have B withhold the card when there's no session.
- **A/B major, open.** A launchd-started resume runs on the plist PATH, not the direnv toolchain. Use `direnv exec`.
- **B major, open.** The card shows the diagnosis but not the correction that becomes the next agent's prompt, and
  model text is unescaped mrkdwn. Show the capped correction in full and escape `&<>`.
- **Minor, open.** Drain timeout 240 s vs a 300 s resume timeout. `_dispatch_open` would show
  `primary_coordinator_cost` as a row's last event (`:1306`). Credit exhaustion is not a 401. Limit `stalled` to the
  current version. Key second-stall on (version, slug). Some evidence ids are mislabelled. Phase-1 cuts: the `open`
  suffix, the drain-health probe, the expiry state machine, the cumulative ledger arithmetic.

## Release split (operator, 2026-11-14: "go with your recommendation")

- **v1.44.1 patch (the bug fix):** child A trimmed to detect, capture and one Slack notice; no kill, no hooks. Liveness
  comes from the agy conversation step count, proven on the 13-hour hang (803-minute gap; healthy gaps at most 21
  minutes): see A, "Scope for v1.44.1". This closes the bug: the operator is no longer the detector.
- **v1.45.0 plan 5 `dispatch-stall-recovery` (the feature):** the safe stop, C (diagnosis), B (Slack approval and
  resume) and D (dashboard), as the parts of `docs/plans/v1.45.0-dispatch-stall-recovery.md`. It starts with real stall
  directories from v1.44.1. Cost of the split: if v1.45.0 is cut after 2026-12-08, diagnosis runs on ordinary API
  spend, not the $100 credit.
