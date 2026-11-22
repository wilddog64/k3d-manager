# Bug: ask-docs answers "list fixed bugs in current release" from an old release, and finds nothing for v1.44.1

**Status:** OPEN
**Priority:** P2 (proposed) — a wrong answer, not just a miss: Slack names v1.43.4 as the current release while the branch is v1.44.1. Workaround: ask with a count word ("how many bugs fixed in current release").
**Introduced by:** pre-existing
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Classified:** P2 by gemini-4-argon-medium, 2026-11-22 (Degraded `ask-docs` query routing returns wrong release answers for "list" wording, with a workaround of phrasing the query with count words.)
**Waiting on:** operator decision — since 2026-11-17
**Prior art:** `docs/plans/v1.51.0-bug-count-query-translation.md` (exact-slug pass found no bug doc; `find-similar-docs` not run, no k3d-k3d-cluster context on the M4) — read: its 2026-10-30 note already lists list wording falling through to search; this doc records the wrong-release answer as a bug so triage can pull that plan forward. Also read `docs/bugs/2026-10-09-ask-docs-latest-bugs-misses-recent-fixes.md` (VERIFIED, same symptom family, different trigger).
**Filed:** 2026-11-17

## What happened

Slack, 2026-11-17 07:41–07:42 local (operator screenshot), webhook on the M5:

1. `ask-docs can you list fixed bugs in current release` → "Based on the provided documentation excerpts for release **v1.43.4**, the specific fixed bug listed is: `docs/bugs/2026-10-16-bug-dashboard-release-filter-defaults-to-all.md` …". Sources: v1.43.3/v1.43.4 plans and retro.
2. `ask-docs can you list fixed bugs in v1.44.1` → "The provided documentation excerpts do not contain information about fixed bugs in v1.44.1." Sources: v1.43.4/v1.43.7 retros, v1.43.x/v1.46.0 plans. The branch `k3d-manager-v1.44.1` holds 13 bug docs naming it.

## Cause

`scripts/lib/webhook/bug_count.py:41` `match()` returns no match unless `_COUNT_RE` (`:11`, `how many|count|number of|tally`) is in the question, so "list" never reaches the tally, which does know the current release (`:23` `_CURRENT_RE`, `:86` `_current_release`). The question falls through to similarity search, which returns a few chunks; the model then takes the release named in those chunks as "current". A complete list can only come from the tally, never from retrieved chunks.

Unconfirmed: why search returned no v1.44.1 bug doc at all (ranking of recent docs, or the index not yet holding them). Check the vectordb index for one v1.44.1 doc path before speccing.

## Fix direction (to spec at triage)

The operator rule of 2026-10-30 forbids new matcher vocabulary in the meantime, so the fix is `docs/plans/v1.51.0-bug-count-query-translation.md` (the model writes the query, the tally writes the numbers and lists). Proposal for grooming 2026-11-22: pull that plan forward into the next open minor by displacing a not-started plan. Until then, the search path should not state a release as "current" unless it came from the branch.
