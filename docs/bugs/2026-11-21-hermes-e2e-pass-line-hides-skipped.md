# Hermes e2e Slack PASS line hides the skipped count

**Status:** OPEN — captured 2026-11-21, not triaged.
**Priority:** P3
**Introduced by:** v1.34.0 (hermes-scheduled-e2e)
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Cosmetic Slack summary formatting omission where the Hermes e2e `PASS` line omits the count of skipped tests.)
**Waiting on:** operator decision — since 2026-11-21
**Prior art:** not run (find-similar-docs: vector store unavailable, context k3d-k3d-cluster missing); exact-slug glob found none.

## Symptom

Slack 2026-11-21 02:08: `Hermes e2e 2026-11-21 (run 1795255507-25908, M2): PASS 89/102`. The operator cannot tell
whether the 13 missing tests failed or were skipped. They were skipped: a `PASS` line requires `result == "pass"`
(exit 0, 0 failed); the 2026-10-24 local summary shows the same shape (passed 88, failed 0, total 102).

## Cause

`bin/k3dm-hermes:416-417` (`_e2e_text`) prints `PASS {passed}/{total}` and drops the skipped count, which the FAIL
branch (`:420`) does print.

## Fix sketch

PASS line prints `PASS 89/102 (13 skipped)` when `total - passed - failed > 0`, and `PASS 102/102` otherwise. Update
`scripts/tests/bin/test_hermes_e2e_text.py`; the v1.34.0 plan's example (`docs/plans/v1.34.0-hermes-scheduled-e2e.md:60`)
is history, not edited.
