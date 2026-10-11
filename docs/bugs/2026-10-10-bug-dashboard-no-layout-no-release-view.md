# Bug: the k3dm Bug Tracking dashboard has no layout and no per-release view

**Filed:** 2026-10-10
**Branch:** `k3d-manager-v1.43.0`
**Status:** FIXED 2026-10-10 (Claude, in-tree; see CHANGELOG [1.43.0])
**Priority:** P3 — the counts were correct, only hard to read
**Severity:** low

## Symptom

During the v1.43.0 release check the operator found `k3dm-bugs` unreadable. All six panels were
stacked in one narrow column on the left. Bar labels read `{priorit...`, the time series legend
showed raw label sets, and Scan age was a red sparkline at about 400, though a 5-minute-old scan is
healthy. Nothing showed bugs per release, which the dashboard was meant to answer.

## Cause

- No panel had a `gridPos`, so Grafana stacked them at default width.
- No `legendFormat` was set, and the stat panels kept the default sparkline and the red-above-80
  threshold with no unit.
- `bin/k3dm-vectordb-metrics` published only the all-time inventory. The per-release tally existed
  only in `scripts/bug-tally.py`, which nothing published.

## Fix

- `bin/k3dm-vectordb-metrics` publishes a second Pushgateway group, `k3dm-bug-releases`, from
  `bug-tally.py --json`. It covers the current release branch and the five shipped releases before
  it, plus the current-release marker and open bugs already scheduled for later releases. A tally
  failure skips only this group.
- The dashboard has three rows: the current release, the last five releases plus the current one
  as stacked bar charts (by priority, and open vs fixed), and the all-time open counts. Scan age now
  has unit `s` and thresholds at 30 and 120 minutes.
- New tests: release order and history cap, a non-release branch, later-release counts, push
  groups, tally failure, and a dashboard layout check (no overlap, 24 columns, every queried metric
  emitted). Mutation-checked: removing the history cap, pushing to the wrong group, counting the
  current release as later, and renaming the metric each turn a test red.
