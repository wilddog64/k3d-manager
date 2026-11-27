# Review: v1.46.0 hub-deploy restarts changed agents — rev 1 (blind spec re-review)

**Filed:** 2026-11-27
**Repo / branch:** `k3d-manager` / `k3d-manager-v1.46.0`
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Neon (agy, `gemini-4-neon-high`), role review; Fable reviews the same text separately

## Task

Review rev 1 of [`v1.46.0-hub-deploy-restart-changed-agents.md`](v1.46.0-hub-deploy-restart-changed-agents.md)
against the code on this branch. You get the spec and the repository, nothing else. Do not edit any file; write your
review as your final answer. No network calls; never read Keychain values; do not run hub-deploy, launchctl, curl or
make lifecycle targets.

Answer:

- Check every file:line the spec cites (`bin/k3dm-hub-deploy`, `bin/k3dm-hub-sync`, `bin/k3dm-webhook`,
  `Makefile`, `scripts/tests/bin/hub_deploy.bats`, `scripts/lib/webhook/*`). Is any wrong or stale?
- State: does "write the `agents` line only when non-empty" really leave every existing state write and the
  assertions at `hub_deploy.bats:96-101,288,779,912` unchanged? Does `valid_state` accepting it break anything?
- Decision order and the deferred path: are the five outcomes complete and non-overlapping? Is exit 3 safe for every
  caller? Does placing the block after the launchd loop interact badly with `pending`, `ran`, `release_lock`, the
  `trap cleanup` lines or the stage2 handoff?
- Restart and confirm: is calling `make restart-webhook` with `9>&-` under the held repo-sync lock safe (does the
  recipe or `restart-cloud-bridge` touch the lock or the checkout)? Does the `launchctl print` pid / env parsing and
  the unauthenticated 401 liveness check hold? Is `K3DM_HUB_DEPLOY_AGENT_WAIT` enough to keep tests fast?
- Tests: will every pre-existing `hub_deploy.bats` test really take the "not installed" branch with no assertion
  edit? Are the stubs and guards (launchctl, curl, make `restart-webhook`, `K3DM_JOB_DIR`) specified concretely enough
  for an implementer who cannot ask questions? Can each `must_not` fail as stated; are the mutants concrete?
- Anything missing from `## Files`, `## Contract readers` or the accepted-risk list.

## Files

| File | Change |
|---|---|
| `docs/plans/v1.46.0-hub-deploy-restart-changed-agents.md` | read only (start here) |
| `bin/k3dm-hub-deploy` | read only |
| `scripts/tests/bin/hub_deploy.bats` | read only |
| `Makefile` | read only |

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
    intent: A second model checks the rewritten hub-deploy restart design against the code before Luna builds it, so a promote never kills a running job or leaves the hub on old code.
interface: none
```

**Intent approved:** operator, 2026-11-27
**Approval words and scope:** "go ahead to have Fable/Neon review the spec then dispatch to Luna"
