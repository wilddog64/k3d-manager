# dirused `/purge` dry run refuses to run without a `/largest` pattern, so a user cannot preview before choosing what to delete

**Status:** LIVE-VERIFIED — operator, work laptop, dirused 0.0.19/0.0.20, 2026-11-19: patternless `/largest /purge` over `/file` servers listed files and ended with the rerun hint; the same with `/confirm` was refused with the new message. Fix f79ba4c on branch m8b-purge-dry-run, PR wilddog64/dirused#32 (Flash implemented; Claude verified: portable 121/121, pre-fix red on fa3a07c, 2 mutants red)
**Priority:** P3 — usability: workaround is a separate `/largest` run (no `/purge`) to see the files, then a second run with patterns
**Introduced by:** M8 (`docs/plans/dirused-m8-purge-largest-files.md`, review rev 2: explicit pattern list required for every `/purge`)
**Should have been caught by:** spec
**Introducing change reviewed:** yes (Fable + Astra)
**Tracked:** dirused (OOB repo), not a k3d-manager release.
**Prior art:** `docs/plans/dirused-m8-purge-largest-files.md` (design source, not a bug); `make find-similar-docs` returned nothing — none above threshold
**Fix commit:** f79ba4c (wilddog64/dirused PR #32)
**Spec:** `docs/plans/dirused-m8b-purge-dry-run-without-patterns.md` (operator: "go ahead to dispatch this to Luna", 2026-11-19)
**Filed:** 2026-11-19
**Intent approved:** operator, 2026-11-19

## Symptom

Operator, 2026-11-19, on Windows (dirused 0.0.18):

```
dirused /top 3 /warn 30 /crit 45 /html /file server-list.txt /largest /purge
/purge requires /largest with file patterns, e.g. /largest *.log
```

Operator: "I think /purge can take a default /largest pattern because user might not know what need to be deleted in the first
place until they saw the report".

## Cause

M8 rule 3 (`docs/plans/dirused-m8-purge-largest-files.md:42`) refuses `/purge` when `/largest` has no pattern argument, and rule 4
(`:43`) refuses match-all patterns. Both apply to the dry run as well, though a run without `/confirm` deletes nothing (`:247`).

## Proposed change (for operator decision)

Narrow the pattern requirement to deletion only:

1. `/largest /purge` without `/confirm` (no pattern, or a match-all pattern) runs as a dry run over the `/largest` default set. It
   reports every listed file as `would delete` or `skipped <reason>`, the same as an explicit-pattern dry run. The output ends with
   a hint line such as `To delete, rerun with /largest <patterns> /purge /confirm, e.g. /largest *.log`.
2. `/confirm` keeps both M8 refusals: no pattern → `"/purge /confirm requires /largest with file patterns, e.g. /largest *.log"`;
   match-all → the existing match-all message. A no-pattern or match-all run can therefore never delete anything.
3. Help and `ShortUsageText` say that patterns are needed only with `/confirm`.

Rejected alternative: a default pattern for deletion itself. It would delete files nobody chose across every `/file` target.

M9 (`docs/plans/dirused-m9-purge-stop-service-for-locked-files.md`, draft) adds a y/n prompt before deletion. That prompt doesn't
replace rule 2: a batch run with `/file` lists has no one to answer it.

## Acceptance (draft, completed after the decision)

- must: `/largest /purge` (no pattern, no `/confirm`) exits 0 and deletes nothing; each listed file is `would delete` or skipped;
  the hint line is printed. The same holds for `/largest * /purge`.
- must: `/largest /purge /confirm` and `/largest *.* /purge /confirm` are refused with exit 64-class usage error, and no file is
  touched (fixture tree hash unchanged).
- must_not: any no-pattern or match-all run removes or renames a file (red on the base: the refusal fires before the dry run, so
  the positive dry-run assertion is the pre-fix red; mutant: drop the `/confirm` check from rule 2).
