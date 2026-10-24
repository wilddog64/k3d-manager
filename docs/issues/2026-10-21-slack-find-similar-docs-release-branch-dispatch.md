# Task spec: investigate Slack find-similar-docs live Q failure

**Context:** `docs/bugs/2026-10-15-slack-find-similar-docs-free-text-q-parsing.md` is OPEN after the operator's slash command returned `invalid value for Q` twice. Offline fix commits `74d79eac` and `997587d6` are on `k3d-manager-v1.43.5`.

## Objective

Investigate whether the failed live query reflects a remaining code defect or the relay/webhook not being rolled out from the current release branch. The deployment baseline is the checked-out release branch, not `main`.

## Requirements

- Trace the exact Slack relay → webhook validation → job/Make argv path for `Q="what's recent e2e-remote issues"`.
- Check whether a safe read-only check can identify active relay and webhook revisions; do not claim a stale component based only on the initial Slack acknowledgment.
- Confirm the deployment steps for this release checkout and give concise, exact operator commands if rollout is needed.
- If a code defect remains, implement only the scoped fix and add a regression test. If the code is already correct, do not duplicate it; document the evidence and rollout requirement.
- Do not deploy the Worker, restart services, mutate live systems, or create a PR.
- Preserve the prior failed-live evidence and keep the canonical bug OPEN unless successful live evidence is supplied.

## Files

- `docs/bugs/2026-10-15-slack-find-similar-docs-free-text-q-parsing.md`
- `docs/issues/2026-10-21-slack-find-similar-docs-live-verification-failed.md`
- `workers/slack-relay/index.js`
- `scripts/lib/webhook/make_targets.py`
- `scripts/lib/webhook/cloud_actions.py`
- `scripts/lib/webhook/lifecycle.py`
- `Makefile`
- `workers/slack-relay/test/relay.test.mjs`
- `scripts/tests/bin/webhook_make_targets.py`
- `scripts/tests/bin/test_cloud_bridge.py`
