# Bug: acg-up monolithic design locks provider to AWS

**Branch:** `recovery-v1.1.0-aws-first`
**Files Implicated:** `bin/acg-up`

---

## Summary

The `bin/acg-up` script, which is the primary entry point for `make up`, is hardcoded to use the AWS provider. It sources `scripts/lib/providers/k3s-aws.sh` and calls `acg_get_credentials` (the AWS extraction function) regardless of the `CLUSTER_PROVIDER` environment variable.

---

## Reproduction Steps

1. Run `CLUSTER_PROVIDER=k3s-gcp make up`.
2. Observe logs: 
   ```text
   INFO: [acg-up] Step 1/12 — Getting AWS credentials...
   INFO: [acg] Extracting AWS credentials from https://app.pluralsight.com/cloud-playground/cloud-sandboxes...
   ```
3. Observe failure: The script attempts to navigate to the AWS legacy URL instead of the GCP hands-on URL.

---

## Root Cause

`bin/acg-up` is a legacy monolith that lacks a dispatcher. It has hardcoded logic for:
- Sourcing provider libraries (sources `k3s-aws.sh` on line 30).
- Credential extraction (calls `acg_get_credentials` on line 60).
- Deployment (sets `CLUSTER_PROVIDER=k3s-aws` on line 64).

---

## Proposed Fix

Refactor `bin/acg-up` to be provider-aware:
1.  Source `scripts/etc/playwright/vars.sh` for unified URLs.
2.  Use a `case "${CLUSTER_PROVIDER}"` block to source the correct provider library.
3.  Dispatch to the correct extraction function (`gcp_get_credentials` vs `acg_get_credentials`).
4.  Remove hardcoded `CLUSTER_PROVIDER` assignments.

---

## Impact

The `k3s-gcp` provider is currently unusable via the standard user interface (`make up`), despite the underlying plugin logic being complete.
