# Bug: Codex activity files every dispatch worktree session under `other`

**Status:** LIVE-VERIFIED 2026-10-25 — `9cb1fa09`; pytest 123/123, BATS 21/21, shellcheck clean; 5 new tests red on the pre-fix script. ruff unavailable locally.
**Live evidence:** 2026-10-25 · run hub-grafana-agent-activity-tokens-by-repo-screenshot · env hub/k3d-k3d-cluster · scenario agent-activity/tokens-by-repo-7d · commit 9cb1fa09 · proves E2
**Live note:** operator screenshot 276 at Window 7d: Tokens by repo k3d-manager 896 Mil, shopping-cart-infra 1.91 Mil, shopping-cart-frontend 920 K, other 2.88 Mil.
**Fix commit:** `9cb1fa09`
**Review note:** Claude removed an out-of-spec hunk that type-guarded `ts` in `_session_records` (read_ledger already rejects non-numeric `ts`). Offline dry-run at 7d on the operator's data: k3d-manager 593.3M → 895.9M tokens, other 305.5M → 2.9M; total 901.6M and 203 sessions unchanged (N3).
**Priority:** P3
**Severity:** low — totals are right, but a third of k3d-manager's Codex tokens show as `other`
**Release:** v1.43.7 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-25, by Claude, from the operator's question about Tokens by repo (screenshot 272)
**Approval:** explicit 2026-10-25 ("go ahead", after Claude proposed mapping worktree sessions back to their repo). Not critical (metrics script only).
**Component:** `bin/k3dm-dispatch-metrics` (`_session_files`, `_activity_metrics`)
**Related:** `docs/plans/v1.43.7-codex-dispatch-cross-repo.md` (the ledger `repo` field)

## Problem

On k3dm Agent Activity, row **All Codex activity**, panels **Untracked by repo** (54) and **Tokens by
repo** (56) label each Codex session with `Path(cwd).name`, keep the 10 names with the most sessions
over 30 days, and fold the rest into `other`.

A dispatched Codex task runs in `<K3DM_WORKTREE_ROOT>/<version>/<slug>`, so its session is labelled
with the slug. Each slug has one or two sessions, never reaches the top 10, and lands in `other`. On
2026-10-25, 7d window: `other` held 141 sessions and 304M tokens across 107 folder names, nearly all
dispatch slugs; `k3d-manager` showed 593M tokens of a real ~897M.

Landed worktrees are pruned, so the folder usually no longer exists when the metrics run.

## Fix

### F1. Map a worktree working directory to its repo

In `_session_files` (or a helper it calls), after reading `cwd`:

1. If `cwd` resolves to a path of the form `<_root()>/<version>/<slug>` (exactly two components below
   the worktree root, the slug not ending `.run`), look up the ledger `start` events with that
   `version` and `slug`:
   - the latest such event has a valid `repo` (`[A-Za-z0-9._-]{1,64}`) → use it;
   - it has no `repo` (events written before cross-repo dispatch) → `k3d-manager`;
   - no such event → if `<cwd>/.git` is a file whose `gitdir:` points into `<repo>/.git/worktrees/...`,
     use that `<repo>` folder name; otherwise `other`.
2. Any other `cwd` keeps today's rule (`Path(cwd).name`, validated, else `other`).

Read the ledger once per run (the script already reads it) and pass the mapping in; do not re-read it
per session file. Do not put any path, home directory or username into a label.

### F2. Docs

`docs/guides/grafana-dashboards.md`, Agent Activity: one sentence that dispatch worktree sessions count
under the repo they were dispatched for, and that `other` is names outside the 30-day top 10 plus
sessions with no usable working directory.

## Tests

In `scripts/tests/bin/test_dispatch_metrics.py`, with `K3DM_WORKTREE_ROOT` set to a temp dir and a
temp `CODEX_HOME`:

1. A session whose `cwd` is `<root>/v1.43.7/some-slug`, with a ledger `start` for that version and
   slug carrying `repo: shopping-cart-order` → labelled `shopping-cart-order`.
2. Same, ledger `start` without `repo` → `k3d-manager`.
3. No ledger match, worktree folder exists with a `.git` file pointing at `<x>/my-repo/.git/worktrees/s`
   → `my-repo`.
4. No ledger match, no `.git` → `other`.
5. A `cwd` outside the worktree root keeps its folder name (today's behaviour).
6. A `cwd` deeper than `<root>/<version>/<slug>` (a subdirectory of a worktree) maps the same as its
   worktree.
7. Eleven dispatch sessions under different slugs of one k3d-manager version produce a
   `k3dm_codex_tokens{repo="k3d-manager"}` series and no `other` series from them.

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `docs/guides/grafana-dashboards.md`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: A Codex session whose working directory is inside a dispatch worktree is labelled with the repo the ledger records for that version and slug, or k3d-manager when the start event has no repo.
  - id: M2
    text: With no ledger match, a worktree whose .git file points into <repo>/.git/worktrees is labelled <repo>.
  - id: M3
    text: Sessions outside the worktree root keep their current label.
  - id: M4
    text: The guide says how dispatch worktree sessions are counted and what other means.
must_not:
  - id: N1
    text: No path, home directory or username in any label value.
  - id: N2
    text: A malformed ledger line, a missing worktree, or an unreadable .git file must not stop the metrics run.
  - id: N3
    text: No change to session counts, token totals or cost per window; only the repo label moves.
  - id: N4
    text: Tests never push to the real Pushgateway.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, N1, N2, N3, N4]
    text: K3DM_DISPATCH_PUSHGATEWAY_URL=http://127.0.0.1:9 pytest scripts/tests/bin/test_dispatch_metrics.py green; tests 1, 2, 6 and 7 red on a temp copy of the pre-fix script; ruff clean; bats scripts/tests/plugins/agent_dispatch_dashboard.bats green.
  - id: E2
    kind: live
    proves: [M1, M3]
    text: After the next metrics push, the operator's screenshot of Tokens by repo at Window 7d shows k3d-manager near 0.9B tokens and other well under 50M.
interface:
  - bin/k3dm-dispatch-metrics --dry-run (env K3DM_WORKTREE_ROOT, CODEX_HOME, K3DM_DISPATCH_PUSHGATEWAY_URL)
  - k3dm_codex_sessions, k3dm_codex_untracked_sessions, k3dm_codex_tokens, k3dm_codex_active_seconds (label repo)
  - Grafana /d/k3dm-agent-activity panels 54 and 56
```

## Definition of Done

- [ ] F1–F2 and a CHANGELOG `[Unreleased]` `### Fixed` entry; only the Files above change.
- [ ] E1 green; paste the summaries.
- [ ] Tests 1, 2, 6 and 7 shown red on a temp copy of the pre-fix script.
- [ ] Commit: `fix(dispatch): count dispatch worktree Codex sessions under their repo`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT change the agy activity path; its repo comes from a different producer.
- Do NOT push to the real Pushgateway; tests use `K3DM_DISPATCH_PUSHGATEWAY_URL=http://127.0.0.1:9`.
- Do NOT change or remove existing tests or assertions, except where this spec changes the behaviour.
- Do NOT modify files outside the Files list.
