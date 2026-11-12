# Bug Tracking: "Target forecast (earliest/latest)" tiles only say "no date — see table"

**Status:** OPEN — captured 2026-11-11 from the operator's report; not investigated (capture-first rule)
**Priority:** P3
**Waiting on:** operator decision — since 2026-11-11 (post-merge `/release-groom` triage)
**Introduced by:** unknown (tiles from `401e4eca`, v1.43.5; when they stopped showing a date is not established)
**Should have been caught by:** unknown
**Prior art:** `docs/bugs/2026-11-07-forecast-milestones-drift-and-folded-releases.md` — read, different defect (that one
fixed the Remaining releases table going blank or overdue); `find-similar-docs` unavailable (vector store context missing)
**Approval:** operator, 2026-11-11 ("we don't need those two")

## Symptom

On Bug Tracking → Release forecast, both stat tiles "Target forecast (earliest)" (panel 29) and "Target forecast
(latest)" (panel 30) show their `noValue` text, "no date — see table", which sends the reader to Remaining releases
(operator, 2026-11-11). The table already carries the low/mid/high forecast per release.

## What is known

- The tiles show the forecast for the single `"target": true` milestone in `docs/release-milestones.json`: `v1.61.0`
  (queries in `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml:2824` and `:2862`).
- No milestone in that file is `blocked` today, so the v1.43.5 design reason for no dates (target after a blocked
  milestone) does not explain it. Why the series is empty is not established.
- Since the 2026-11-08 grooming rule, only the open and next release carry numbers; a far numbered target such as
  v1.61.0 has little meaning, so the tiles may have no useful value even when fixed.

## Options for triage

1. **Remove panels 29 and 30** (operator's suggestion); the Remaining releases table is the forecast. Update the
   dashboard tests that name them (`scripts/tests/plugins/grafana_dashboard_bugs.bats`).
2. Re-point the tiles at the next release instead of a far target.
3. Investigate why the target series is empty and keep the tiles.
