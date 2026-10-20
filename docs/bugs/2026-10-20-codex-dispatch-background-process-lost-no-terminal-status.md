# Bug: Codex dispatch workers disappear without terminal status or diagnostic output

**Filed:** 2026-10-20 (ChatGPT; operator-provided CLI screenshots)
**Status:** OPEN — investigation and implementation deferred until Claude is available
**Priority:** P1 — critical engineering workflow blocker: autonomous Codex dispatch can silently fail, preventing reliable agent-to-agent implementation and verification
**Severity:** high — tasks can appear accepted but never run or report completion, blocking dependable automated engineering throughput
**Approval:** operator approved filing as P2, then explicitly escalated to P1 on 2026-10-19 PDT because unreliable dispatch hinders effective engineering work; NOT approval to implement at filing time; operator then approved implementation and a Codex dispatch on 2026-10-20 PDT (Codex billing is flat-rate, no API token calls)
**Release:** v1.43.5 (triage; scheduling to be confirmed)
**Component:** `bin/k3dm-codex-dispatch`, `scripts/tests/bin/codex_dispatch.bats`
**Related:** `docs/bugs/2026-10-19-pr-checks-grafana-tables-misaligned-populated-state.md`

## Priority escalation — 2026-10-19 PDT

Operator: "I think that p2 should raise to p1 as this hinder any work effectively". Dispatch is a critical path for k3d-manager's AI-engineering workflow: repeated accepted-but-silent worker failures prevent dependable implementation and verification handoffs, require manual investigation/retries, and make completion evidence untrustworthy. P1 reflects **workflow impact and urgency**, not proof that all invocations fail or that the root cause is known. Prior successful Claude-coordinated runs and r4 demonstrate the failure is intermittent/context-dependent. Investigate before implementing; retain all failed-run evidence and the reverted speculative repair commits (6e8ef83e, bd63a39e, 04d91a6e and respective reversals) as forensic history, not accepted fixes.

## Problem and observed evidence

The operator used `bin/k3dm-codex-dispatch` while working on the PR Checks Grafana table-misalignment bug. A previous dispatch (`pr-checks-table-misalignment-r4`) did execute and wrote a ~294 KB `codex.log`: focused BATS 4/4 green, `_agent_audit` green; the full suite reported 1,746 tests with 41 failures described as pre-existing, and manifest validation was blocked by unavailable DNS/network. Those claims are from a local log summary, not independently revalidated here.

Two subsequent attempts (`pr-checks-table-misalignment-r5`, `pr-checks-table-misalignment-r6`) show:

| Artifact/check | r5 | r6 |
|---|---|---|
| Worktree and `.run` directory | present | present |
| `pid` | `43248` | `63542` |
| `codex.log` | 0 bytes | 0 bytes |
| `exit` | missing | missing |
| `codex-exit-ts` | missing | missing |
| `ps -p 43248,63542 -o pid,ppid,stat,etime,command` | no process | no process |
| `git status --short` in worktree | clean | clean |
| `bin/k3dm-codex-dispatch status` | `unknown` | `unknown` |

The same status command also reported `e2e-sandbox-live-verify` as `unknown`, but that task's artifacts have NOT been investigated; do not assume a common cause.

A screenshot of a manually entered diagnostic command contains `zsh: command not found: ]]`; this appears to come from the diagnostic command, NOT established as a dispatcher or Codex failure.

## Source inspection

In the v1.43.5 script, `_dispatch_start` creates worktree/run state and starts a background subshell (approximately lines 195–206) using:

```bash
(
  set +e
  env ... "${K3DM_CODEX_BIN:-codex}" exec ... >"$run/codex.log" 2>&1
  exit_code="$?"
  _dispatch_codex_exit "$worktree" "$run" "$version" "$slug" "$run/codex.log" "$exit_code"
  printf '%s\n' "$exit_code" >"$run/exit"
) </dev/null >/dev/null 2>&1 &
printf '%s\n' "$!" >"$run/pid"
```

The supervisor's stdout/stderr is discarded. The `exit` marker is written *after* `_dispatch_codex_exit` (which performs Git operations and ledger/metrics updates); failures there may prevent recording the original Codex return code. `status` reports `unknown` if PID is not alive and `exit` does not exist. A PID file alone proves an attempt to launch the shell subshell, not that Codex started.

**Root cause was unknown when this section was written; see "Investigation findings — 2026-10-20" below for the confirmed cause.** Plausible explanations that required evidence: Codex startup failure; background worker terminated by parent/session/signal; supervisor failure prior to or during completion bookkeeping; filesystem/permission error. The fact that r4 worked rules out a blanket claim that all dispatches fail. No evidence implicates tmux specifically.

## Investigation findings — 2026-10-20 (Antigravity agent, evidence-based)

Preserved for later review. Commands were run on `m4-air.local`; probe processes were `sleep` only (no Codex calls) and were cleaned up afterwards.

### Root cause (confirmed for the launcher used in that session; inferred for Codex CLI)

`_dispatch_start` launches Codex as a plain background subshell `( ... ) &` that stays in the **same process group and session** as whatever launched `bin/k3dm-codex-dispatch`. Agent harnesses clean up that process group when a tool command returns, so the worker is killed before it writes `codex.log`, `exit`, `codex-exit-ts` or a ledger `codex_exit` event. The surviving artifacts are exactly those seen for r5/r6: a PID file, a 0-byte `codex.log`, no exit marker, no live process.

### Evidence 1 — signal observed (Antigravity shell tool)

A probe subshell with `trap ... HUP TERM INT QUIT PIPE` was backgrounded exactly like the dispatcher's worker. At the instant the launching command returned it logged:

```text
04:10:06 got SIGHUP
```

Without the trap the same subshell was gone by the next command. Earlier, a plain `( sleep 120 ) &` was likewise dead within ~3 seconds of its launching command ending.

### Evidence 2 — which launch styles survive

Each variant ran `sleep` and was checked after the launching command ended (SIGHUP case), then separately after the whole process group was sent `SIGKILL` (`os.killpg`):

| Launch method | Survives SIGHUP | Survives `SIGKILL` to the group |
|---|---|---|
| Plain `( ... ) &` (current dispatcher) | NO | NO |
| `nohup` | yes | NO |
| `trap '' HUP` in the subshell | yes | NO |
| New session (`perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV'`) | yes | yes |
| Double-fork + `setsid` (python `os.fork`/`os.setsid`) | yes | yes |

macOS has no `setsid` binary; use perl or python.

### Evidence 3 — why the earlier Codex-authored fixes did not help

`git log` shows three reverted commits: `04d91a6e` (detached `nohup` worker), `bd63a39e` (`trap '' HUP`) and `6e8ef83e` (status label for a dead worker). The first two defend only against SIGHUP. Table above shows they cannot survive a `SIGKILL` of the process group, which is consistent with those fixes appearing to do nothing when the dispatch was launched from Codex CLI. This is an inference: Codex CLI's actual kill mechanism was **not** observed directly.

### Evidence 4 — r4 worked only because the launcher stayed alive

`pr-checks-table-misalignment-r4` was started with the launching command kept running until Codex exited (a wait loop on the worker PID). It produced a 294 KB `codex.log`, `exit=0` and a ledger `codex_exit`. A task started the normal way (launcher returns immediately) died within seconds. This matches the root cause and rules out a Codex startup, auth or sandbox fault: `codex login status` was fine and Codex ran normally once it was kept alive.

### Other observations

- `status` printed `unknown` for `e2e-sandbox-live-verify`, `r5` and `r6`. All three have a ledger `start` event but no `codex_exit`. Only r5/r6 were checked in detail (0-byte `codex.log`); `e2e-sandbox-live-verify` was not.
- r4's Codex output survived abandonment only because the ledger recorded the Git tree `5e1f59ce05f71d5d8ed78429f12796dcfe059fc4`; `abandon` deletes the worktree. Consider warning or archiving `codex.log`/`last-message.md` before `abandon` removes evidence.

### Implementation direction (operator approved implementation on 2026-10-20 PDT)

1. Start the worker fully detached: new session via a double-fork with `setsid` (perl or python helper; no reliance on a `setsid` binary), stdin from `/dev/null`, stdout/stderr to `supervisor.log`. Apply the same launch path to `resume`.
2. The worker's first action writes a start marker (its own PID, process start time, timestamp) atomically. A bare shell PID is not proof of a started worker.
3. Write the `exit` marker (code and timestamp) **before** Git-tree, ledger and metrics bookkeeping, then record bookkeeping failures separately in `supervisor.log`.
4. `status` reports a dead worker with a start marker but no `exit` marker as `terminated unexpectedly` with the log path; compare process start time to avoid PID-reuse false positives. Keep `unknown` only for runs with no start marker at all.
5. Offline BATS with a fake Codex binary (`K3DM_CODEX_BIN`) must cover: rc=0, rc=42, missing executable, forced bookkeeping failure, lost worker (SIGKILL of the worker) and PID reuse, plus a regression test proving the worker survives `SIGHUP` and a `SIGKILL` of the launcher's process group. No test may call the real `codex`.
6. Update `docs/howto/codex-dispatch.md` with the new status values, `supervisor.log`, and a note that agent-launched dispatches no longer need to keep the launching command alive.
7. Fallback if a detached worker is still killed when launched from Codex CLI (verified live, E2): move to `launchctl submit` / a launchd job. Do not add it speculatively.

### Not verified

- A detached worker surviving Codex CLI's own cleanup (needs E2 live dispatch from Codex CLI).
- Whether `r5`/`r6` were launched from Codex CLI; their launch environment was not recorded.

## Expected behavior

A dispatched task must be observable through startup, execution and terminal phases. A failed/aborted launch must not silently leave a permanent `unknown` state, and Codex's return code must not be lost to secondary bookkeeping errors. Existing isolated worktrees, sandbox restrictions, scope validation and operator approval/landing policy must remain intact.

## Investigation and proposed fix (not implementation approval)

1. Record `supervisor.log` separately from `codex.log`, capturing launcher/startup, signal and bookkeeping errors without leaking secrets.
2. Persist an atomic lifecycle record (start acknowledgment; Codex PID/process identity where feasible; Codex exit code and timestamp; separate bookkeeping status). Do not report 'Codex started' merely because a shell PID exists.
3. Ensure terminal metadata is written before nonessential Git-tree/ledger/metrics processing, with an `EXIT` trap for catchable shell exits. Signals such as SIGKILL cannot be trapped; recover via status reconciliation.
4. When the worker is absent and no completion metadata exists, report `terminated unexpectedly` (or equivalent) with a diagnostic reason and log path instead of indefinite `unknown`. Avoid PID-reuse false positives.
5. Investigate background-process lifetime/parent-shell behavior independently before prescribing `nohup`, `setsid`, or launchd. Use durable worker supervision only if evidence demonstrates it is required.

## Files

- `bin/k3dm-codex-dispatch`
- `scripts/tests/bin/codex_dispatch.bats`
- `docs/howto/codex-dispatch.md`

## Acceptance

```yaml
must:
  - id: M1
    text: Dispatcher records reliable startup and terminal status for each task, distinguishing launcher startup from successful Codex execution.
  - id: M2
    text: Codex exit status and timestamp are persisted even when subsequent ledger, Git-tree or metrics bookkeeping fails; those failures are recorded separately.
  - id: M3
    text: Supervisor errors are captured in a dedicated, redacted diagnostic log instead of being discarded.
  - id: M4
    text: Status distinguishes running, exited successfully, exited nonzero, and unexpectedly terminated when the worker is gone without an exit marker.
  - id: M5
    text: Startup, missing executable, early failure, post-processing failure and interrupted-worker scenarios have deterministic offline regression coverage.
must_not:
  - id: N1
    text: A missing exit marker with a dead process is reported as running, succeeded, or a fabricated exit code.
  - id: N2
    text: A bookkeeping error overwrites or hides an already-recorded Codex exit code.
  - id: N3
    text: Tests launch billable Codex requests or modify live infrastructure; no weakening of worktree isolation, scope checks, or landing safeguards.
  - id: N4
    text: Error logs publish credentials, tokens or other secrets.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, M5, N1, N2, N3, N4]
    text: Run shellcheck and focused BATS with a fake Codex binary covering rc=0, rc=42, missing executable, forced bookkeeping failure, lost worker and PID reuse; verify a pre-fix negative case fails and the fix passes.
  - id: E2
    kind: live
    proves: [M1, M2, M3, M4]
    text: After operator approval, use a small real dispatch on the intended release branch and verify process state, codex.log, supervisor.log and the terminal status match; record run ID, exact commit and timestamps.
interface:
  - bin/k3dm-codex-dispatch start/status/resume
  - run artifacts under ~/.local/share/k3d-manager/worktrees/<version>/<slug>.run/
```

## Definition of Done

- [ ] Identify the actual termination/failure path using newly captured evidence; keep root cause marked unknown until confirmed.
- [ ] Regression tests pass in a hermetic offline environment, including the pre-fix negative test.
- [ ] No loss of original Codex exit status when completion bookkeeping fails.
- [ ] Dead workers never remain indefinitely as ambiguous `unknown`.
- [ ] Operator-approved live dispatch validates status and diagnostic artifacts against the implementation commit.

## What NOT to Do

- Do NOT implement, dispatch to Codex, create a PR, or merge as part of filing this bug.
- Do NOT delete existing r4/r5/r6 worktrees or run directories; preserve forensic evidence.
- Do NOT assume tmux, Claude's quota, Codex itself, or launchd is the root cause without new evidence.
