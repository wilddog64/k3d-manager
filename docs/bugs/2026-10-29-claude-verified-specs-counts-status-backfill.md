# Bug: `k3dm_claude_verified_specs` counts a status backfill and closed-to-closed edits as verified specs

**Status:** LANDED — 2026-10-29: fix `79b525a8` (Luna, gpt-6-luna). Claude independent Acceptance tests 5/5 pass on the fix; N1 and N2 shown red on the pre-fix counter. Luna suites 162 pytest + 30/30 dashboard BATS green. Out-of-scope edits reviewed and allowed: `scripts/tests/bin/test_dispatch_logs.py` (mock follows new return shape), `scripts/tests/plugins/agent_dispatch_dashboard.bats` (new panel 93 and row layout). Dry-run on the fix: 30d 450 (130 live / 251 verified / 69 unverified), was 858. E4 (live panel read after the next push) pending.
**Priority:** P2
**Approval:** explicit 2026-10-29 "go with your suggestion" (operator): fix the count and add a `level` label (live / verified / unverified) in one change
**Filed:** 2026-10-29
**Detected by:** human (an assistant reading the Claude cost panel flagged that $1.00 per spec implied about 851 specs)
**Affected:** `bin/k3dm-dispatch-metrics` `_verified_specs` and the line that renders `k3dm_claude_verified_specs`; the Agent Cost panel **Claude cost per verified spec** and the Agent Activity panel **Compactions per verified spec**
**Caused by:** `61256041` (v1.43.6, introduced the counter) together with the v1.42.0 status backfill `cc88386c`
**Severity:** a per-spec cost KPI reads about half its true value for 30 days, and the compaction trial in `CLAUDE.md` (`autoCompactWindow` 400K) is measured against this denominator.

## Symptom

**Claude cost per verified spec** showed $1.00 for the 30-day window.

A local `--dry-run` of the producer on 2026-10-29 printed:
- 30-day window: `k3dm_dispatch_claude_api_cost_usd{window="30d"} 867.33` and `k3dm_claude_verified_specs{window="30d"} 858`, so $1.01 per spec;
- 1-day window: 16.43 / 12, so $1.37;
- 7-day window: 291.51 / 165, so $1.77.

The run used `K3DM_DISPATCH_PUSHGATEWAY_URL=http://127.0.0.1:9`, so nothing was pushed.

The cost is correct. The spec count is not.

## Root cause

`_verified_specs` runs `git log -p` over `docs/bugs` and `docs/plans`. It counts a file in every window where a commit **adds** a `**Status:**` line matching `_CLOSED_RE`. It never looks at what the line replaced, so three kinds of change count:

| Kind of added closed-status line | 1d | 7d | 30d | Correct? |
|---|---|---|---|---|
| A transition from a non-closed status (OPEN, QUEUED, READY …) | 4 | 56 | 140 | yes |
| A new file created already closed | 1 | 101 | 316 | yes |
| **A backfill:** a status line added to an existing file that had none | 0 | 0 | **405** | **no** |
| **Closed to closed:** a reworded status on a doc already closed | **7** | **29** | **40** | **no** |
| Reported total (distinct files) | 12 | 165 | 858 | |
| Correct total (transition + new, distinct) | 5 | 155 | 453 | |

- **The backfill** is the v1.42.0 squash-merge `cc88386c` (2026-10-09). It added `**Status:** CLOSED — … Not individually re-verified …` to about 367 bug docs dating from April onward. The counter dates every one of them as verified on 2026-10-09. They drop out of the 30-day window on 2026-11-08, but any future status backfill does the same thing again.
- **Closed-to-closed edits** dominate the 1-day window: 7 of 12. Amending a LANDED status to add live evidence, or rewording a CLOSED line, counts the doc again in the window of the edit.

**Known limitation, not part of this fix:** releases are squash-merged, so a doc closed during a release branch is dated to the merge, not to its closing commit. The 7-day window bunches up after a merge (99 docs in v1.43.5's squash `401e4eca` on 2026-10-24). Fixing that needs the archived branch history (`archive/<branch>` tags) and is a separate change.

## Fix

**Part 1: count only real closes.** In `_verified_specs`, track the `-**Status:**` line removed in the same file diff, and the `--- ` side of the header:
- count a file when its `--- ` side is `/dev/null` (a new file) and the added status is closed;
- count it when the removed status line exists and does **not** match `_CLOSED_RE`, and the added one does;
- do not count it when no `-**Status:**` line was removed from an existing file (a backfill);
- do not count it when the removed status line also matches `_CLOSED_RE` (closed to closed).

**Part 2: split the count by level (operator, 2026-10-29).** A single total hides how much of the work was proven live. Each counted doc gets a `level`, taken from the first word of the added status line:

| `level` | Status word |
|---|---|
| `live` | `LIVE-VERIFIED` |
| `verified` | `VERIFIED`, `FIXED`, `Fixed on/in` |
| `unverified` | every other `_CLOSED_RE` match (`LANDED`, `IMPLEMENTED`, `DONE`, `CLOSED`, `RESOLVED`, `WONTFIX`, `SUPERSEDED`, `DUPLICATE` …) |

- `_verified_specs` returns counts per window and per level.
- Render `k3dm_claude_verified_specs{window="<w>",level="<l>"}` for every window and all three levels. Emit 0 for empty ones, so a level never disappears from the series.
- A doc counted more than once in a window keeps the level of its latest counted commit in that window.

On 2026-10-29 history this gives 30d: 120 live, 265 verified, 68 unverified (453 total); 7d: 83 / 56 / 16 (155).

**Dashboards.** Once the metric carries `level`, the existing Agent Cost expression no longer matches one-to-one, because the cost series has no `level` label.
- `grafana-dashboard-agent-cost.yaml`, **Claude cost per verified spec**: `k3dm_dispatch_claude_api_cost_usd{window="$window"} / (sum by (window) (k3dm_claude_verified_specs{window="$window"}) > 0)`.
- Add a stat **Claude cost per live-verified resolution** next to it: the same expression with `level="live"` inside the sum. Fit it into the existing row, with no overlapping panels.
- `grafana-dashboard-agent-activity.yaml` **Compactions per verified spec** already uses `sum(...)`. Leave it as is.

**Docs.** In `docs/guides/grafana-dashboards/k3dm-agent-cost.md` and `k3dm-agent-activity.md`:
- say what counts as a verified spec;
- list the three levels;
- describe the new panel;
- name the squash-merge limitation.

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml`
- `docs/guides/grafana-dashboards/k3dm-agent-cost.md`
- `docs/guides/grafana-dashboards/k3dm-agent-activity.md`

## Acceptance

```yaml
must:
  - id: M1
    text: A commit that changes an existing doc's status line from a non-closed value to a closed value counts that doc once in every window containing the commit.
  - id: M2
    text: A commit that creates a doc whose status line is already closed counts it once.
  - id: M3
    text: For each window, the counts across all levels add up to the number of distinct docs that meet M1 or M2 inside that window.
  - id: M4
    text: A doc closed as LIVE-VERIFIED counts under level="live"; VERIFIED, FIXED or "Fixed on/in" counts under level="verified"; any other closed status counts under level="unverified".
  - id: M5
    text: --dry-run prints k3dm_claude_verified_specs{window,level} for every window and all three levels, including zero values.
  - id: M6
    text: The Agent Cost dashboard shows Claude cost per verified spec (all levels) and Claude cost per live-verified resolution. Both expressions return a value when the matching count is above zero, and the panels do not overlap.
  - id: M7
    text: The agent-cost and agent-activity guides define a verified spec, list the three levels and name the squash-merge limitation.
must_not:
  - id: N1
    text: A commit that adds a closed status line to an existing doc that had no status line must not count that doc.
  - id: N2
    text: A commit that changes a closed status line to another closed status line must not count that doc.
  - id: N3
    text: The counter must not push, write the Pushgateway or read Keychain values when run with --dry-run.
  - id: N4
    text: k3dm_claude_verified_specs must not be emitted without a level label.
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2]
    kind: offline
    text: A pytest builds a throwaway git repo with one commit for each kind (transition, new closed file, backfill, closed-to-closed) and one doc per level, then asserts the per-window, per-level counts. N1 and N2 are shown red against the pre-fix _verified_specs.
  - id: E2
    proves: [M5, N3, N4]
    kind: offline
    text: A --dry-run test with K3DM_DISPATCH_PUSHGATEWAY_URL=http://127.0.0.1:9 asserts all window x level lines and that no unlabelled verified_specs line exists.
  - id: E3
    proves: [M6]
    kind: offline
    text: The existing dashboard tests (every queried metric exported, no overlapping panels) pass with the new panel, and a test asserts both cost expressions use sum by (window).
  - id: E4
    proves: [M3, M6]
    kind: live
    text: After the next metrics push, Claude reads both panels. The 30-day total is near 453, not 858, and the live-verified cost is above the all-levels cost.
interface:
  - bin/k3dm-dispatch-metrics --dry-run (prints k3dm_claude_verified_specs{window=...,level=...})
  - _verified_specs(repo_root, now) in bin/k3dm-dispatch-metrics
  - scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml
```

## Decision (operator, 2026-10-29)

Keep every `_CLOSED_RE` status in the total, and split it by `level` instead of dropping statuses. Restricting the set alone would have shrunk the 30-day count from 453 to 385 and still shown one number; the split shows how much of it was proven live.

**Considered and not chosen:** basing `live` on a `**Live evidence:**` line instead of the status word. It is stricter, but the line is often added in a later commit than the close.
