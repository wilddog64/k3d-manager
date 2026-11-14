# Bug (child C): headless Claude diagnosis of a stalled dispatch, paid by the API credit

**Status:** OPEN
**Priority:** P2 (operator, 2026-11-14)
**Waiting on:** operator decision — since 2026-11-14 (spec intent)
**Approval:** drafted by Sonnet for Claude review 2026-11-14
**Intent approved:** pending
**Introduced by:** pre-existing
**Should have been caught by:** none
**Prior art:** docs/bugs/2026-11-14-codex-dispatch-silent-running-raises-no-alert.md (parent) — child spec
**Parent:** docs/bugs/2026-11-14-codex-dispatch-silent-running-raises-no-alert.md ("Chosen direction" step 3, "Decomposition" row C)
**Depends on:** child A (`docs/bugs/2026-11-14-dispatch-stall-a-detector.md`: creates `<run>/stall-<UTC ts>/` and calls this tool with that directory through `K3DM_STALL_DIAGNOSE_CMD`). Child B consumes `correction.md`. This child is testable alone from a hand-built stall directory.

## What this child does
