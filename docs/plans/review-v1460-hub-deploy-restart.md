# Review: v1.46.0 hub-deploy restarts changed agents (blind spec review)

**Filed:** 2026-11-27
**Repo / branch:** `k3d-manager` / `k3d-manager-v1.46.0`
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Neon (agy, `gemini-4-neon-high`), role review; Fable reviews the same text separately

## Task

Review the spec [`v1.46.0-hub-deploy-restart-changed-agents.md`](v1.46.0-hub-deploy-restart-changed-agents.md)
against the code on this branch. You get the spec and the repository, nothing else. Do not edit any file; write your
review as your final answer. No network calls; never read Keychain values; do not run hub-deploy, launchctl or make
lifecycle targets.

Answer:

- Is the detection right and complete? Which Python code do the webhook and the cloud bridge actually import (trace
  `bin/k3dm-webhook` and `bin/k3dm-cloud-bridge` imports and `sys.path` setup)? Is `scripts/lib/**/*.py` too narrow
  (shell helpers, templates, config the processes read at start) or wastefully wide?
- Is the running-job check sound? Where are job states written and cleared; can a job be `running` with no live
  process (stale) or live with no `running` file; what about the `_MAKE_JOB_LOCK` serialisation and cloud-bridge
  in-flight watches? Does `launchctl bootout` kill job child processes?
- Is the "runs under the webhook" ancestor check needed today and implementable portably?
- State: where does `bin/k3dm-hub-deploy` keep `appsets`/`launchd`/`pending`, and do `bin/k3dm-hub-promote` or
  `make hub-promote-status` parse it (a new `agents` field must not break them)? Is the stage2 / approval re-exec path
  (`K3DM_HUB_DEPLOY_PREV`, `--approval`) handled?
- Restart and confirm: reuse of `make restart-webhook` (it runs `bin/k3dm-require-role hub`), the bootstrap retry
  quirk (`Bootstrap failed: 5: Input/output error`), the health endpoint and port source, timeouts.
- Acceptance: can each `must_not` fail on the current code as stated; are the mutants concrete; does
  `scripts/tests/bin/hub_deploy.bats` already have stubs for launchctl/git/kubectl to build on?
- Anything missing from `## Files` or `## Contract readers`.

## Files

| File | Change |
|---|---|
| `docs/plans/v1.46.0-hub-deploy-restart-changed-agents.md` | read only (start here) |
| `bin/k3dm-hub-deploy` | read only |
| `bin/k3dm-hub-promote` | read only |
| `scripts/tests/bin/hub_deploy.bats` | read only |

## What NOT to Do

- Do not edit, create, stage or commit any file. Do not contact the hub or run deploy/lifecycle targets.

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
    intent: A second model checks the hub-deploy restart design against the code before Luna builds it, so a promote never kills a running job or leaves the hub on old code.
interface: none
```

**Intent approved:** operator, 2026-11-27
**Approval words and scope:** "Go for your suggestions" (fix hub-deploy stale webhook in v1.46.0; spec, blind reviews)
