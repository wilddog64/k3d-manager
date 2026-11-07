# Bug: e2e results never reach the M5 hub, and runs dispatched from it fail before tests

**Filed:** 2026-11-07
**Branch:** `k3d-manager-v1.43.15` (moved 2026-11-07 by Claude, operator: "go ahead to move that four bugs to v1.43.15"; no landed fix to verify in v1.43.14; filed on `k3d-manager-v1.43.14`)
**Status:** OPEN
**Priority:** P2 — the hub has had no e2e signal since the 2026-10-31 cutover; the verification dashboards are empty and `E2EResultsMissing` has fired for the full 3-day window
**Waiting on:** operator decision — since 2026-11-07
**Approval:** pending — touches SSH trust between the M2 and the hub, and a GitHub credential
**Severity:** medium
**Related:** `docs/bugs/2026-09-15-e2e-remote-results-never-reach-grafana.md` (publish-back conf file), `docs/bugs/2026-09-23-e2e-dispatch-forward-ghcr-token-over-stdin.md`, `docs/bugs/2026-10-30-host-disk-labels-the-new-hub-as-m4-and-cannot-reach-m2.md` (its 2026-11-04 regression section), `docs/bugs/2026-11-07-hermes-e2e-summary-crashes-on-null-counts.md`

## Symptom

`E2EResultsMissing` (`absent(e2e_last_run_pass)`) has fired for the whole 3-day retention window (72 series-hours, 0 trips). The hub has no e2e-result ConfigMaps (`k3dm.k3d.io/e2e-result=true`) and no `e2e_*` series. `vulnerability-inventory-exporter` is up and scraped, so it has nothing to export.

## Findings (Claude, 2026-11-07, read-only)

**F1 — publication still targets M4, and M5 has no target.** The M2 log of run `1794051590-16732` ends `WARN: [e2e-remote] M4 publication unavailable; retained 1794051590-16732.publication_pending.json for replay`. The publish-back host comes from `E2E_M2_PUBLISH_BACK_HOST`, read under launchd from `~/.config/k3d-manager/e2e-remote.env` (the 2026-09-15 fix). That file exists on the M4 and names `m4-air.local`. On the M5 the directory holds only `machine-role`. The cutover and `make machine-setup ROLE=hub` did not carry it over, nor the matching publisher key and forced-command entry. The M2 holds 10 `publication_pending` results.

**F2 — runs fail at `deploying-substrate`.** Same run: `GHCR_PAT env var authenticates but cannot pull from ghcr.io — it is missing the read:packages scope`. The Vault fallback then fails with `error: context "k3d-k3d-cluster" does not exist`, although `kubectl config get-contexts` on the M2 lists that context; the fallback (`scripts/plugins/shopping_cart.sh:328`) probably runs with the vCluster's kubeconfig. The forwarded token comes from the dispatching host, now the M5. Cause of the missing scope and the kubeconfig in the fallback are not confirmed.

Since the summary has null counts, Hermes then crashes (separate bug, linked above).

## Progress

- 2026-11-07: operator ran `gh auth refresh` on the M5 (F2 step 1). Next: one e2e run dispatched from the M5 shows whether `deploying-substrate` now passes (E2).

## Decision needed

1. F1: point publish-back at the M5. Either Claude specs `make machine-setup ROLE=hub` to install the conf file, publisher key and forced-command entry (and a read-only check), or the operator recreates them by hand once. Either way, `make e2e-replay` then drains the 10 pending results.
2. F2: refresh the M5's GitHub credential with `read:packages` (`gh auth refresh -h github.com -s read:packages`, run by the operator), then rerun one e2e. The kubeconfig in the Vault fallback needs a separate look only if the token fix is not enough.

## Acceptance

```yaml
interface:
  - "~/.config/k3d-manager/e2e-remote.env on the hub; scripts/plugins/e2e_remote.sh e2e_runner_publish_back; make e2e-replay"
must:
  - id: M1
    text: "A run dispatched from the M5 publishes its result to the M5 hub: an e2e-result ConfigMap appears and e2e_last_run_pass has a series."
  - id: M2
    text: "A run dispatched from the M5 passes deploying-substrate."
must_not:
  - id: N1
    text: "No result is published to the M4."
evidence:
  - id: E1
    proves: [M1, N1]
    kind: live
    what: "Claude: after the change and make e2e-replay, the hub has e2e-result ConfigMaps, E2EResultsMissing resolves, and the M2's publish audit names the M5."
  - id: E2
    proves: [M2]
    kind: live
    what: "Claude: the next run's summary on the M5 has a phase past deploying-substrate and non-null counts."
```
