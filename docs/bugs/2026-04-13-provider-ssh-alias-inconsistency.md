# Bug: SSH alias contract differs across providers instead of using one dynamic standard

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/plugins/aws.sh`, `scripts/lib/providers/k3s-gcp.sh`, future Azure provider files

---

## Summary

AWS currently updates aliases such as `ubuntu`, `ubuntu-1`, and `ubuntu-2`, while GCP uses
`ubuntu-gcp`. This exposes provider-specific naming even though ACG only allows one active
sandbox at a time.

SSH aliases should be standardized across providers so users always connect the same way,
regardless of AWS/GCP/Azure implementation details.

---

## Expected Alias Contract

All providers should maintain these aliases dynamically:

- `ubuntu-tunnel`
- `ubuntu-1`
- `ubuntu-2`

Their IPs should be refreshed whenever `make up`, `make refresh`, or equivalent cluster update
flows run.

---

## Root Cause

Each provider currently manages its own SSH aliases independently. AWS grew its alias set from
its original multi-node ACG workflow; GCP introduced a provider-specific alias during its
single-node implementation.

---

## Proposed Fix

1. Define a provider-agnostic SSH alias contract in shared code/docs.
2. Update AWS, GCP, and future Azure providers to populate the same aliases.
3. Ensure IP refresh is idempotent and removes stale entries before inserting new ones.
4. Add tests to verify alias updates after reprovisioning or IP rotation.

---

## Impact

Users must remember provider-specific hostnames even though only one sandbox can be active.
This makes SSH access inconsistent and increases operational friction.
