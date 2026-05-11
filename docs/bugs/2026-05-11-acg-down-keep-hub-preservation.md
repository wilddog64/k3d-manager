# Bug: `acg-down --keep-hub` is hard to trust because the teardown output does not reflect the preserved Hub state

**Date:** 2026-05-11  
**Severity:** Medium — operator sees local Hub removed even when the flag should preserve it
**Status:** Open

## Symptom

Running:

```bash
bin/acg-down --confirm --keep-hub
```

still appears to remove the local Hub cluster from the operator’s perspective.

## Root Cause

`bin/acg-down` only logs a generic completion line at the end:

```bash
_info "[acg-down] Done. Remote cluster and local Hub deleted."
```

That message is wrong when `--keep-hub` is set. The script also does not print the resolved Hub
cluster name up front, so it is hard to tell which cluster name would have been deleted if the
preserve gate were not in effect.

## Required Fix

1. Make the script print the resolved Hub cluster name and keep-hub state at startup.
2. Make the final completion message conditional so it says the Hub was preserved when
   `--keep-hub` is set.
3. Keep the actual Hub deletion behind the explicit `--keep-hub` gate.

## Follow-up

If the Hub still disappears after this change, the next step is to verify whether some other
teardown path is deleting the cluster outside `bin/acg-down`.
