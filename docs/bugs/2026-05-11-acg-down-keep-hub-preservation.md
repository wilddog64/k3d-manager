# Bug: `acg-down --keep-hub` is hard to trust because the teardown output does not reflect the preserved Hub state

**Date:** 2026-05-11  
**Severity:** Medium — operator sees local Hub removed even when the flag should preserve it
**Status:** Fixed

## Symptom

Running:

```bash
bin/acg-down --confirm --keep-hub
```

still appears to remove the local Hub cluster from the operator’s perspective.

## Root Cause

The `Makefile` wrapper previously inverted the keep-hub intent through a `LOCAL` toggle, which
made the preserved-Hub path hard to trust from the top-level `make down` entrypoint. `bin/acg-down`
also always printed the same completion line, even when the Hub was preserved.

## Required Fix

1. Make the script print the resolved Hub cluster name and keep-hub state at startup.
2. Make the final completion message conditional so it says the Hub was preserved when
   `--keep-hub` is set.
3. Expose the keep-hub behavior in `Makefile` with a direct `KEEP_LOCAL` toggle instead of the
   inverted `LOCAL` convention.

## Resolution

The keep-hub path is now explicit in both places:

- `bin/acg-down` logs the resolved Hub cluster name and prints a preserved-Hub completion line.
- `make down` uses `KEEP_LOCAL=1` by default and accepts `KEEP_LOCAL=0` when the local Hub should be
  deleted too.

## Follow-up

If the Hub still disappears after this change, the next step is to verify whether some other
teardown path is deleting the cluster outside `bin/acg-down`.
