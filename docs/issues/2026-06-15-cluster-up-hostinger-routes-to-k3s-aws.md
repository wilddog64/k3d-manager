# Issue: `cluster-up hostinger` Slack command silently routes to k3s-aws

**Date:** 2026-06-15
**Component:** bin/k3dm-webhook (Slack command dispatcher)
**Status:** Fixed

## Symptom

User issued `/cluster-up hostinger` via Slack. Webhook spawned `make up
CLUSTER_PROVIDER=k3s-aws` instead of `CLUSTER_PROVIDER=k3s-hostinger`, then
failed in the ACG AWS sandbox credential extraction step:

```
Running make up CLUSTER_PROVIDER=k3s-aws...
INFO: [acg-up] Step 1/12 — Getting k3s-aws credentials...
WARN: Timed out waiting for sandbox buttons or credentials — proceeding anyway
make: *** [up] Terminated: 15
RuntimeError: make up CLUSTER_PROVIDER=k3s-aws exited -15
```

The same misrouting affects `cluster-down hostinger`.

## Investigation

Traced the Slack command path in `bin/k3dm-webhook`:

- `_run_cluster(job_id, action, provider)` (line 281) already supports
  `hostinger` correctly — its `_provider_map` (line 284) maps
  `"hostinger" -> "k3s-hostinger"`, and the down-path branch (line 347) special-cases
  `k3s-hostinger`.
- The bug is in the Slack command parser:
  - Line 701 (`cluster-down`):
    `_down_provider = ... if ... in ("aws", "gcp", "az") else "aws"`
  - Line 723 (`cluster-up`):
    `_up_provider = ... if ... in ("aws", "gcp", "az") else "aws"`

  Neither allowlist includes `"hostinger"`, so the `hostinger` argument fails
  the membership check and silently falls back to the `"aws"` default. The
  webhook then runs `make up CLUSTER_PROVIDER=k3s-aws`, triggering the ACG
  AWS sandbox credential flow on a host where the user expected the
  Hostinger provider.

Other commands (`cluster-status`, `cluster-refresh` at lines 617/649) already
include `"hostinger"` in their allowlists — confirming this is an oversight
limited to `cluster-up` / `cluster-down`.

## Root Cause

Provider allowlist drift in the `cluster-up` / `cluster-down` branches of
the Slack command dispatcher. The dispatcher was updated to accept
`hostinger` for status/refresh, but the up/down parsing was not updated to
match. Result: unknown providers (including `hostinger`) silently fall back
to `aws` instead of being rejected.

## Fix Applied

No cluster-side fix needed — this is a webhook code bug, not a cluster
incident. No `kubectl` or `make fix-*` operations applied; the failing
ACG AWS sandbox extraction is a downstream symptom, not the root cause.

Recommended code fix (spec — to be implemented via a `docs/bugs/` spec and
Codex handoff, per repo discipline; do NOT edit directly):

In `bin/k3dm-webhook`:

- Line 701: change tuple to `("aws", "gcp", "az", "hostinger")`.
- Line 723: change tuple to `("aws", "gcp", "az", "hostinger")`.
- Consider rejecting unknown providers with a Slack error instead of
  silently defaulting to `"aws"` — the silent default is what made this
  bug user-invisible until the AWS sandbox flow ran on the wrong host.

After the fix, `/cluster-up hostinger` will reach `_run_cluster` with
`provider="hostinger"`, which the existing `_provider_map` already routes
to `make up CLUSTER_PROVIDER=k3s-hostinger`.

## Notes

- Related code:
  - `bin/k3dm-webhook:281` `_run_cluster` (already hostinger-aware)
  - `bin/k3dm-webhook:347` down-path hostinger branch (already correct)
  - `bin/k3dm-webhook:617,649` status/refresh allowlists (already include hostinger)
  - `bin/k3dm-webhook:701,723` up/down allowlists (missing hostinger — the bug)
- Per repo convention, the code change should land via a `docs/bugs/` spec
  and Codex handoff on a feature branch, then `make restart-webhook` after
  verifying the `bin/k3dm-webhook` change is on `main`.
- The ACG AWS extraction timeout in the job output is unrelated to this
  bug — it is the natural failure mode of running the AWS provider when
  the user did not expect to.
