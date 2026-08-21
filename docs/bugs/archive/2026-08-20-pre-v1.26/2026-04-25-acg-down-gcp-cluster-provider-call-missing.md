# Bug: make down CLUSTER_PROVIDER=k3s-gcp fails with _cluster_provider_call not found

**Branch:** `k3d-manager-v1.2.0`
**File:** `bin/acg-down`

## Root Cause

`bin/acg-down` sources only `system.sh` and `core.sh`. For the `k3s-gcp` provider,
it calls `destroy_cluster --confirm` (line 59), which is a wrapper in `core.sh:542`
that delegates to `_cluster_provider_call destroy_cluster`. But `_cluster_provider_call`
is defined in `scripts/lib/provider.sh`, which `bin/acg-down` never sources.

The AWS path is unaffected because it calls `acg_teardown --confirm` directly —
it never goes through `destroy_cluster` or `_cluster_provider_call`.

```
INFO: [acg-down] Tearing down GCP cluster...
/Users/cliang/.../scripts/lib/core.sh: line 542: _cluster_provider_call: command not found
make: *** [down] Error 127
```

## Fix

In `bin/acg-down`, replace the indirect `destroy_cluster` call with a direct call to
`_provider_k3s_gcp_destroy_cluster`. The function is already available after sourcing
`scripts/lib/providers/k3s-gcp.sh` on the line above.

**Old (line 59):**
```bash
    destroy_cluster --confirm
```

**New:**
```bash
    _provider_k3s_gcp_destroy_cluster --confirm
```
