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

## Follow-up: `bug-tally --ref` failed for every ref except HEAD

After the fix went live, the release row read "No data". Hermes passes
`K3DM_INDEX_REF=origin/k3d-manager-v1.43.0`, and `scripts/bug-tally.py` found the branch with
`git symbolic-ref --short -q <ref>`, which fails for any ref that is not symbolic, so the tally exited 2.
The producer tests had stubbed the tally, so they missed it. The branch is now the ref name without
`origin/`. A regression test runs the tally against a local and an `origin/` ref; it was red before the fix.
`bug-tally.py` reads `K3DM_INDEX_REF` as its default `--ref`, so `make bug-tally` and the count
answers also failed wherever that variable was set.

## Follow-up: zero labels on the stacked bars (2026-10-10)

After the rebuild, "Bugs filed per release, by priority" printed a value label on every stacked
segment, including the empty ones, so `0` labels piled up on the bar bottoms over the real count
(`4` over `0`). A first fix mapped 0 to blank text, which hid the labels but added a grey `0`
entry to both legends (the bar chart lists value mappings in its legend). The charts now query
`… > 0` and leave empty matrix cells `null`, so empty segments are neither drawn nor labelled. A
series that is zero in every release (today P0) drops out of the legend, and a release with no bug
docs at all would drop off the x-axis. `grafana_dashboard_bugs.bats` asserts the query, the null
cells and the absence of mappings.

Dropping zero rows changed which column appears first (v1.38.0 has only `unset` bugs), and Grafana
assigns palette colours by column order, so `unset` turned green and P1 orange-red. Colours are now
pinned by name on both priority panels (P0 dark red, P1 red, P2 orange, P3 yellow, unset grey) and
the state chart (closed green, open orange, unknown grey), and an `organize` step fixes the column
order. A BATS test asserts the same priority colours on both panels (fails on the previous version).

### Follow-up: on-bar labels sat on the wrong segment

With `showValue: auto` on stacked bars, Grafana draws each count at the top edge of its own
segment, so on short segments it reads as the next colour's number, and it silently drops labels
that do not fit. Live check 2026-10-10: v1.42.0 is P1 4, P2 6, P3 3, unset 29; the chart showed "4"
inside the orange P2 segment and no 6 at all, and every `open` count was hidden. The stacked bars
now set `showValue: never` with a `multi` tooltip, so hovering a bar lists every series' count, and
the panel descriptions say so. BATS test 6 asserts both settings and fails on the previous file.
