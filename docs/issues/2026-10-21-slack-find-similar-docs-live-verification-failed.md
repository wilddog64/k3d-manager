# Slack find-similar-docs live verification failed

**Date:** 2026-10-21
**Related bug:** `docs/bugs/2026-10-15-slack-find-similar-docs-free-text-q-parsing.md`

## Attempted

The operator ran the Slack `/k3dm find-similar-docs` command with a natural-language `Q` value, twice, after the offline fix was landed.

## Actual output

The operator screenshot showed these two repeated response sequences (message text transcribed verbatim; the screenshot clips the target name):

```text
Queuing make find-similar-docs…
⚠️ invalid value for Q

Queuing make find-similar-docs…
⚠️ invalid value for Q
```

## Findings and limits

The live attempt failed. In the landed source, the relay acknowledgment is `Request received for make …; validating…`, not `Queuing make …`; the backend `Q` validation accepts printable ASCII, including apostrophes. The screenshot's acknowledgment is not enough to identify which component generated it or prove that the relay is stale. It also does not show the exact submitted query.

## Follow-up

From the current release branch, run the documented rollout steps for both components (`make deploy-worker` for the Cloudflare relay and `make restart-webhook` for the local webhook) if they have not already been done. Then retry `k3dm find-similar-docs Q="what's recent e2e-remote issues"` in Slack and verify successful execution with the full unchanged query. Keep the canonical bug OPEN until that live check passes.

## Redispatched investigation task

**Task:** Codex investigation `01a160e6-0c57-7dd1-a894-3d20546d63b1`

Treat the current release branch as the intended deployment source. Inspect the Slack relay and webhook code paths, identify safe read-only ways to establish which release-branch revisions are active (or state if runtime revision cannot be queried), and document the component-specific rollout/restart steps and live acceptance check. Determine whether any remaining parser/validation defect exists in the landed code. Do not deploy, restart services, change deployment triggers, or duplicate an already-correct implementation.

**Files:**

- `docs/issues/2026-10-21-slack-find-similar-docs-live-verification-failed.md`
- `docs/bugs/2026-10-15-slack-find-similar-docs-free-text-q-parsing.md` (read-only reference)
- `.github/workflows/deploy-worker.yml` (read-only reference; supplementary, not the release-branch deployment baseline)
- `docs/architecture/webhook-server.md` (read-only reference)
