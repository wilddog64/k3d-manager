# Bug: acg-up cannot install the sandbox Pushgateway on a hub without the `prometheus-community` Helm repo

**Status:** FIXED — `2a2a43c9` (Codex; Claude review, independent verify); E2 (live) pending
**Fix commit:** 2a2a43c9
**Priority:** P3
**Severity:** low — deployment metrics from the sandbox are disabled; the run completes
**Approval:** operator, 2026-11-01 (hub-migration gaps are filed as found)
**Filed:** 2026-11-01
**Detected by:** Claude, reading job `cdff3cea` output on the M5
**Affected:** `scripts/plugins/observability.sh` (`_deploy_pushgateway_acg`, ~line 687)
**Branch:** `k3d-manager-v1.43.13`
**Related:** `memory: project_m5_air_new_hub` (hub-migration gaps)

## Observed failure

Job `cdff3cea` (M5, 2026-11-01): `Error: repo prometheus-community not found` then
`WARN: [observability] Pushgateway install failed — deployment metrics disabled`. `helm repo list` on the M5 has
external-secrets, hashicorp, jp-gouin and argo, but no prometheus-community.

## Root cause

`_deploy_pushgateway_acg` installs `prometheus-community/prometheus-pushgateway` but never adds the repo. It worked on
the M4 only because that machine had the repo from an earlier manual add.

## Fix

Before the install, add the repo idempotently, as `argocd.sh` does:
`helm repo add --force-update prometheus-community https://prometheus-community.github.io/helm-charts`. A failed add
warns and skips the install, as the install failure does today. Keep the chart version pin `2.14.0`.

## Files

- `scripts/plugins/observability.sh`
- `scripts/tests/plugins/observability.bats` (or the suite covering `_deploy_pushgateway_acg`)
- `CHANGELOG.md`

## What NOT to do

- Do not run `helm repo update` for every repo, and do not change the chart version.
- Tests stub `helm`, record argv in a scratch dir, and never reach a cluster or the network.

## Acceptance

```yaml
must:
  M1: _deploy_pushgateway_acg runs helm repo add --force-update prometheus-community <url> before helm upgrade --install
  M2: a failing repo add warns and returns 0 without running the install
must_not:
  N1: the install's chart reference, --version 2.14.0 and values do not change
evidence:
  E1:
    proves: [M1, M2, N1]
    kind: offline
    intent: You will see BATS with a stub helm show the add before the install (red on the pre-fix code), the failing add skip the install with a warning, and the install argv unchanged.
    what: bats on the observability suite
  E2:
    proves: [M1]
    kind: live
    intent: You will see the next /cluster-up on the M5 log the Pushgateway installed, with no "repo prometheus-community not found".
    what: Claude reading the webhook job output on the M5
interface:
  - _deploy_pushgateway_acg [context]
  - helm on PATH
```

## Verification (2026-11-01, Claude)

- Landed as `2a2a43c9` through `make codex-land`; the ledger records `land` and `verify` events for slug `2026-11-01-sandbox-pushgateway-install-needs-local-helm-repo`.
- Offline evidence: land test on `scripts/tests/plugins/observability_k3dm_tests_rules.bats` passed (rc 0), landed with `--allow-out-of-scope` (that suite is the one the spec names as covering the install). Independent black-box verifier (Sonnet, tests written from the Acceptance block only): PASS; M1/M2 red on pre-fix code, N1 invariant.
- Errors seen: none.
- E2 (live) pending: the next sandbox `make up` shows the Pushgateway install succeed on the M5 hub.
