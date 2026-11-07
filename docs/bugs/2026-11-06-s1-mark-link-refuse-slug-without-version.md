# Bug: S1 `mark` and `link` refuse a slug without `--version`, and `combine` does not resolve from its parts

**Filed:** 2026-11-06
**Branch:** `k3d-manager-v1.43.14`
**Status:** OPEN
**Waiting on:** fix running — since 2026-11-06
**Priority:** P3 — the documented commands exit 2; passing `--version` works, and nothing is written wrongly
**Approval:** implied 2026-11-06, within the operator's "go ahead to work on S1 spec then dispatch to Luna"; this is a defect in that S1 dispatcher slice, found by its independent verifier.
**Severity:** low
**Related:** `docs/plans/v1.43.14-dispatch-stall-detection-and-escalation-gates.md` (M8)

## Symptom

The S1 spec says a command without `--version` finds the slug in the ledger, and that no S1 command needs a release branch to resolve a task. Reproduced on 2026-11-06 in a scratch repo on `main`:

```
gate-status --slug a                                   rc=0
link --slug a --parent p --role build                  rc=2  missing or unlisted link flag
link --slug a --version v9.9.9 --parent p --role build rc=0
mark --slug a --state offline_tested --sha S --evidence F --by op  rc=2  missing or unlisted mark flag
```

`docs/howto/codex-dispatch.md` and the usage text show both commands without `--version`, so the documented forms fail.

## Root cause

In `_dispatch_s1` in `bin/k3dm-codex-dispatch`, the `link` and `mark` branches put `--version` in the set of required flags. `resolve` is already called above them and works without it.

`combine` takes no `--slug` and uses `version or current_version(rows)`. That reads the branch, or the last `start` in the ledger, rather than the parts it was given. Parts from another version are then refused or, on `main`, depend on whichever task started last.

## Fix

All in `_dispatch_s1`:

1. `link`: `--version` stays allowed and is no longer required.
2. `mark`: the same.
3. `combine`, when `--version` is absent: resolve each part from the ledger with the existing `task_rows(rows, part, None)`. If they all resolve to one version, use it. If they resolve to more than one version, exit 2 and write nothing. A part in two versions already exits 2 through `task_rows`.
4. The usage text: show `[--version V]` on `mark`, `gate-record`, `link` and `combine`.

Do not change `resolve`, `task_rows` or `current_version`.

Add one bullet at the end of `[Unreleased]`'s existing bullets in `CHANGELOG.md`. Do not add a heading.

## Files

- `bin/k3dm-codex-dispatch`
- `scripts/tests/bin/codex_dispatch.bats`
- `CHANGELOG.md`

## Tests

In `scripts/tests/bin/codex_dispatch.bats`, with names starting `codex dispatch S1`, following the existing fixtures. Gate: `bats --filter 'codex dispatch S1' scripts/tests/bin/codex_dispatch.bats`.

If an existing test pins behaviour this spec changes, stop and report it. Do not remove an assertion.

## What NOT to Do

- Do NOT change what any command writes when `--version` is given.
- Do NOT weaken any other validation in `mark`, `link` or `combine`.
- Do NOT edit `docs/howto/codex-dispatch.md`; its examples become correct.
- Do NOT touch the real ledger.
- Do NOT commit, push or create a PR. Claude reviews and commits.
- Do NOT modify files outside the Files list.

## Acceptance

```yaml
interface:
  - "bin/k3dm-codex-dispatch link|mark|combine, run with cwd in a scratch git repo on a non-release branch, K3DM_WORKTREE_ROOT holding a scratch ledger.jsonl; exit code, stderr and the ledger's bytes"
must:
  - id: M1
    text: "link with a slug in one version and no --version exits 0 and appends one link row carrying that version, on a non-release branch."
  - id: M2
    text: "mark with a slug in one version and no --version exits 0 and appends one row carrying that version, on a non-release branch."
  - id: M3
    text: "combine with no --version, on a non-release branch, where the ledger's most recent start belongs to another version, writes a combine row carrying the version of its parts."
  - id: M4
    text: "With --version given, link, mark and combine write the same row as before."
must_not:
  - id: N1
    text: "A slug in two versions, without --version, is not resolved by link or mark: exit 2 and the ledger unchanged. Paired control: with --version it succeeds."
  - id: N2
    text: "A slug with no start is not resolved by link or mark: exit 2 and the ledger unchanged. Paired control: a slug with a start succeeds."
  - id: N3
    text: "combine with parts in two different versions and no --version writes nothing: exit 2 and the ledger unchanged. Paired control: parts in one version succeed."
  - id: N4
    text: "Removing the --version requirement does not loosen the rest: mark without --by, and link without --role, still exit 2 and write nothing, with or without --version. Paired control: the full flags succeed."
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2, N3, N4]
    kind: offline
    what: "The Tests gate on the task branch, run by Claude."
  - id: E2
    proves: [M1, M2, M3, M4, N1, N2, N3, N4]
    kind: offline
    what: "Independent verifier's tests, written from this block only, pass on the fix and are red on its parent where new. Mutants, each red: --version required again for link; for mark; combine uses current_version; combine picks the first part's version without comparing the rest; --by no longer required for mark."
```
