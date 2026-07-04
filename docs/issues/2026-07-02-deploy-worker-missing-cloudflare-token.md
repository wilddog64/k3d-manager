# Issue: `make deploy-worker` failed because `CLOUDFLARE_API_TOKEN` was empty in Keychain

**Date:** 2026-07-02  
**Branch:** `k3d-manager-v1.12.0`  
**Area:** `Makefile`, `bin/k3dm-worker-setup`

## Symptom

`make deploy-worker` failed in Wrangler with:

```text
✘ [ERROR] A request to the Cloudflare API (/accounts) failed.

  Invalid request headers [code: 6003]

  - Invalid format for Authorization header [code: 6111]
```

## Investigation

The deploy recipe reads `CLOUDFLARE_API_TOKEN` from macOS Keychain:

```bash
security find-generic-password -s k3dm-cloudflare-api-token -a k3dm -w
```

In this environment the lookup returned an empty value, so Wrangler received
`CLOUDFLARE_API_TOKEN=""` and Cloudflare rejected the request before deploy.

## Root Cause

The deploy path did not validate that the Cloudflare token existed before
calling Wrangler.

## Fix

`make deploy-worker` now fails fast with a clear Keychain-specific error if the
Cloudflare token, webhook token, or Slack signing secret is missing.

This avoids the opaque Wrangler auth error and points the operator at the
correct bootstrap step immediately.
