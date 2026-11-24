# Bug: ArgoCD Degraded / OutOfSync alerts never match the cluster-prefixed shopping-cart Application names

**Status:** LANDED — `400041df` on `k3d-manager-v1.45.1` (2026-11-23; independent verifier pass); header corrected 2026-11-24
**Priority:** P3 — a monitoring gap: `ArgoCDAppProgressingStuck` (no name filter) and the dashboards still cover them
**Introduced by:** `4c5d3556` (v1.16.0, Applications renamed `<cluster>-<service>`); the name regex dates from the v1.12.0 alert work
**Should have been caught by:** offline test (promtool rule tests use the old bare names, if any; not checked)
**Introducing change reviewed:** unknown
**Waiting on:** live check — since 2026-11-23 (L1: Claude reads argocd_app_info names on the hub Prometheus after a promote)
**Triage:** patch → v1.45.1 (operator, 2026-11-23)
**Intent approved:** operator, 2026-11-23
**Prior art:** Pass 1 `ls docs/bugs/*-argocd-alert-name-regex-misses-cluster-prefixed-apps.md`: none; `make find-similar-docs` not run (vector store unavailable); [`2026-06-30-argocd-alerts-app-specific-outofsync.md`](2026-06-30-argocd-alerts-app-specific-outofsync.md) (name grep) — read, the change that wrote the bare-name regex; this is its rot after the rename
**Filed:** 2026-11-23
**Detected by:** Claude, while writing the R1 spec, 2026-11-23

## What is wrong

- `scripts/etc/argocd/platform-ops/prometheusrule.yaml:36-39` (`ArgoCDAppDegraded`) and `:49-52` (`ArgoCDAppOutOfSync`)
  filter `argocd_app_info{name=~"shopping-cart-(apps|basket|...)|data-layer|trivy-operator|ubuntu-hostinger-(eso|platform)"}`.
- PromQL `=~` is fully anchored. The service Applications are named `'{{.name}}-{{.path.basename}}'`
  (`scripts/etc/argocd/applicationsets/services-git.yaml:41`), e.g. `<cluster>-shopping-cart-order`, so the
  `shopping-cart-(...)` alternative never matches them. (Verified by reading both files, 2026-11-23; live `argocd_app_info`
  names not queried.)
- Not checked: whether `data-layer` and `trivy-operator` still carry those exact names.

## Fix

Allow an optional cluster prefix on the service alternative (`(.+-)?shopping-cart-(...)`), after confirming the live
names with a read-only `argocd_app_info` query (operator or Claude on the hub). Add or update a promtool unit test with a
cluster-prefixed series.

## Files

| File | Change |
|---|---|
| `scripts/etc/argocd/platform-ops/prometheusrule.yaml` | `ArgoCDAppDegraded` and `ArgoCDAppOutOfSync` name regex: optional cluster prefix on the shopping-cart alternative |
| `scripts/tests/plugins/argocd_app_alert_regex.bats` | new: `promtool test rules` over a heredoc test file (follow `scripts/tests/plugins/dispatch_alert_rules.bats` for extracting the rule group and handling a missing promtool) |
| `scripts/tests/plugins/argocd_metrics_servicemonitor.bats` | added after dispatch (spec defect: missed reader): its `grep -F` pins the literal regex string and must follow the new text |

Read only: `scripts/etc/argocd/applicationsets/services-git.yaml`.

## Acceptance

```yaml
must:
  - id: M1
    text: ArgoCDAppDegraded and ArgoCDAppOutOfSync fire for a series named <cluster>-shopping-cart-order with the matching status
  - id: M2
    text: they still fire for the bare names already listed (data-layer, trivy-operator, ubuntu-hostinger-eso) (positive control)
must_not:
  - id: N1
    text: a Degraded <cluster>-shopping-cart-order series must not go unalerted
    red_on_current: the anchored regex excludes cluster-prefixed names
evidence:
  - id: E1
    proves: [M1, M2, N1]
    kind: offline
    command: promtool test rules with a new test file feeding argocd_app_info series for ubuntu-hostinger-shopping-cart-order (Degraded, OutOfSync) and data-layer (Degraded)
    red_control: on current rules the prefixed series produce no alert
    intent: When a shopping-cart app on the hub goes Degraded or stays out of sync, the operator gets the ArgoCD alert again.
  - id: L1
    proves: [M1]
    kind: live
    command: Claude, read-only, after promote - query argocd_app_info names on the hub Prometheus and confirm the rule's regex matches each shopping-cart Application
    red_control: any shopping-cart Application name the regex does not match
    intent: The fixed alert covers every shopping-cart app name that actually exists on the hub.
```

## Routing

Luna (rule regex + a promtool test file). Does **not** touch R1's files (`services-git.yaml` is read only), so it can
dispatch now, subject to the WIP limit.
