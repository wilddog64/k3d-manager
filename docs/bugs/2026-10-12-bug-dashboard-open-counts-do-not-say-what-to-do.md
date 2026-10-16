# Bug: the Bug Tracking dashboard's open counts do not say what to do

**Filed:** 2026-10-12
**Branch:** `k3d-manager-v1.43.2`
**Status:** OPEN — spec ready; dispatch after `2026-10-11-bug-dashboard-cannot-list-open-bugs` lands (same files)
**Priority:** P3 — the counts are correct; a reader cannot tell an outage from a shipped fix waiting for proof
**Approval:** explicit 2026-10-12 "then maybe we should have same comment or explaination (short one) to present; otherwise this confuse people as we don't know what to do or panic" (operator, on the Open P1 = 1 stat)
**Severity:** low

## Symptom

The **Open P1** stat reads **1** in orange. The one P1 is
`docs/bugs/2026-10-09-node-health-watch-ignores-ready-node-with-dead-kubelet-tunnel.md`, whose
status is `IMPLEMENTED`: the fix shipped in v1.42.0 and is waiting for a natural recurrence to prove
the restart path. Nothing is down. The dashboard gives no hint of that, so the stat reads like a live
P1 incident.

The same holds for the whole open set (2026-10-12): of 45 open docs, 16 start their status with
`OPEN`, 7 with `IMPLEMENTED`, 2 `MITIGATED`, 2 `DEFERRED`, and the rest use about twenty other
words. `WITHDRAWN`, `OBSOLETE` and `COMPLETE` count as open because `_CLOSED_RE` does not list them.

## Root cause

`doc_meta` reduces a status to `open`/`closed`/`unknown`. "Open" mixes not started, in progress,
fix shipped awaiting proof, mitigated and deferred. The stat panels have no description, and the
coming "Open bugs" table (`2026-10-11-bug-dashboard-cannot-list-open-bugs.md`) shows title,
priority and age but no status.

## Fix

Depends on `2026-10-11-bug-dashboard-cannot-list-open-bugs.md` having landed; build on its
`_open_bug_metrics` and its "Open bugs" table.

### 1. `scripts/lib/hermes/prior_art.py`

Add `WITHDRAWN`, `OBSOLETE`, `COMPLETE` and `COMPLETED` to `_CLOSED_RE`. Nothing else.

### 2. `bin/k3dm-vectordb-metrics`, `_open_bug_metrics`

Add two labels to `k3dm_bug_open_info`:

- `phase`, from the first word of the `**Status:**` value (case-insensitive; a doc with no status
  line → `other`). A fixed set only:

  | `phase` | first word |
  |---|---|
  | `not started` | `OPEN`, `SPEC`, `DESIGN` |
  | `in progress` | `IN`, `PARTIAL`, `PR`, `FIX` |
  | `reopened` | `REOPENED`, `RECURRENCE` |
  | `fix shipped, awaiting proof` | `IMPLEMENTED`, `LIVE` |
  | `mitigated` | `MITIGATED`, `RECOVERED` |
  | `deferred` | `DEFERRED` |
  | `other` | anything else |

- `status`: the status value, cleaned the same way as `title` (no backticks or `*`; `"`, `\`, tabs
  and newlines become a space), cut at 90 characters with `…`.

### 3. `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`

- "Open bugs" table: add **Phase** (after Priority, 170 px) and **Status** (last, fills the rest)
  columns. Enable the column filter on **Phase**.
- Descriptions on the stats, short:
  - **Open P0** (and the same wording for P1, P2, P3 with their priority):
    "Open bug docs at this priority. Open includes fixes that shipped and are waiting for proof — check the Phase column in Open bugs below before treating this as an incident."
  - **Open, any release**: "Every open bug doc, whatever release it is planned for. Most are P3. See the Phase column in Open bugs below."
- No colour, threshold or layout change.

### 4. Docs

- `docs/guides/grafana-dashboards.md`, k3dm Bug Tracking: the Phase column, its seven values, and
  "fix shipped, awaiting proof is not an outage".
- `CHANGELOG.md` `[Unreleased]` → `### Fixed`.

## Files

| File | Change |
|---|---|
| `scripts/lib/hermes/prior_art.py` | `_CLOSED_RE` words |
| `bin/k3dm-vectordb-metrics` | `phase` + `status` labels |
| `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` | table columns + stat descriptions |
| `scripts/tests/bin/test_vectordb_bug_metrics.py` | tests below |
| `scripts/tests/plugins/grafana_dashboard_bugs.bats` | tests below |
| `docs/guides/grafana-dashboards.md` | section above |
| `CHANGELOG.md` | `[Unreleased]` entry |

## Tests

Python (temp `docs/bugs/` fixtures, injected `now`; never push to the real Pushgateway):

1. Status `IMPLEMENTED — 90d8942a` → `phase="fix shipped, awaiting proof"`.
2. `OPEN — spec ready` → `not started`; `REOPENED 2026-10-11` → `reopened`; `MITIGATED` →
   `mitigated`; an unknown word → `other`; no status line → `other`.
3. `WITHDRAWN`, `OBSOLETE`, `COMPLETE` docs are not in `k3dm_bug_open_info` and count as closed
   in `k3dm_bug_docs`.
4. A 200-character status → `status` is 90 characters ending in `…`, with no `"` or backtick.
5. Every emitted `phase` is one of the seven values.

BATS (`grafana_dashboard_bugs.bats`):

6. The Open bugs table maps `phase` and `status` to **Phase** and **Status**, Phase after Priority.
7. Open P0–P3 and Open, any release each have a description containing `waiting for proof` or
   `Phase column`.

Mutations (each must turn a test red): map `IMPLEMENTED` to `not started` (test 1); drop
`WITHDRAWN` from `_CLOSED_RE` (test 3); remove the Open P1 description (test 7).

Gates: `pytest scripts/tests/bin/test_vectordb_bug_metrics.py`,
`bats scripts/tests/plugins/grafana_dashboard_bugs.bats`, `make test`, `make test-pytest`.

## Proof it works

After landing and the next Hermes cycle: hovering **Open P1** shows the description, and the Open
bugs table lists the node-health-watch P1 with Phase **fix shipped, awaiting proof**.

## What NOT to Do

- Do NOT change any bug doc's status here; status cleanup is separate.
- Do NOT add a free-text label other than `status` and the existing `title`.
- Do NOT change colours, thresholds or panel positions.
- Do NOT commit, push or create a PR. Claude verifies and commits.
- Do NOT modify files outside the Files list.
