# Bug: Rejected-attempt Codex tokens shows No data when no run was rejected

**Status:** LIVE-VERIFIED 2026-10-25 — `9d6f6a06`; pytest 91/91, ruff clean, new test red on the pre-fix script; live: panel 44 reads 0 at Window 1d and v1.43.7 (operator screenshots 245, 246)
**Live evidence:** 2026-10-25 · run hub-grafana-dispatch-rejected-tokens-screenshot · env hub/k3d-k3d-cluster · scenario agent-dispatch/rejected-tokens-zero · commit 9d6f6a06 · proves E2
**Fix commit:** `9d6f6a06`
**Live note:** E2 names window v1.43.6; the screenshots show 1d and v1.43.7, which take the same zero path; the dry run also prints 0 for v1.43.6
**Priority:** P3
**Severity:** low — the panel says "unavailable" when the true answer is a measured 0
**Release:** v1.43.7 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-25, by Claude, from the operator's screenshot 234
**Approval:** explicit 2026-10-25 ("sounds good", after Claude proposed emitting 0). Not critical (metrics script only).
**Component:** `bin/k3dm-dispatch-metrics`
**Related:** `docs/bugs/2026-10-21-dispatch-dashboard-missing-codex-telemetry-renders-zero.md` (missing telemetry must never render as zero; this fix keeps that rule)

## Problem

On k3dm Agent Dispatch, **Rejected-attempt Codex tokens** (panel 44) shows No data for v1.43.6.
Its description says No data means the total is unavailable, not zero.

`_run_metrics` sets `rejected_known = True` only after adding a known token increment from an
objectively rejected run (outcome `rework` or `failed` with evidence `land_refused.tests` or
`codex_exit.exit`). When the window has runs but none of them is objectively rejected, nothing is
added, `rejected_tokens` is returned as `None`, and `_render` emits no
`k3dm_dispatch_objectively_rejected_codex_tokens` line. v1.43.6's only failed run is an
`abandon.event`, which is deliberately not an objective rejection, so the panel reads as
unavailable when the measured value is 0.

## Fix

In `_run_metrics`, track whether any objectively rejected run was seen, and whether any of them had
an unknown increment:

- No objectively rejected run, and at least one counted run in the window (`sum(outcomes) > 0`):
  `rejected_tokens = 0`.
- At least one objectively rejected run, every one with a known increment: the sum (unchanged).
- At least one objectively rejected run with a known increment and another with an unknown one:
  the sum of the known ones (unchanged behaviour).
- Objectively rejected runs exist, none with a known increment: `None` (unchanged).
- No counted runs in the window: `None` (unchanged).

`_render` is unchanged: it already emits the line whenever the value is not `None`. Update panel
44's description wording only if Claude asks; do not edit the dashboard.

## Tests

Add to `scripts/tests/bin/test_dispatch_metrics.py`:

1. A window with one accepted run and one `abandon.event` failed run emits
   `k3dm_dispatch_objectively_rejected_codex_tokens{window="30d"} 0`.
2. A window with no runs at all emits no `objectively_rejected_codex_tokens` line.
3. The existing `test_reset_cumulative_run_counter_stays_unknown` still passes unchanged (a rejected
   run with an unknown increment stays No data).
4. The existing known-increment test (`... 100`) still passes unchanged.

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: A window with counted runs and no objectively rejected run exports rejected-attempt Codex tokens as 0.
  - id: M2
    text: A window whose objectively rejected runs all have known increments exports their sum, as before.
must_not:
  - id: N1
    text: A window whose only objectively rejected runs have unknown token increments must not export a value (no fabricated 0).
  - id: N2
    text: A window with no counted runs must not export a value.
  - id: N3
    text: An abandoned run must not count as objectively rejected.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, N1, N2, N3]
    text: pytest scripts/tests/bin/test_dispatch_metrics.py green; test 1 red on a temp copy of the pre-fix script; ruff 0.15.8 clean.
  - id: E2
    kind: live
    proves: [M1]
    text: After the next metrics push, panel 44 shows 0 for window v1.43.6.
interface:
  - bin/k3dm-dispatch-metrics --dry-run (Prometheus text on stdout)
  - dispatch_metrics.render(events, start, end, repo_root=...) as imported by test_dispatch_metrics.py
  - Grafana /d/k3dm-agent-dispatch panel "Rejected-attempt Codex tokens"
```

## Definition of Done

- [ ] The Fix and a CHANGELOG `[Unreleased]` `### Fixed` entry; only the Files above change.
- [ ] `K3DM_DISPATCH_PUSHGATEWAY_URL=http://127.0.0.1:9 pytest scripts/tests/bin/test_dispatch_metrics.py` green; paste the summary.
- [ ] Test 1 shown red on a temp copy of the pre-fix script.
- [ ] Commit: `fix(dispatch-metrics): report zero rejected-attempt tokens when no run was rejected`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT change or remove any existing test or assertion.
- Do NOT count `abandon.event` runs as rejected, or emit 0 when a rejected run's increment is unknown.
- Do NOT edit the dashboard YAML.
- Do NOT push to the real Pushgateway or read the real ledger.
- Do NOT modify files outside the Files list.
