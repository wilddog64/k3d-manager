# Bug: the Per run evidence table sorts the run column as text

**Filed:** 2026-11-06
**Branch:** `k3d-manager-v1.43.14`
**Status:** LANDED `49765821`; independent verifier running, live check pending
**Priority:** P3 — cosmetic; the rows are all present and correct, only their order misleads
**Waiting on:** live check — since 2026-11-06
**Approval:** explicit 2026-11-06 "you can file run column as P3 and dispatch to Gemini Flash 3.8" (operator).
**Severity:** low

## Symptom

On Agent Dispatch, **Per run evidence**, the operator asked "how does run column get sorted". A task with many runs reads 1, 10, 11, 2, and rows inside a version are in no useful order.

## Root cause

1. The `run` value is a Prometheus label, so it is a string, and clicking the header sorts it as text.
2. The default order comes from one `sortBy` on `vsort`, which holds only the version. Rows of the same version have no defined order.

## Fix

Only `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`, panel titled `Per run evidence`.

**Queries.** In both targets, extend `vsort` to include the slug and a zero-padded run. Keep the existing three `label_replace` calls as they are, call that `V`, and wrap it:

`label_join(label_replace(label_replace(label_replace(V, "rpad", "00$1", "run", "([0-9])"), "rpad", "0$1", "run", "([0-9]{2})"), "rpad", "$1", "run", "([0-9]{3,})"), "vsort", "|", "vsort", "slug", "rpad")`

The `sum by (...)` lists stay exactly as they are and do not gain `rpad`. Claude ran this form against hub Prometheus on `m5-air` on 2026-11-06: 403 rows, and a task with 20 runs came back 20, 19, ... 1 when sorted descending by `vsort`.

**Transformations.** Keep `merge`, `sortBy` on `vsort` descending and `organize` as the first three, unchanged. Append after them:

`{"id": "convertFieldType", "options": {"fields": {}, "conversions": [{"targetField": "run", "destinationType": "number"}]}}`

The default order is then version, slug and run, all newest first, and clicking Run sorts by number.

**Test.** In `scripts/tests/plugins/agent_dispatch_dashboard.bats`, this bug changes one existing assertion. The check `"label_join(" not in target["expr"]` exists to stop a `doc` label being rebuilt in the query (`docs/bugs/2026-10-24-agent-dispatch-run-evidence-table-unreadable.md`). Replace only that clause with `'"doc"' not in target["expr"]`, and leave the `plans/` and `bugs/` clauses on the same line as they are. Add new assertions per the Acceptance block. If any other existing assertion fails, stop and report it. Do not edit it.

**Docs.** `docs/guides/grafana-dashboards/k3dm-agent-dispatch.md`: one sentence giving the default order and saying Run sorts by number. `CHANGELOG.md`: one bullet at the end of the `[Unreleased]` section.

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`
- `docs/guides/grafana-dashboards/k3dm-agent-dispatch.md`
- `CHANGELOG.md`

## Gates

`bats scripts/tests/plugins/agent_dispatch_dashboard.bats`, and `pytest scripts/tests/bin/test_dashboard_queries.py` with `PATH` including a Python that has PyYAML. Paste the output, including failures.

## What NOT to Do

- Do NOT add a second field to `sortBy` or an `options.sortBy` to the table.
- Do NOT rename the `run` field, or change the panel's position, width or links.
- Do NOT change the exporter.
- Do NOT commit, push or create a PR. Claude reviews and commits.
- Do NOT touch `memory-bank/` or any file outside the Files list.

## Acceptance

```yaml
interface:
  - "scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml: the agent-dispatch.json key, the panel titled Per run evidence"
must:
  - id: M1
    text: "Each target's query sets vsort from vsort, slug and a run padded to at least three digits, joined by |, keeps the version rewrite, and has the same sum by label list as before."
  - id: M2
    text: "Transformations begin merge, sortBy on vsort descending, organize, and a later convertFieldType converts run to number."
must_not:
  - id: N1
    text: "Run order is never text order: applying the query's three rpad rules, a run of 9 pads to a key that sorts before 10, and 10 before 100. Paired control: runs 1, 2 and 3 sort in order under the same rules."
  - id: N2
    text: "The query does not rebuild a doc or URL label: no \"doc\", plans/ or bugs/ in any expr, and label_join appears exactly once per target and writes only vsort. Paired control: spec_url is still in target A and the slug link still reads it."
  - id: N3
    text: "rpad does not reach the table: it is not in any sum by list. Paired control: vsort is, and stays excluded by organize."
evidence:
  - id: E1
    proves: [M1, M2, N1, N2, N3]
    kind: offline
    what: "Claude's review run of the Gates on the task branch."
  - id: E2
    proves: [M1, M2, N1, N2, N3]
    kind: offline
    what: "Independent verifier's tests, written from this block only, pass on the landed commit. M1, M2 and N1 are red on its parent. N2 and N3 are red by mutants: a label_join writing a doc label; rpad added to a sum by list."
  - id: E3
    proves: [M1, N1]
    kind: live
    what: "Claude: the panel's committed target A expression, run read-only on hub Prometheus, returns a task's runs in numeric order when sorted descending by vsort."
  - id: E4
    proves: [M2]
    kind: live
    what: "Operator: after the dashboard is synced, the default order is newest version, slug and run first, and clicking Run sorts by number."
```
