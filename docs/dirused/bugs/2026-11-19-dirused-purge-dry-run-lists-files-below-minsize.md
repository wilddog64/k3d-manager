# dirused `/purge` lists every `/largest` match, including files below `/minsize`, so the files that would be deleted are hard to pick out

**Status:** LANDED — 529ec87 on branch m8c-purge-hide-below-minsize, PR wilddog64/dirused#33 (Flash implemented; Claude verified: portable 122/122, pre-fix red on b708b63, 2 mutants red)
**Priority:** P3 — usability: the would-delete rows are all there, just mixed in with rows that can never be deleted; workaround: read only the `[would delete]` rows
**Introduced by:** M8 (wilddog64/dirused, released v0.0.18)
**Should have been caught by:** spec
**Introducing change reviewed:** yes (both)
**Waiting on:** live check — since 2026-11-19 (released v0.0.20, merge 31edffe; operator E2 on work laptop)
**Fix commit:** 529ec87 (wilddog64/dirused PR #33)
**Spec:** `docs/plans/dirused-m8c-purge-hide-below-minsize.md` (operator: "go ahead to write a bug and dispatch to flash", 2026-11-19)
**Intent approved:** operator, 2026-11-19
**Tracked:** dirused (OOB repo), not a k3d-manager release.
**Prior art:** `docs/dirused/bugs/2026-11-19-dirused-purge-dry-run-refuses-without-pattern.md` (same feature, different issue); find-similar-docs unavailable (vector store context missing), exact-slug glob found none
**Filed:** 2026-11-19

## Symptom

Operator, 2026-11-19, dirused 0.0.19, `dirused /top 3 /warn 30 /crit 45 /html /file server-list.txt /largest /purge`
(screenshot). On us03p02ffm01, 3 of 20 rows are `[would delete]` (117G, 9.8G, 7.2G). The other 17 are
`[skipped: smaller than 1.0 GB]`, down to a 1.4K `localhost.*.log`. On us03p02app01 all 20 are skipped ("would free 0B").

Operator: "if we give /largest and /purge, the list should give only largest files instead of every file as this make it hard
to tell what to delete".

## Cause

`Purge.cs:84` gives every `/largest` row a status. `TextRenderer.WriteLargest` (`TextRenderer.cs:83`) and
`HtmlRenderer.cs:86` print every row whatever its status.

## Proposed change (for operator decision)

With `/purge`, text and HTML output leave out rows whose only problem is `skipped: smaller than <minsize>`. The header says how
many were left out, e.g. `Largest candidate files (3 shown of 32 matches, 17 smaller than 1.0 GB not shown, would free 134G)`.
When none is left, the line reads `no files of at least 1.0 GB`.

Kept as rows:
- `would delete` / `deleted` / `failed`.
- Any other skip reason (modified within N days, read-only, hard-linked, changed since scan, and the rest). These are large
  files you would expect to be deleted, so the reason should be shown.

Unchanged:
- JSON and CSV keep every row, because scripts may read them.
- `/largest` without `/purge` is unchanged.
- To see smaller files, lower the limit, e.g. `/minsize 100MB`. No new switch.

## Live check of M8b (E2), from the same screenshot

- Step 3 PASSED: the patternless `/largest /purge` ran across `/file` servers and showed `would delete` and skipped rows.
- The hint line is below the screenshot crop, and step 2 (`/confirm` refused) has not been run. M8b stays LANDED until both are
  seen.
