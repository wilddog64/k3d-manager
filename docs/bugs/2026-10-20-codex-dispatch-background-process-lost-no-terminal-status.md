# Bug: Codex dispatch workers disappear without terminal status or diagnostic output

**Filed:** 2026-10-20 (ChatGPT; operator-provided CLI screenshots)
**Status:** OPEN — investigation and implementation deferred until Claude is available
**Priority:** P2 — unreliable autonomous dispatch and loss of execution evidence
**Severity:** medium — tasks can appear accepted but never run or report completion
**Approval:** operator explicitly approved filing a P2 bug, 2026-10-19 PDT; NOT approval to implement
**Release:** v1.43.5 (triage; scheduling to be confirmed)
**Component:** `bin/k3dm-codex-dispatch`, `scripts/tests/bin/codex_dispatch.bats`
**Related:** `docs/bugs/2026-10-19-pr-checks-grafana-tables-misaligned-populated-state.md`

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

**Root cause is unknown.** Plausible explanations requiring evidence: Codex startup failure; background worker terminated by parent/session/signal; supervisor failure prior to or during completion bookkeeping; filesystem/permission error. The fact that r4 worked rules out a blanket claim that all dispatches fail. No evidence implicates tmux specifically.

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
