# Bug: `codex-dispatch abandon` cannot close a task from an older release, or one whose worktree is gone

**Status:** LANDED — `5df3a166` on `k3d-manager-v1.43.15` 2026-11-08 (land: 6 suites PASS, `codex_dispatch.bats` 269 s). Live E2 done 2026-11-08 by Claude: 23 stale rows closed with `abandon --version`, rc 0 each; `open` then listed only the 3 v1.43.15 tasks and `2026-11-01-machine-setup-skips-acg-node-deps-and-chromium`, kept because its bug is OPEN and its worktree holds an uncommitted fix. Ledger marks: `offline_tested`, `live_verified`. Independent verifier not run.
**Priority:** P3
**Introduced by:** pre-existing (`abandon` has always resolved the version from the current release branch)
**Should have been caught by:** spec
**Severity:** low — ledger hygiene: 24 started-never-closed tasks from v1.43.2, v1.43.9, v1.43.13 and v1.43.14 stay
"open" in `bin/k3dm-codex-dispatch open`, inflate the WIP count, and make the Plans panel's Blocked by read
`waits on <stale task> (CHANGELOG.md)` for about 40 plans
**Approval:** operator, 2026-11-08 ("go ahead to file a P3 and dispatch to Flesh 3.8 if our rules allowed")
**Intent approved:** operator, 2026-11-08
**Filed:** 2026-11-08
**Detected by:** Claude, abandoning the stale rows the operator approved closing on 2026-11-08
**Affected:** `bin/k3dm-codex-dispatch` (`_dispatch_abandon`)
**Branch:** `k3d-manager-v1.43.15`
**Related:** `docs/bugs/2026-11-08-plans-panel-blocked-by-ignores-dispatch-state.md` (LANDED; its live check E2 needs
these rows closed)

## Symptom

On the M5, 2026-11-08, on branch `k3d-manager-v1.43.15`, `bin/k3dm-codex-dispatch open` (and a replay of
`~/.local/share/k3d-manager/worktrees/ledger.jsonl`) lists 24 tasks with a `start` and no `land` or `abandon`, for
example `v1.43.2 hub-recover-all-rebuild 27d codex_usage` and `v1.43.9 webhook-incident-closeout-luna 11d codex_usage`.
Most were superseded by a rerun under a new slug that did land (`cve-autopatch-empty-tables` →
`cve-autopatch-empty-tables-v2`). The operator approved closing them; the tool cannot.

## Root cause

`_dispatch_abandon` (`bin/k3dm-codex-dispatch`):
- takes the version from `_dispatch_release_branch` (the checkout's branch), so from `k3d-manager-v1.43.15` it can only
  address `v1.43.15/<slug>`; there is no `--version`;
- runs `git worktree remove --force` and `git branch -D` unconditionally; for a task whose worktree and branch are
  already gone (most of the 24) these fail and the `abandon` event is never written.

## Fix

- `abandon --slug S [--version vX.Y.Z] [--reason TEXT] --yes`. `--version` defaults to the current release branch's
  version (today's behaviour). `--reason` is recorded in the ledger event.
- Refuse, writing nothing, when the ledger has no `start` for that version and slug, or when the task already has a
  `land` or `abandon` event.
- Remove the worktree and the `task/<version>/<slug>` branch only when they exist, then write the `abandon` event
  (version and slug of the task, not of the current branch). A missing worktree or branch is reported, not an error.
- Without `--yes`, print what would be removed and recorded, and change nothing (as today).

## Files

- `bin/k3dm-codex-dispatch`
- `scripts/tests/bin/codex_dispatch.bats`

## Acceptance

```yaml
must:
  - id: M1
    text: "abandon --version v1.2.3 --slug S --yes, run from a different release branch, writes one abandon event with version v1.2.3 and slug S, and S no longer appears in 'open'"
  - id: M2
    text: "abandon of a task whose worktree and task branch no longer exist exits 0 and writes the abandon event"
  - id: M3
    text: "abandon --reason TEXT records TEXT in the abandon event"
  - id: M4
    text: "abandon without --version still closes the current release's task and removes its worktree and branch (paired control for N3)"
must_not:
  - id: N1
    text: "abandon writes an event for a version and slug with no start in the ledger (it exits non-zero, ledger unchanged)"
  - id: N2
    text: "abandon writes an event for a task that already has a land or abandon event (it exits non-zero, ledger unchanged)"
  - id: N3
    text: "abandon --version of an older release removes or changes any worktree or branch of the current release"
  - id: N4
    text: "abandon without --yes changes the ledger, a worktree or a branch"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2, N3, N4]
    kind: offline
    intent: "tests start tasks in a scratch repo and scratch worktree root, delete one task's worktree and branch by hand, then abandon tasks of an older and of the current release and read the ledger, 'open', the worktrees and the branches"
  - id: E2
    proves: [M1, M2]
    kind: live
    intent: "Claude closes the stale v1.43.2, v1.43.9, v1.43.13 and v1.43.14 rows that landed elsewhere or were superseded, and 'open' then lists only the current tasks and the rows kept for Sunday's planning"
interface:
  - "bin/k3dm-codex-dispatch abandon --slug S [--version V] [--reason TEXT] [--yes], with K3DM_WORKTREE_ROOT pointing at a scratch directory"
  - "bin/k3dm-codex-dispatch open, and the ledger.jsonl under K3DM_WORKTREE_ROOT"
```

## Notes

- Fixtures assert first that `K3DM_WORKTREE_ROOT` and the repo are scratch paths, never
  `~/.local/share/k3d-manager` or the real tree (the existing `codex_dispatch.bats` setup already exports a scratch
  root).
- Ledger event shape (captured from `~/.local/share/k3d-manager/worktrees/ledger.jsonl`, M5, 2026-11-08):
  `{"ts":…,"event":"start","version":"v1.43.15","slug":…,"repo":"k3d-manager",…,"spec":…}`; an abandon event is
  `{"ts","event":"abandon","version","slug","repo"}` plus the new `reason`.
- Kept open for Sunday (do not close in E2): `v1.43.13 2026-11-01-machine-setup-skips-acg-node-deps-and-chromium`
  (uncommitted work), `v1.43.14 grafana-error-stack-trace` (commit `0afa2504` not on the branch),
  `v1.43.14 2026-11-06-s1-spec-independent-review-brief`.
