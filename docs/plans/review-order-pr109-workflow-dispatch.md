# Review: shopping-cart-order PR #109 — blind diff review

**Filed:** 2026-11-22
**Repo / branch:** `wilddog64/shopping-cart-order` / `fix/cve-manual-rebuild` (head 227bbdbe; diff `00c9fcd..227bbdbe`)
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Argon (agy, `gemini-4-argon-medium`), role review

## Task

Review `git diff 00c9fcd..227bbdbe` blind. Shopping-cart-order PRs get no Copilot review, so this review is the PR's
review gate. Intended behaviour:

- `.github/workflows/ci.yml` accepts a `workflow_dispatch` event (no inputs), in addition to the unchanged `push` and
  `pull_request` triggers on `main`. An outside scanner dispatches it with `{"ref":"main"}` to rebuild the image.
- Job `publish` (calls `wilddog64/shopping-cart-infra/.github/workflows/build-push-deploy.yml` at a pinned SHA) runs
  only when the ref is `refs/heads/main` and the event is `push` or `workflow_dispatch`.
- Nothing else changes.

Look for:
- any event or ref for which `publish` (image push, signing, promote commit to `main`) now runs that it should not;
- any job or step that skips, fails or behaves differently on a `workflow_dispatch` run on `main`, including inside the
  called reusable workflow at the pinned SHA (read it with `gh api` or the local `shopping-cart-infra` checkout,
  read-only);
- permission, secret or concurrency risks the new trigger introduces;
- YAML or expression errors.

## Before You Start

1. `git log --oneline -1` and confirm HEAD is 227bbdbe.
2. Read `.github/workflows/ci.yml` in full and the diff.

## Files

| File | Change |
|---|---|
| `.github/workflows/ci.yml` | read only |

## What NOT to Do

- Do NOT edit, commit, push or comment on the PR.
- Do NOT dispatch a workflow, touch any cluster, Keychain or network endpoint other than read-only `gh api` GETs.
- Do NOT update `memory-bank/`.

## Definition of Done

- [ ] Report back one line per finding: `file:line — defect — concrete failure scenario — severity (high/medium/low)`.
      If there are none, report `no findings`. Mark each finding as verified-from-code or speculative.

## Acceptance

```yaml
must:
  - id: M1
    text: every finding cites file:line and a concrete failure scenario
must_not:
  - id: N1
    text: the reviewer changes any file
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: git status --short in the review worktree is empty; report lists findings or "no findings"
    intent: An independent model checks the order CI change before you merge it, since order PRs get no Copilot review.
interface: none
```

**Intent approved:** operator, 2026-11-22
**Approval words and scope:** "Fix now (Recommended)" for the order CI bug (operator, 2026-11-22), whose text named "a blind Argon review (no Copilot on order)".
