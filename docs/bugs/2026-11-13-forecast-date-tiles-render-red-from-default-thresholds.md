# Release forecast Earliest/Latest dates render red from Grafana's default thresholds

**Status:** OPEN — captured 2026-11-13
**Priority:** P3 (Claude proposal: cosmetic; red reads as "late" but means nothing)
**Classified:** P3 by gemini-4-argon-medium, 2026-11-14 (The release forecast dates are displayed accurately, and the red coloring caused by Grafana's default threshold on epoch milliseconds is a purely cosmetic visual issue.)
**Waiting on:** operator decision — since 2026-11-13
**Introduced by:** 2e0fa2d8 (panels 29 and 30 rewritten without a thresholds block)
**Should have been caught by:** review
**Prior art:** `docs/bugs/2026-11-11-bugs-dashboard-target-forecast-tiles-always-no-date.md` (exact-topic read) — the fix that rewrote these panels

## Symptom

After the 9a579a05 promote, the Earliest and Latest tiles on the Bug Tracking dashboard show their dates in red (operator screenshot, 2026-11-13).

## Cause

Panels 29 and 30 (`scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`) set `unit: dateTimeAsIso` and no `thresholds`, so Grafana applies its default (green base, red at 80). The value is epoch milliseconds, always above 80, so the text is always red.

## Fix

Give both panels a single-step thresholds block (one neutral colour, `value: null`), as other stat panels in the file do. One bats assertion per panel.
