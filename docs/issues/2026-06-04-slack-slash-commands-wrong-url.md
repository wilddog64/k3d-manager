# Issue: Slack slash commands pointed to tunnel URL — bypassed Worker auth relay

**Date:** 2026-06-04
**Symptom:** All slash commands (`/acg-status`, `/acg-up`, `/acg-down`) returned
"Something went wrong. Please try again!" from Slackbot.

---

## Root Cause

The Slack app slash command **Request URL** was set to
`https://webhook.3ai-talk.org/slack/command` — the direct Cloudflare Tunnel endpoint.
This bypasses the `k3dm-slack-relay` Cloudflare Worker entirely.

The local webhook at `127.0.0.1:7443` requires `Authorization: Bearer <token>` on all
paths. Slack's slash command POST carries no such header, so the webhook returned HTTP
401 → Slack surfaced "Something went wrong."

Additionally, the Worker's `SLACK_SIGNING_SECRET` and `WEBHOOK_TOKEN` secrets were
out of sync with the live values (signing secret had drifted, webhook token was rotated
without pushing to Cloudflare).

## Architecture

```
Correct path:
  Slack → k3dm-slack-relay.k3dm.workers.dev → HMAC verify → relay with Bearer token → webhook.3ai-talk.org → localhost:7443

Wrong path (was configured):
  Slack → webhook.3ai-talk.org/slack/command → localhost:7443 → 401 Unauthorized
```

## Fix

1. Updated all slash command Request URLs in **api.slack.com → Slash Commands**:
   - `/acg-status` → `https://k3dm-slack-relay.k3dm.workers.dev`
   - `/acg-up` → `https://k3dm-slack-relay.k3dm.workers.dev`
   - `/acg-down` → `https://k3dm-slack-relay.k3dm.workers.dev`

2. Re-synced Worker secrets:
   ```bash
   echo "44af57828359a6c3f5e94251852e519f" | npx wrangler secret put SLACK_SIGNING_SECRET --name k3dm-slack-relay
   WEBHOOK_TOKEN=$(security find-generic-password -s "k3dm-webhook-token" -a "k3dm" -w) && \
     echo "$WEBHOOK_TOKEN" | npx wrangler secret put WEBHOOK_TOKEN --name k3dm-slack-relay
   ```

## Prevention

- `bin/k3dm-worker-setup` (added in commit `d7ebb11f`) documents the correct Worker URL.
- `bin/rotate-webhook-token` (added in commit `91193d5f`) now pushes to Cloudflare
  before updating Keychain, keeping Worker and local token in sync.
- The `deploy-worker` Makefile target (`make deploy-worker`) redeploys the Worker
  including current secrets.
