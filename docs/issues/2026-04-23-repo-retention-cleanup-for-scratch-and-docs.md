# Issue: repository retention cleanup for `scratch/` and historical docs

## What was reviewed

- Reviewed overall working-tree size and major contributors to repository weight.
- Identified that `scratch/` and accumulated historical documentation are the main cleanup candidates.
- Confirmed that many historical documents are recoverable from git history even if they are no longer kept in the active tree.

## Current findings

- The working tree size is dominated by transient and historical content rather than active source files.
- `scratch/` is the largest current contributor and appears to be the strongest cleanup target.
- `docs/` also contains a large amount of historical material, including older plans and investigation notes that may no longer need to remain in the active tree.
- `memory-bank/` is not currently the primary size problem; growth pressure is much higher in `scratch/` and `docs/`.

## Why this matters

- Large transient directories make the repo heavier to navigate and reason about.
- Historical documents that are no longer active references add maintenance burden and make current guidance harder to find.
- Git history already preserves committed material, so active-tree retention should favor operator-relevant and currently referenced docs.

## Recommended follow-up

1. Purge transient content in `scratch/` aggressively unless specific artifacts are still needed for an active investigation.
2. Review `docs/` for older plans, investigations, and one-off notes that can be:
   - moved to archive,
   - removed from the active tree, or
   - kept only if still referenced by README, Memory Bank, or current operator workflows.
3. Treat active references as the retention criterion, not just age.
4. Keep Memory Bank concise, but prioritize `docs/` and `scratch/` cleanup first.

## Scope note

- This issue records the cleanup need only.
- No automated purge or archival action is performed here.
