# Bug: the Bug Tracking dashboard counts open bugs but cannot say which they are

**Filed:** 2026-10-11
**Branch:** `k3d-manager-v1.43.2`
**Status:** OPEN — spec ready (v1.43.2 batch 1)
**Priority:** P3 — the counts are correct; the workaround is listing `docs/bugs/` by hand
**Severity:** low

## Symptom

The k3dm Bug Tracking dashboard shows **Open P1: 1**, **Open P2: 10**, **Open P3: 28**
(2026-10-11). The operator asked which bugs those are, and the dashboard cannot answer. Every
panel is a count, so the next step is always a manual scan of `docs/bugs/`.

## Root cause

`bin/k3dm-vectordb-metrics` publishes only aggregates: `k3dm_bug_docs{priority,state}` (15
series), per-release counts and the current release. No series names a bug, so Grafana has
nothing to put in a table. That was deliberate in v1.43.0 (bounded label values), but it leaves
the counts with no way to act on them.

## Fix

### 1. `bin/k3dm-vectordb-metrics`

- Extract the doc-reading block of `_bug_metrics` (the `if ref: … else: …` that builds `texts`)
  into `_bug_texts(root, ref=None)` returning `{path: text}`. `_bug_metrics` calls it. No change to
  its output.
- Add `_open_bug_metrics(root, ref=None, branch="")`. For each text where `doc_meta` gives
  `state == "open"`, emit
  `k3dm_bug_open_info{priority="<P0..P3|unset>",bug="<stem>",sort_key="<priority> <stem>",branch="<branch>"} 1`
  - `stem` is the file name without `docs/bugs/` and `.md`. Nothing else from the doc: no title,
    no path, no prose.
  - Skip a stem that does not match `^[A-Za-z0-9._-]{1,120}$`, and count skips in
    `k3dm_bug_open_info_skipped`.
  - Sort by `sort_key`, and emit at most 200 series. Emit `k3dm_bug_open_info_truncated` as `1`
    when the cap was hit, else `0`.
  - `branch` is the branch the scan read, resolved exactly as `_current_release` resolves its
    name (`ref` without `origin/`, or `git branch --show-current` for `HEAD`/no ref). Factor that
    line into `_scan_branch(root, ref)` and have `_current_release` call it. It must match
    `^[A-Za-z0-9._/-]{1,100}$`, else `""`.
  - Always emit `k3dm_bug_open_info_skipped` and `k3dm_bug_open_info_truncated`, even with no
    open bugs.
- `_push_bug_group(job, payload, method="POST")`. Existing callers are unchanged.
- In `publish_bug_metrics`, after the `k3dm-bug-docs` push, push `_open_bug_metrics(...)` to a
  **new group `k3dm-bug-open` with `method="PUT"`**. PUT replaces the whole group, so a bug that
  closes, and the last open bug closing, both disappear from the dashboard. A failure here is
  non-fatal and logged the same way the release metrics are, and it never blocks the other two
  pushes.

### 2. `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`

- New table panel **"Open bugs"** in the "All open bugs" row, at `x 0, y 20, w 24, h 10`, directly
  under the stat panels. Move "Open by priority over time" (id 15) from `y 20` to `y 30`.
- Query (instant, table format): `k3dm_bug_open_info`.
- Transformations: `organize` to show only `priority` and `bug`, in that order, with `sort_key`
  hidden. Sort by `sort_key` ascending, so the order is P0, P1, P2, P3, unset, oldest first.
- `priority` cell colours: the same per-priority colours the bar chart pins (read them from
  panel 7's overrides; do not invent new ones).
- Data link on `bug`:
  `https://github.com/wilddog64/k3d-manager/blob/${__data.fields.branch}/docs/bugs/${__data.fields.bug}.md`,
  opening in a new tab.
- Panel description: "Every open bug doc, from the same scan as the counts above. Click a name to
  open the doc on the branch the scan read."
- If `k3dm_bug_open_info_truncated == 1`, the description's note says the list is capped at 200.
  No extra panel.

### 3. Docs

- `docs/guides/grafana-dashboards.md`, k3dm Bug Tracking section: the Open bugs table, its metric
  and the `k3dm-bug-open` group, and why that group is PUT.
- `CHANGELOG.md` `[Unreleased]`: one entry.

## Files

| File | Change |
|---|---|
| `bin/k3dm-vectordb-metrics` | item 1 |
| `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` | item 2 |
| `scripts/tests/bin/test_vectordb_bug_metrics.py` | tests below |
| `scripts/tests/plugins/grafana_dashboard_bugs.bats` | tests below |
| `docs/guides/grafana-dashboards.md`, `CHANGELOG.md` | item 3 |

## Tests (each shown failing against the pre-change code, on a temp copy)

- pytest (`test_vectordb_bug_metrics.py`, fixture repo):
  - one series per open doc; closed and unknown-state docs are absent;
  - labels are exactly `priority`, `bug`, `sort_key`, `branch`; no label value contains `/docs`,
    `.md` or a space other than the one in `sort_key`;
  - a stem with a disallowed character is skipped and counted;
  - 201 open docs give 200 series and `truncated 1`;
  - no open docs give zero info series and the two counters still present;
  - `k3dm-bug-open` is pushed with `PUT` and the other two groups keep `POST` (monkeypatched
    `urlopen` records method and URL);
  - an `_open_bug_metrics` exception still lets `k3dm-bug-docs` and `k3dm-bug-releases` push;
  - the existing 15-series and fixed-enum tests stay green unchanged.
- BATS (`grafana_dashboard_bugs.bats`):
  - the existing "every queried metric is emitted" and layout tests pass with the new panel;
  - the table's data link uses `__data.fields.branch` and `__data.fields.bug`;
  - the table sorts by `sort_key`.
- Mutations (Claude at verification), each turning a test red:
  - POST instead of PUT for `k3dm-bug-open`;
  - include closed docs;
  - drop the stem check;
  - drop the cap.

## Operational Requirements

| Item | Requirement |
|---|---|
| Resources | No new workload. One more pass over texts already in memory; one more push. |
| Capacity | Series = open bug count (39 on 2026-10-11), hard cap 200, plus 2 counters. |
| Rollback | Revert. Then delete the group: `curl -X DELETE <pushgateway>/metrics/job/k3dm-bug-open` (operator). |
| Proof it works | Within one Hermes poll on the M4, the table lists 1 P1, 10 P2 and 28 P3 rows matching the stat panels, and a click opens the doc. |

## What NOT to Do

- Do NOT change `k3dm_bug_docs`, `k3dm_bug_release_docs` or the existing groups' push method.
- Do NOT put a title, path or any doc text in a label. The file stem is the only exception, and
  only in `k3dm-bug-open`.
- Do NOT push to a real Pushgateway in tests; point the exporter at a closed local port.
- Do NOT create a PR, commit to `main`, or use `--no-verify`.
