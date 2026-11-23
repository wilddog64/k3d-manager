# Bug: agy dashboard panels label headless sessions "print", which reads as nothing

**Status:** OPEN
**Priority:** P3 — cosmetic; the operator had to ask what "print" meant
**Introduced by:** unknown (the agy mode split in `bin/k3dm-dispatch-metrics`)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** dispatch
**Triage:** patch → v1.45.1 (operator, 2026-11-23: "change print to headless session")
**Intent approved:** operator, 2026-11-23
**Prior art:** Pass 1 `ls docs/bugs/*-agy-dashboard-print-mode-label-unclear.md`: none; `make find-similar-docs` not run; [`2026-11-21-agy-transcript-sessions-always-unknown-repo-and-mode.md`](2026-11-21-agy-transcript-sessions-always-unknown-repo-and-mode.md) (name grep) — read, different defect (repo/mode detection), same panels
**Filed:** 2026-11-23
**Detected by:** operator, 2026-11-23 (screenshot of "agy untracked by repo": "what does print mean?")

## What is wrong

`bin/k3dm-dispatch-metrics:2641` labels an agy session `mode="print"` when its id is not in agy's `history.jsonl`
(a headless `-p` run, for example an Argon review). Two panels in
`scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml` show that value raw through `{{mode}}`:
"agy sessions by mode" (legend `{{mode}}`, ~line 1065) and "agy untracked by repo" (legend `{{repo}} {{mode}}`,
~line 1116). "print" means nothing to a reader.

## Fix

Display-only. Rename `print` to `headless` in those two panels with a Grafana `renameByRegex` transformation, so a
legend reads `headless` / `k3d-manager headless`. Do **not** change the metric label value: `mode="print"` is read by
`scripts/tests/bin/test_dispatch_metrics.py` and by Prometheus history, and changing it would split the series.

## Contract readers

None change. The `mode` label value stays `print`; readers by grep: `bin/k3dm-dispatch-metrics:2333,2641`,
`scripts/tests/bin/test_dispatch_metrics.py`. Only the two panels' display changes.

## Acceptance

```yaml
must:
  - id: M1
    text: the "agy sessions by mode" and "agy untracked by repo" panels each carry a renameByRegex transformation mapping a display name ending in "print" to the same name ending in "headless"
  - id: M2
    text: the panels' targets (expr, legendFormat) are unchanged, and no other panel in the dashboard gains or loses a transformation (positive control on scope)
must_not:
  - id: N1
    text: the two agy panels must not display the raw value "print"
    red_on_current: neither panel has a transformation, so the legend shows "print"
  - id: N2
    text: bin/k3dm-dispatch-metrics must not change (the mode label value stays print)
    red_on_current: n/a (scope guard)
evidence:
  - id: E1
    proves: [M1, M2, N1, N2]
    kind: offline
    command: a new test in scripts/tests/plugins/agent_dispatch_dashboard.bats that parses the dashboard JSON and asserts, by panel title, the renameByRegex transformation (regex matching "print" at the end, renamePattern ending "headless") on both agy panels, their unchanged expr and legendFormat, and no transformation on the codex "Untracked by repo" and "Sessions by mode" panels; plus git diff showing bin/k3dm-dispatch-metrics untouched
    red_control: on the current dashboard the transformation assertions fail
    intent: The agy panels say "headless" instead of "print", so the operator can read them without asking.
  - id: L1
    proves: [N1]
    kind: live
    command: operator or Claude, read-only, after promote - open the Agent Activity dashboard and check both agy panels' legends read "headless"
    red_control: a legend still showing "print"
    intent: The live dashboard on the hub shows the new wording.
```

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml` — add the transformation to the two agy panels
- `scripts/tests/plugins/agent_dispatch_dashboard.bats` — the E1 test

## Routing

Luna, one dashboard file plus a test. Shares no file with the running dispatches (argocd-alert-regex, totp-a2,
age-identity). Dispatch at the next free slot.
