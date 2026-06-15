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

The same misrouting affects `cluster-down hostinger`. Job `4570a5e0` is a
second observation of this bug — same misroute, same AWS sandbox timeout —
confirming that any `/cluster-up <unsupported>` (including `hostinger`)
silently kicks off an ACG AWS sandbox run.

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

Two related defects in the `cluster-up` / `cluster-down` branches of the
Slack command dispatcher:

1. **Provider allowlist drift.** The dispatcher was updated to accept
   `hostinger` for status/refresh, but the up/down parsing was not updated
   to match. The membership check on lines 701/723 only allows
   `("aws", "gcp", "az")`, so `hostinger` (and any other unknown value)
   silently falls back to the default.

2. **Default provider is `aws`.** Lines 701 and 723 default the provider
   to `"aws"` when the argument is missing or unrecognized. This is what
   turns a typo or unsupported provider into a real ACG AWS sandbox
   credential-extraction run (the failure seen in job `4570a5e0`). The
   default should not be `aws`: either reject the command with a Slack
   error, or pick a provider that does not depend on a live AWS sandbox
   session (e.g. `hostinger`, which targets the always-on lab VPS).

## Fix Applied

No cluster-side fix needed — this is a webhook code bug, not a cluster
incident. No `kubectl` or `make fix-*` operations applied; the failing
ACG AWS sandbox extraction is a downstream symptom, not the root cause.

Recommended code fix (spec — to be implemented via a `docs/bugs/` spec and
Codex handoff, per repo discipline; do NOT edit directly):

In `bin/k3dm-webhook`:

- Line 701: change tuple to `("aws", "gcp", "az", "hostinger")`.
- Line 723: change tuple to `("aws", "gcp", "az", "hostinger")`.
- Change the fallback default at lines 701/723 from `"aws"` to either
  (a) a hard error returned to Slack, or (b) `"hostinger"`. A typo or
  unknown provider must not silently kick off an ACG AWS sandbox run.
  The current `"aws"` default is what caused job `4570a5e0` to spend
  ~12 minutes timing out in `acg-up` credential extraction when the
  user asked for hostinger.

After the fix, `/cluster-up hostinger` will reach `_run_cluster` with
`provider="hostinger"`, which the existing `_provider_map` already routes
to `make up CLUSTER_PROVIDER=k3s-hostinger`.

## Notes

- Related code:
  - `bin/k3dm-webhook:281` `_run_cluster` (already hostinger-aware)
  - `bin/k3dm-webhook:347` down-path hostinger branch (already correct)
  - `bin/k3dm-webhook:617,649` status/refresh allowlists (already include hostinger)
  - `bin/k3dm-webhook:701,723` up/down allowlists (missing hostinger — the bug)
  - `bin/k3dm-webhook:701,723` fallback default `"aws"` (the silent-misroute amplifier)
- Per repo convention, the code change should land via a `docs/bugs/` spec
  and Codex handoff on a feature branch, then `make restart-webhook` after
  verifying the `bin/k3dm-webhook` change is on `main`.
- The ACG AWS extraction timeout in the job output is unrelated to this
  bug — it is the natural failure mode of running the AWS provider when
  the user did not expect to.
- Recurrences: job `4570a5e0` (2026-06-15) — same symptom, confirms the
  bug is reproducible and not a one-off.
