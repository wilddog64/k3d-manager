# Bug: `k3dm_claude_verified_specs` counts a status backfill and closed-to-closed edits as verified specs

**Status:** OPEN
**Priority:** P2
**Approval:** pending
**Filed:** 2026-10-29
**Detected by:** human (an assistant reading the Claude cost panel flagged that $1.00 per spec implied about 851 specs)
**Affected:** `bin/k3dm-dispatch-metrics` `_verified_specs`; the Agent Cost panel **Claude cost per verified spec** and the Agent Activity panel **Compactions per verified spec**
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

In `_verified_specs`, track the `-**Status:**` line removed in the same file diff, and the `--- ` side of the header:
- count a file when its `--- ` side is `/dev/null` (a new file) and the added status is closed;
- count it when the removed status line exists and does **not** match `_CLOSED_RE`, and the added one does;
- do not count it when no `-**Status:**` line was removed from an existing file (a backfill);
- do not count it when the removed status line also matches `_CLOSED_RE` (closed to closed).

Update `docs/guides/grafana-dashboards/k3dm-agent-cost.md` and `k3dm-agent-activity.md` to say what counts as a verified spec, and to name the squash-merge limitation.

## Acceptance

```yaml
must:
  - id: M1
    text: A commit that changes an existing doc's status line from a non-closed value to a closed value counts that doc once in every window containing the commit.
  - id: M2
    text: A commit that creates a doc whose status line is already closed counts it once.
  - id: M3
    text: Each window reports the number of distinct docs that meet M1 or M2 inside that window.
must_not:
  - id: N1
    text: A commit that adds a closed status line to an existing doc that had no status line must not count that doc.
  - id: N2
    text: A commit that changes a closed status line to another closed status line must not count that doc.
  - id: N3
    text: The counter must not push, write the Pushgateway or read Keychain values when run with --dry-run.
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    text: A pytest builds a throwaway git repo with one commit for each kind (transition, new closed file, backfill, closed-to-closed) and asserts the per-window counts. N1 and N2 are shown red against the pre-fix _verified_specs.
  - id: E2
    proves: [N3]
    kind: offline
    text: The existing hermetic guard passes with K3DM_DISPATCH_PUSHGATEWAY_URL=http://127.0.0.1:9.
  - id: E3
    proves: [M3]
    kind: live
    text: After the next metrics push, Claude reads the panel. The 30-day verified-specs count is far below the 2026-10-29 value of 858 (453 on that day's history), and Claude cost per verified spec rises accordingly.
interface:
  - bin/k3dm-dispatch-metrics --dry-run (prints k3dm_claude_verified_specs{window=...})
  - _verified_specs(repo_root, now) in bin/k3dm-dispatch-metrics
```

## Open question for the operator

`_CLOSED_RE` also matches `LANDED`, `IMPLEMENTED`, `DONE` and `CLOSED`. So a plan that has landed but has not been verified counts as a "verified spec", and so does a bug closed without verification. Should the denominator be limited to `VERIFIED` / `LIVE-VERIFIED` / `FIXED`? This fix leaves the set unchanged until you decide.
