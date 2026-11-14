# Bug (child B): approve a stalled-dispatch correction from Slack, then resume once

**Status:** OPEN
**Priority:** P2 (operator, 2026-11-14)
**Waiting on:** operator decision — since 2026-11-14 (spec intent)
**Approval:** drafted by Sonnet for Claude review 2026-11-14
**Intent approved:** pending
**Introduced by:** pre-existing
**Should have been caught by:** none
**Prior art:** docs/bugs/2026-11-14-codex-dispatch-silent-running-raises-no-alert.md (parent) — child spec
**Parent:** docs/bugs/2026-11-14-codex-dispatch-silent-running-raises-no-alert.md
**Depends on:** child A (`docs/bugs/2026-11-14-dispatch-stall-a-detector.md`: `bin/k3dm-dispatch-stall-watch` calls the executable named by `K3DM_STALL_DRAIN_CMD` every tick). Child C (`docs/bugs/2026-11-14-dispatch-stall-c-diagnose.md`) writes the files this child reads; B is testable alone with fixture stall directories.

## What this child does
