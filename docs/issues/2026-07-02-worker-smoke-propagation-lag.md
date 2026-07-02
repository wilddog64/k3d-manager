# Issue: `make deploy-worker` can 401 on the first smoke probe immediately after deploy

**Date:** 2026-07-02  
**Branch:** `k3d-manager-v1.12.0`  
**Area:** `Makefile`, `bin/k3dm-worker-setup`, `workers/slack-relay/index.js`

## What was tested

Ran the repo's live worker deploy path:

```text
make deploy-worker
```

## Actual output

Immediate post-deploy smoke:

```text
HTTP/2 401
...
---BODY---
Unauthorized
```

Same signed request retried after a short delay:

```text
HTTP/2 200
...
---BODY---
{"text":"🔍 Checking Hostinger cluster status…","response_type":"ephemeral"}
```

## Root cause

The Cloudflare Worker accepted the signed `/cluster-status` request, but not
immediately after deploy. The first probe hit a short-lived consistency window
right after `wrangler deploy` and secret upload. After the edge caught up, the
same request returned `200`.

This is not a local webhook bug; it is a timing issue in the live smoke path.

## Follow-up

If this flake becomes common, add a short retry loop to the worker smoke test so
`make deploy-worker` waits for the new Worker version / secret state to settle
before declaring failure.
