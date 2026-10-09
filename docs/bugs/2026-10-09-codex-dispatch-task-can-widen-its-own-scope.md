# Bug: a Codex dispatch task can widen its own scope by editing its spec's Files table

**Filed:** 2026-10-09
**Branch:** `k3d-manager-v1.43.0`
**Status:** FIXED `774747ac` 2026-10-09 (Codex via worktree dispatch; Claude verified 17/17 BATS, both mutations red)
**Priority:** P2 — the scope gate is the point of the tool, and an agent can bypass it silently
**Severity:** medium

## Symptom

The first real run of `bin/k3dm-codex-dispatch` was Hermes R10. During verification, Claude edited
the task's copy of `docs/plans/v1.43.0-hermes-r10-delete-superseded-failed-job.md` to add
`scripts/tests/hermes/test_hermes.py` to its `## Files` table. `land` then printed `scope: in-scope`
and landed without `--allow-out-of-scope`. The edit was reviewed, but nothing stops Codex from making
the same edit unreviewed.

## Cause

`_dispatch_scope_verdict` reads the spec from `$worktree/$spec`, which is the task's working copy.
The task can change that file, so the task controls its own allowlist.

## Fix

- In `start`, record the release-branch commit the worktree was cut from:
  `git -C "$_dispatch_repo_root" rev-parse "origin/$rel" > "$run/base"`.
- `_dispatch_scope_verdict` reads the Files section from
  `git -C "$worktree" show "$(<"$run/base"):$spec"`, the spec as dispatched, never from the working copy.
  Change `_dispatch_spec_files` to read its input from stdin. The `start` precondition check keeps
  reading the operator checkout's committed spec.
- Any change to the spec file itself is always out of scope, like `memory-bank/**`.
- `status` and `land` report `scope: unknown (no recorded base)` and refuse, respectively, when
  `$run/base` is missing.
- The scope diff in `_dispatch_scope_verdict` uses `"$(<"$run/base")"...HEAD` instead of
  `origin/$rel...HEAD`. Then a release branch that moved after dispatch does not show other people's
  commits as task changes.

## Files

| File | Change |
|---|---|
| `bin/k3dm-codex-dispatch` | record `<run>/base`; scope from the dispatched spec; spec edits out of scope |
| `scripts/tests/bin/codex_dispatch.bats` | regression tests |
| `docs/howto/codex-dispatch.md` | one sentence: scope comes from the spec as dispatched, and editing the spec is out of scope |

## Tests

Add to `scripts/tests/bin/codex_dispatch.bats`:
1. A task commits an edit to `a.txt` **and** adds `` `b.txt` `` to its spec's Files table plus a
   `b.txt` change. `land` refuses (exit 2), and `status` lists both `b.txt` and the spec as out of
   scope.
2. `$run/base` exists after `start` and equals the fixture's `origin/k3d-manager-v9.9.9` at dispatch.
3. Another commit pushed to the release branch after dispatch does not appear in the task's scope
   output.
4. With `$run/base` deleted, `land` refuses.

Mutation checks:
- Read the spec from the working copy again. Test 1 must fail.
- Drop the spec-file out-of-scope rule. Test 1 must fail.

## Rules

- `shellcheck bin/k3dm-codex-dispatch`: zero warnings.
- `bats scripts/tests/bin/codex_dispatch.bats`: all green. Paste the output.
- Do not commit. `.git` is read-only in the sandbox.
