# Review: v1.46.0 promote-waiting squash-merge containment (blind spec review)

**Filed:** 2026-11-27
**Repo / branch:** `k3d-manager` / `k3d-manager-v1.46.0`
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Neon (agy, `gemini-4-neon-high`), role review; Fable reviews the same text separately

## Task

Review [`v1.46.0-promote-waiting-squash-merge-containment.md`](v1.46.0-promote-waiting-squash-merge-containment.md)
against the code on this branch. You get the spec and the repository, nothing else. Do not edit any file; write your
review as your final answer. No network calls; never read Keychain values; do not run repo-sync against real remotes.

Answer:

- Is `git merge-tree --write-tree` tree equality a sound "content already in deploy/hub" test? Find cases where it
  says contained but real work would be lost (rename/delete, mode-only, reverted-then-reapplied, merge commits on the
  release branch, a release branch that is behind deploy/hub), and cases where it says not contained after a plain
  squash. Is `None → not contained` the right default?
- Are all ancestry-based readers covered (`find_promotable`, `carry_forward_promotable`, anything else that decides
  "unpromoted": grep `is-ancestor`, `deploy/hub..` in `bin/k3dm-repo-sync`)? Should `promote_backlog` change too?
- Cost: up to 10 merge-trees per run on the hub; timeouts via the `git()` helper.
- Tests: can S1–S5 be built in `scripts/tests/bin/repo_sync_promote_backlog.bats` as described (fixture, `is-green`
  stub, `commit-tree` squash, git wrapper only for merge-tree)? Can each `must_not` fail as stated?
- Anything missing from `## Files` or `## Contract readers` (CI git version for `merge-tree --write-tree`).

## Files

| File | Change |
|---|---|
| `docs/plans/v1.46.0-promote-waiting-squash-merge-containment.md` | read only (start here) |
| `bin/k3dm-repo-sync` | read only |
| `scripts/tests/bin/repo_sync_promote_backlog.bats` | read only |

## What NOT to Do

- Do not edit, create, stage or commit any file. Do not contact the hub.

## Output

Findings most severe first, each tagged BLOCKER / MAJOR / MINOR with file:line evidence and a concrete fix, then a
verdict: READY, NEEDS FIXES, or REWRITE.

## Acceptance

```yaml
must:
  - id: M1
    text: every finding cites file:line and a concrete fix; the review ends with a verdict
must_not:
  - id: N1
    text: the reviewer changes any file or makes a network call
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: git status --short in the review worktree is empty; report has findings and a verdict
    intent: A second model checks the promote-waiting fix against the code before Luna builds it, so the hub stops false promote emails without hiding real ones.
interface: none
```

**Intent approved:** operator, 2026-11-27
**Approval words and scope:** "can you start first group - 5 P2s (review by Fable/Neon)"
