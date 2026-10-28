# Bug: Plans table repeats plan identity in Plan and Title columns

**Status:** VERIFIED — 38 dashboard BATS pass; operator deployment/click pending
**Priority:** P3
**Filed:** 2026-10-28
**Branch:** k3d-manager-v1.43.9
**Approval:** explicit operator request: keep Title, link it to the plan, remove visible Plan to reduce crowding.

The original v1.43.5 release-plan-tracking spec intentionally showed both fields.
This request explicitly amends that presentation for the Plans table only.
Keep Title and transfer the existing plan-document link to it. Hide the Plan
field with custom.hidden, retaining the exact plan stem for URL interpolation;
do not exclude it in organize. Preserve scanned branch, dependency/dispatch
links, all queries, sorting, status columns, widths and other panels.

## Files

- scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml
- scripts/tests/plugins/grafana_dashboard_bugs.bats

## Acceptance

Only Title is visible for plan identity, Title opens the same plan document on
the scanned branch, and hidden Plan/branch values survive organize for the link.
Existing dashboard BATS and embedded JSON checks pass. Operator applies the
single existing Bug Tracking ConfigMap, reloads, verifies column removal and
clicks a Title before live closure. No new panels, metrics or plan docs.
