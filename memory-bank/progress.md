# Progress — k3d-manager

## Status
- Current branch: `k3d-manager-v1.4.2`.
- The repository is at the post-v1.4.1 handoff point; `_ai_agent_review`, Copilot docs cleanup, and ACG hardening are already shipped.
- The only known local worktree deviation is the unrelated `scripts/playwright/acg_extend.js` modification, which remains untouched.

## Milestones
- `k3d-manager-v1.4.1` completed and shipped.
- `k3d-manager-v1.4.2` created as the next working branch.
- `tools/rigor-cli/` remains vendored and treated as read-only unless explicitly refreshed.
- Repo-local review/docs cleanup around `_ai_agent_review` is done.
- Current-state memory-bank files are compressed and maintained for handoff continuity.
- Argo CD bootstrap now uses a configurable `ARGOCD_SERVER_WAIT_TIMEOUT` because the local cluster can take longer than 180s to cold-pull and become Available.
- The full `scripts/tests/plugins/argocd.bats` suite still has two unrelated baseline failures; the timeout fix was verified with a targeted smoke run instead.
- `bin/acg-sync-apps` can still fail when the local `cicd` namespace has no ApplicationSet/Application resources; a new issue doc records the missing-bootstrap state and root cause.
- `bin/acg-up` now refreshes Argo CD bootstrap resources on existing Hub clusters when the bootstrap objects are absent, closing the gap that left `sync-apps` with no `rollout-demo-default` app.

## Next Steps
- Pick up the next scoped task on `k3d-manager-v1.4.2`.
- Keep `main` protection/restoration work aligned with the current release flow.
