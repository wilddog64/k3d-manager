# Bug: Security findings by image shows tier as its own column, which reads like part of the image

**Filed:** 2026-11-07
**Branch:** `k3d-manager-v1.43.14`
**Status:** LANDED 2026-11-07 — 5b7ecd15 (Luna, second run; reviewed by Claude, CHANGELOG conflict resolved by Claude); independent verifier running
**Fix commit:** 5b7ecd15
**Priority:** P3 — cosmetic; every row is present and correct
**Waiting on:** live check — since 2026-11-07
**Approval:** explicit 2026-11-07 "I think what we can do is to combine tier and image_repository: <repo> + upstream, i.e. argoproj/argocd (upstream). less confusing" (operator)
**Severity:** low

## Symptom

On the Alertmanager delivery dashboard, panel **Security findings by image** (id 10), the operator asked what the `tier` column means and whether it is the same as `image_repository`. Every row reads `upstream`, so the column looks like part of the image name. The `findings` column is also easy to misread as a CVE count; it is the number of firing Trivy alert series, one per cluster and namespace that runs the image. Claude misread it that way on 2026-11-07.

## Fix

Only `scripts/etc/argocd/platform-ops/grafana-dashboard-alertmanager-delivery.yaml`, panel id 10.

1. **Query.** Build one `image` label: `<image_repository> (upstream)` when `tier` is `upstream`, and `<image_repository>` when `tier` is empty. With `X` = `ALERTS{alertstate="firing",alertname=~"Trivy.*"}`:
   `count by (image, alertname) (label_replace(label_replace(label_join(X, "image", "|", "image_repository", "tier"), "image", "$1 ($2)", "image", "(.+)\\|(.+)"), "image", "$1", "image", "(.+)\\|"))`
   Escape it as the YAML file already escapes its JSON strings.
2. **Table.** Columns, in order: `image`, `alertname`, `Value` renamed to `firing in`. Drop `tier` from `indexByName`. Change `options.sortBy` to `firing in` descending.
3. **Description.** One row per image. `(upstream)` marks a third-party image we only consume, with no auto-remediation; no suffix means one of our images, remediated through the CVE loop. `firing in` is the number of cluster and namespace places where the image has critical CVEs, not the number of CVEs; see the CVE inventory dashboard for counts. This is a backlog, not a page.
4. **Test.** Add assertions per the Acceptance block to `scripts/tests/plugins/alertmanager_delivery_dashboard.bats`, the existing test for this dashboard. If an existing assertion fails, stop and report it. Do not edit it. (2026-11-07: the first dispatch stopped because this step and the Files list disagreed; Claude corrected the Files list.)
5. `CHANGELOG.md`: one bullet at the end of `[Unreleased]`.

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-alertmanager-delivery.yaml`
- `scripts/tests/plugins/alertmanager_delivery_dashboard.bats`
- `CHANGELOG.md`

## Gates

`bats scripts/tests/plugins/alertmanager_delivery_dashboard.bats` and `pytest scripts/tests/bin/test_dashboard_queries.py`, with `PATH` including a Python that has PyYAML. Paste the output, including failures.

## What NOT to Do

- Do NOT change the alert rules or the `tier` label.
- Do NOT change any other panel, or this panel's position or size.
- Do NOT commit, push or create a PR. Claude reviews and commits.
- Do NOT touch `memory-bank/` or any file outside the Files list.

## Acceptance

```yaml
interface:
  - "scripts/etc/argocd/platform-ops/grafana-dashboard-alertmanager-delivery.yaml: the embedded dashboard JSON, panel id 10 titled Security findings by image"
must:
  - id: M1
    text: "The panel's query groups by image and alertname only. Applying its label rules to a series with image_repository argoproj/argocd and tier upstream gives image 'argoproj/argocd (upstream)'; with image_repository wilddog64/foo and no tier it gives 'wilddog64/foo'."
  - id: M2
    text: "The table shows image, alertname and firing in, in that order, sorted by firing in descending, and the description says firing in is not a CVE count."
must_not:
  - id: N1
    text: "No tier column and no tier in the by list. Paired control: the word upstream still reaches the image value for an upstream series."
  - id: N2
    text: "No image value ends in '|' or contains '()' for a series without a tier."
evidence:
  - id: E1
    proves: [M1, M2, N1, N2]
    kind: offline
    what: "Independent verifier, tests from this block only; label rules checked by running the query against a local Prometheus or by an equivalent regex evaluation, with N1 shown red against the pre-fix panel."
  - id: E2
    proves: [M1]
    kind: live
    what: "Operator: the panel shows rows such as argoproj/argocd (upstream) after the dashboard syncs."
```
