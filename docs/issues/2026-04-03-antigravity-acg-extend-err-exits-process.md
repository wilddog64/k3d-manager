# Issue: `antigravity_acg_extend` Uses `_err` — Kills Process on Extend Failure

**Date**: 2026-04-03
**Branch**: k3d-manager-v1.0.2
**Fixed in**: `docs/plans/v1.0.2-fix-acg-extend-err.md`

## Symptom

`CLUSTER_PROVIDER=k3s-aws deploy_cluster --confirm` exits immediately with:

```
ERROR: [antigravity] acg_extend failed: INFO: Navigating to ...
ERROR: Extend button not found or not visible after multiple attempts
```

The deploy never reaches `acg_provision`.

## Root Cause

`antigravity_acg_extend` (antigravity.sh:224-226) calls `_err` when the Playwright extend
script exits non-zero:

```bash
if [[ $exit_code -ne 0 ]]; then
  _err "[antigravity] acg_extend failed: ${output}"
fi
```

`_err` in lib-foundation calls `exit 1`, terminating the entire shell process.

The caller in `k3s-aws.sh` line 44-45 was written to tolerate failure:

```bash
antigravity_acg_extend "${_ACG_SANDBOX_URL}" \
  || _info "[k3s-aws] Pre-flight extend failed — proceeding (sandbox may have sufficient TTL)"
```

But because `_err` calls `exit 1` rather than returning non-zero, the `||` branch never runs.

## Impact

- `deploy_cluster` fails entirely when the "Extend" button is not visible (e.g. sandbox has
  sufficient TTL, or page renders differently)
- Pre-flight extend was intentionally non-fatal — this makes it fatal

## Fix

Replace `_err` with `_info` + `return 1` in `antigravity_acg_extend` so the function returns
non-zero and the caller's `||` handler takes over.
