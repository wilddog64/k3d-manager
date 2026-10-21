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

The live attempt failed. In the landed source, the relay acknowledgment is `Request received for make …; validating…`, not `Queuing make …`; the backend `Q` validation accepts printable ASCII, including apostrophes. The older acknowledgment strongly indicates that the deployed relay is stale. The screenshot alone cannot identify whether the webhook backend is also stale, nor does it show the exact submitted query.

## Follow-up

Verify deployed revisions for both the Slack relay and webhook include `74d79eac`/`997587d6`. Then retry `k3dm find-similar-docs Q="what's recent e2e-remote issues"` in Slack and verify successful execution with the full unchanged query. Keep the canonical bug OPEN until that live check passes.

## Redispatched investigation task

**Slug:** `slack-find-similar-docs-deployment-gap`

Investigate the rollout gap for the already-landed parser fix. Compare the release branch commits with `origin/main`, inspect the Cloudflare Worker deployment workflow and the webhook's local service/restart mechanism, and document the exact safe promotion/deployment sequence and how to verify each component's running revision. Do not change deployment triggers, deploy anything, restart services, or duplicate the parser implementation. If repository evidence does not establish the webhook deployment mechanism or required steps, state that uncertainty explicitly.

**Files:**

- `docs/issues/2026-10-21-slack-find-similar-docs-live-verification-failed.md`
- `docs/bugs/2026-10-15-slack-find-similar-docs-free-text-q-parsing.md` (read-only reference)
- `.github/workflows/deploy-worker.yml` (read-only reference)
- `docs/architecture/webhook-server.md` (read-only reference)
