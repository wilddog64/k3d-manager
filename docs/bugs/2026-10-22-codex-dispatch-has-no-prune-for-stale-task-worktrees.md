# Bug: codex dispatcher has no way to prune stale task worktrees from earlier releases

**Filed:** 2026-10-22 (Claude, during M4 disk cleanup)
**Status:** OPEN
**Priority:** P3 — hygiene; disk and clutter only, no failing workflow
**Severity:** low
**Approval:** approved — operator, 2026-10-22: "that prune command seems to be a good idea. go for it"
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Component:** `bin/k3dm-codex-dispatch`; `Makefile`; `docs/howto/codex-dispatch.md`
**Related:** `scripts/tests/bin/codex_dispatch.bats`

## Symptom

On 2026-10-22, 20 task worktrees from v1.43.2 (~0.7 GB) were still under
`~/.local/share/k3d-manager/worktrees/v1.43.2/`, with 20 local `task/v1.43.2/*` branches. All 20
had landed on `k3d-manager-v1.43.2` (13 by identical patch, 7 with review edits). They were
removed by hand with `git worktree remove`; the 20 branches remain.

## Root cause

`land` and `abandon --yes` remove the worktree and the task branch, so tasks handled through
them leave nothing behind. Tasks landed any other way (before `land` cleaned up, or by hand)
are never cleaned up, and `abandon` only works for slugs of the **current** release branch
(`_dispatch_release_branch`), so an earlier release's leftovers have no tool path at all.

## Fix

- **F1.** Add `bin/k3dm-codex-dispatch prune [--yes]`. It walks every version directory under
  `$_dispatch_worktree_root` (all releases, not only the current one) and considers:
  - each task worktree directory (not `*.run`), and
  - each local branch `task/<version>/<slug>` that has no worktree.

  A candidate is **prunable** only when all hold:
  1. its release branch `origin/k3d-manager-<version>` exists;
  2. `git cherry origin/k3d-manager-<version> task/<version>/<slug>` prints no `+` line
     (every task commit is already on the release branch), or the task branch does not exist;
  3. for a worktree: `git status --porcelain` is empty;
  4. no live worker: `<slug>.run/exit` exists, or `<slug>.run/pid` is absent or not alive
     (`kill -0` fails).

  Otherwise it is **kept**, with one reason printed per candidate: `unapplied commits`,
  `uncommitted changes`, `worker running`, or `no release branch`.

  Without `--yes`, print `would prune: <version>/<slug>` and `keep: <version>/<slug> (<reason>)`
  lines and change nothing. With `--yes`, `git worktree remove` the worktree (no `--force`),
  `git branch -D task/<version>/<slug>`, then `git worktree prune` once. End with
  `pruned: N kept: M`. Exit 0 in both modes, including when kept candidates exist.
- **F2.** `prune` never deletes or edits a `*.run` directory, `ledger.jsonl` or `metrics.log`.
  These are research data. It writes no ledger event.
- **F3.** Usage text gains `bin/k3dm-codex-dispatch prune [--yes]`. `main` dispatches `prune`.
  Unknown `prune` options fail like other subcommands.
- **F4.** Makefile `codex-prune` target, following `codex-abandon`: `YES=1` passes `--yes`, otherwise
  dry run. Add it to `.PHONY`.
- **F5.** `docs/howto/codex-dispatch.md`: a short "Pruning old task worktrees" section next to the
  abandon section — what is pruned, what is kept and why, the `.run` logs are kept, preview then
  `YES=1`.
- **F6.** Tests in `scripts/tests/bin/codex_dispatch.bats`, using the existing fixture: see
  Acceptance. Use a second fixture version directory for the "earlier release" case.
- **F7.** `CHANGELOG.md` entry.

## Files

- `bin/k3dm-codex-dispatch`
- `Makefile`
- `docs/howto/codex-dispatch.md`
- `scripts/tests/bin/codex_dispatch.bats`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: prune --yes removes the worktree and deletes the task branch of a task whose commits are all on origin/k3d-manager-<version>, for an earlier release as well as the current one.
  - id: M2
    text: prune --yes deletes a leftover task/<version>/<slug> branch that has no worktree when its commits are on the release branch.
  - id: M3
    text: prune without --yes prints "would prune" / "keep ... (reason)" lines and changes no worktree, branch or file.
  - id: M4
    text: The output ends with "pruned: N kept: M" and the exit status is 0 in both modes.
must_not:
  - id: N1
    text: A task with a commit not on its release branch must not be pruned; it is reported as "keep ... (unapplied commits)".
  - id: N2
    text: A worktree with uncommitted changes must not be pruned; it is reported as "keep ... (uncommitted changes)".
  - id: N3
    text: A task whose worker is still running (pid alive, no exit file) must not be pruned.
  - id: N4
    text: No *.run directory, ledger.jsonl or metrics.log is removed or modified by prune, with or without --yes.
  - id: N5
    text: Existing land and abandon behaviour and their tests are unchanged.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, N1, N2, N3, N4, N5]
    text: bats scripts/tests/bin/codex_dispatch.bats green; N1-N4 tests red against the pre-fix dispatcher (prune is an unknown command there).
  - id: E2
    kind: live
    proves: [M2, M3]
    text: Claude runs make codex-prune on the M4; the 20 leftover task/v1.43.2/* branches are listed, then make codex-prune YES=1 removes the prunable ones and the .run directories are unchanged (file count before and after).
interface:
  - bin/k3dm-codex-dispatch prune [--yes]
  - make codex-prune [YES=1]
  - K3DM_WORKTREE_ROOT (worktree root override already used by the BATS fixture)
```

## Definition of Done

- [ ] F1–F7 on `k3d-manager-v1.43.5`; only the Files above change.
- [ ] N1–N4 shown red against the pre-fix code.
- [ ] `bats scripts/tests/bin/codex_dispatch.bats` green; `shellcheck bin/k3dm-codex-dispatch` clean.
- [ ] Commit: `feat(dispatch): prune landed task worktrees and branches across releases`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`.
- Do NOT use `git worktree remove --force` or delete a branch with unapplied commits.
- Do NOT touch `*.run` directories, `ledger.jsonl`, `metrics.log`, or change `land`/`abandon`.
- Do NOT run `prune` against the real `~/.local/share/k3d-manager/worktrees` in tests; use the fixture root.
