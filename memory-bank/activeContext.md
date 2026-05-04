# Active Context — k3d-manager

## Current Status
- Current branch: `k3d-manager-v1.4.2` (created from `origin/k3d-manager-v1.4.1`).
- The repository is at the post-v1.4.1 handoff point; `_ai_agent_review`, Copilot docs cleanup, and ACG hardening are already shipped.
- One unrelated local modification exists in `scripts/playwright/acg_extend.js`; leave it untouched unless the task explicitly includes it.

## Current Focus
- Keep the next branch lean and focused on the next queued task.
- Preserve compatibility for the legacy CLI and vendored tooling boundaries.
- Treat `tools/rigor-cli/` as read-only vendored tooling unless the task explicitly refreshes the subtree.
- Keep the helper naming / review-doc cleanup aligned with the repo-local `bin/` surface and docs references.

## Notes
- Update this file after the next significant milestone or direction change.
