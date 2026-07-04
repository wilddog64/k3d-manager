# Issue: Slack `/cluster-status` can go silent when the Worker secrets drift and `setup-worker` has no post-deploy smoke check

**Date:** 2026-07-02  
**Branch:** `k3d-manager-v1.12.0`  
**Area:** `bin/k3dm-worker-setup`, `workers/slack-relay/index.js`

## Symptom

Issuing `/cluster-status` in Slack produced no visible reply.

## Investigation

The Slack app Request URL is already pointed at the Cloudflare Worker:

`https://k3dm-slack-relay.k3dm.workers.dev`

The Worker endpoint itself is alive, but a direct unauthenticated probe returns
`401`, which is expected for the signing gate:

```text
401
```

The missing piece was a post-deploy verification step that actually exercises
the signed slash-command path after secrets are synced and the Worker is
redeployed. Before this fix, `bin/k3dm-worker-setup` could finish secret sync
and deployment without proving that the live Worker accepted the current Slack
signing secret.

## Root Cause

The Worker deploy path had no smoke test. That means a stale or drifted
`SLACK_SIGNING_SECRET` could remain deployed in Cloudflare and only surface as
Slack silence when `/cluster-status` was used.

## Fix

`bin/k3dm-worker-setup` now runs a signed `/cluster-status` smoke request after
deploying the Worker. If Cloudflare rejects the current signing secret, the
setup fails immediately with a clear error instead of leaving the relay in a
silently broken state.

`docs/howto/slack-slash-commands.md` now documents that `make setup-worker`
performs this verification automatically.
