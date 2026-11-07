# Bug: the Window dropdown on the Agent Dispatch and Agent Cost dashboards sorts releases alphabetically

**Status:** OPEN — filed 2026-11-07; fix in progress on `k3d-manager-v1.43.15`
**Priority:** P3 (cosmetic: the dropdown order is wrong, every option still works)
**Waiting on:** fix running — since 2026-11-07
**Severity:** low
**Approval:** operator 2026-11-07: "go ahead, but don't forget the file a bug for it too"
**Release:** v1.43.15 (bug docs do not count toward the plan cap)

## Symptom

The operator opened the Window variable on the Agent Dispatch dashboard (screenshot, 2026-11-07). The options read:

```
v1.43.2
v1.43.15
v1.43.14
v1.43.13
v1.43.12
v1.43.10
v1.43.0
7d
```

`v1.43.2` sits above `v1.43.15`. That is alphabetical descending order: as text, `"v1.43.2"` is greater than
`"v1.43.15"` because the character `2` is greater than `1`. The operator wants the releases in version order, which
is also date order, since releases are cut in sequence.

## Cause (partly unconfirmed)

Both dashboards define the variable as a Prometheus `label_values(k3dm_dispatch_landed, window)` query with
`"sort": 7`, Grafana's natural ascending sort, set since v1.43.5 (`401e4eca`, `61256041`):

- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml`

Natural ascending would list `7d, v1.43.0, v1.43.2, v1.43.10 … v1.43.15`. That is the wrong direction for the
operator's need (newest last), and it is also **not** what the hub shows. Prometheus returns label values in
ascending order, so ignoring the sort would not produce the descending list in the screenshot either. The running
Grafana version could not be read: the hub API was unreachable from the M4 (`127.0.0.1:55730` refused) when this was
filed. Whether this Grafana applies natural sort is therefore unproven, and the live check (E2) settles it.

The Agent Activity dashboard is not affected: its Window options are a fixed custom list (`1d,7d,30d`) shown in the
order written.

## Fix

Set `"sort": 8` (natural descending) on the Window variable of both dashboards. Expected order:
`v1.43.15, v1.43.14, v1.43.13, v1.43.12, v1.43.10, v1.43.2, v1.43.0, 7d`.

If E2 shows the order is still alphabetical, this Grafana does not apply natural sort, and the follow-up is to have
the exporter emit the windows in a form whose text order is version order. A change to the exporter is out of scope
here.

## Acceptance

```yaml
interface:
  - "scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml and grafana-dashboard-agent-cost.yaml: templating variable name=window"
  - "Grafana Agent Dispatch / Agent Cost dashboards, Window dropdown (live)"
must:
  - id: M1
    text: "The window variable on both dashboards has sort 8 (natural descending); type, query, label and the 7d default are unchanged."
must_not:
  - id: N1
    text: "Neither dashboard's window variable keeps an ascending or alphabetical sort (1, 2, 5, 6 or 7) (paired control: M1 reads the same field and finds 8)."
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    what: "bats agent_dispatch_dashboard.bats and pytest test_dispatch_metrics.py assert sort 8 on both dashboards; the new assertion is red on the pre-fix tree (sort 7)."
  - id: E2
    proves: [M1]
    kind: live
    what: "Operator or Claude, after make platform-ops from the release branch: the Window dropdown lists v1.43.15 first, v1.43.2 below v1.43.10, and 7d last."
```
