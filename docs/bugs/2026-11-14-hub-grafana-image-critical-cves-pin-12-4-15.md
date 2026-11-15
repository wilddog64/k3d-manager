# Bug: hub Grafana runs 11.4.0 with 9 critical CVEs; pin 12.4.15 by digest

**Status:** VERIFIED — cf26aabd; live E2 on the M5 2026-11-15 (deploy/hub 234bc2d1): pass, dashboards render (operator's Agent Cost screenshot); captured 2026-11-14 by Claude
**Priority:** P2
**Introduced by:** pre-existing (chart default since kube-prometheus-stack 67.9.0)
**Should have been caught by:** review
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store unreachable from the M4); parent `docs/bugs/2026-11-14-trivy-critical-hub-grafana-pgvector-nginx-local-path.md` (disposition 1, tag proof)
**Approval:** operator, 2026-11-14 ("let's go with your recommendation" — Grafana 12.4.15)
**Intent approved:** operator, 2026-11-14

## Symptom

The hub's Grafana is `docker.io/grafana/grafana:11.4.0`, the default of the grafana subchart 8.8.2 bundled with
kube-prometheus-stack `67.9.0` (`scripts/etc/argocd/applicationsets/observability.yaml:18`). Trivy reports 9 critical
findings in it. `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml:80` (`grafana:`) sets no image.

## Proof of external behaviour (Claude, m4-air, 2026-11-14)

- Tag scan (local `trivy` 0.76.2, `--platform linux/arm64 --severity CRITICAL`): 11.4.0 = 9, 11.6.16 = 2, **12.4.15 = 0**
  (2 high), 13.3.1 = 0 (20 high). Details in the parent doc.
- Chart: `helm pull kube-prometheus-stack --version 67.9.0`; `charts/grafana/values.yaml:97-105` has `image.registry`,
  `image.repository`, `image.tag` ("Overrides the Grafana image tag whose default is the chart appVersion") and
  `image.sha`.
- Render: `helm template` with our values file plus `grafana.image.tag=12.4.15`,
  `grafana.image.sha=2894082f6cf7081aefdc1389265c04000812309208c190d75e8c65f7a30e4b7e` gives
  `image: "docker.io/grafana/grafana:12.4.15@sha256:2894082f…4b7e"`; without them, `grafana:11.4.0`.
- Digest: Docker Hub `/v2/repositories/grafana/grafana/tags/12.4.15` (2026-11-14): index digest
  `sha256:2894082f6cf7081aefdc1389265c04000812309208c190d75e8c65f7a30e4b7e`, architectures amd64, arm, arm64.
- Risk: Grafana 12 removes Angular panels; no dashboard in `scripts/etc` or `docs` uses an Angular panel type. Storage
  renders as `emptyDir` (no PVC), so there is no database migration to undo: rollback is a revert.

## Fix

In `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`, under `grafana:`, add:

```yaml
  image:
    tag: "12.4.15"
    sha: "2894082f6cf7081aefdc1389265c04000812309208c190d75e8c65f7a30e4b7e"
```

Leave the chart version, registry and repository unchanged. Add a bats test that reads the values file with yq and
asserts the tag is exactly `12.4.15` and the sha is 64 lowercase hex, and fails when either is missing or the tag is
empty, `latest` or an 11.x version. One CHANGELOG bullet under Unreleased › Security (or Fixed if no Security heading).

## Files

- `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`
- `scripts/tests/plugins/observability_grafana_image.bats` (new)
- `CHANGELOG.md`

## Contract readers

- `scripts/etc/argocd/applicationsets/observability.yaml:19` — reader (ArgoCD renders the values file); no change.
- `scripts/tests/bin/prometheus_port_split.bats:4`, `scripts/tests/plugins/alertmanager_config_secret.bats:11,30`,
  `alertmanager_delivery_dashboard.bats:89`, `hub_pushgateway.bats:33,47`, `observability_federate_self_scrape.bats:3`,
  `argocd_loki.bats:7` — readers of other keys in the same file; must stay green, no change expected.
- `docs/howto/hub-rebuild-from-gitops-vault.md:304` — prose; no change.
- Writer: only the values file.

## Acceptance

```yaml
must:
  - id: M1
    text: the hub Grafana image is grafana/grafana:12.4.15 pinned by sha 2894082f…4b7e via the values file
  - id: M2
    text: every existing test reading kube-prometheus-stack-values.yaml stays green
must_not:
  - id: N1
    text: the values file leaves the Grafana image tag unset (chart default 11.4.0) — red today
  - id: N2
    text: the tag is empty, latest, or 11.x, or the sha is missing or not 64 hex
evidence:
  - id: E1
    proves: [M1, N1, N2]
    kind: offline
    command: bats scripts/tests/plugins/observability_grafana_image.bats
    intent: Grafana on the hub cannot silently fall back to the vulnerable 11.4.0 image.
  - id: E2
    proves: [M2]
    kind: offline
    command: bats scripts/tests/bin/prometheus_port_split.bats scripts/tests/plugins/alertmanager_config_secret.bats scripts/tests/plugins/alertmanager_delivery_dashboard.bats scripts/tests/plugins/hub_pushgateway.bats scripts/tests/plugins/observability_federate_self_scrape.bats scripts/tests/plugins/argocd_loki.bats
    intent: The rest of the monitoring stack's settings are untouched.
  - id: E3
    proves: [M1]
    kind: live
    command: after hub-promote and sync, kubectl -n monitoring get pod -l app.kubernetes.io/name=grafana -o jsonpath='{..image}' shows 12.4.15@sha256:2894082f…; Grafana dashboards load; Trivy VulnerabilityReport for grafana shows 0 critical
    intent: The hub's Grafana is on the patched version and the dashboards still work.
interface: none
```

## Live check (Claude, M5 hub, 2026-11-15, deploy/hub 234bc2d1)

- ArgoCD `kube-prometheus-stack` picked up the promote at about 13:04Z (promote tag 12:57:47Z) and went Synced Healthy at 234bc2d1.
- Pod image `docker.io/grafana/grafana:12.4.15@sha256:2894082f6cf7081aefdc1389265c04000812309208c190d75e8c65f7a30e4b7e`;
  grafana and both sidecars ready, 0 restarts; `/api/health` version 12.4.15, database ok.
- Dashboards: the sidecar delivered 41 dashboard files and provisioning finished with no `level=error` lines in the first 10 minutes.
  Listing them through the API would need admin credentials in a `kubectl exec` string, so the operator opens one dashboard
  in the browser to finish E2.
- Trivy: `replicaset-kube-prometheus-stack-grafana-5bb77b5c89-grafana` 0 critical, 2 high (was 9 critical, 57 high on 11.4.0).
- Dashboard render: the operator's screenshot of the Agent Cost dashboard's "By model" panel (shared in-session after the 13:05Z swap) shows
  gemini-3.8-flash $34.5, gpt-6-luna $8.77 and gpt-6.1-terra $0.890 for 7d, matching Prometheus `k3dm_dispatch_api_cost_by_model_usd{window="7d"}`
  queried at the same time (34.536, 8.773, 0.890). E2 complete.
- More render evidence (operator screenshots, 2026-11-15): k3dm PR Checks (stat, table, timeseries, state-timeline panels) and Agent Activity (bar gauge, stat, timeseries, bar chart, gauge panels) both render with data on 12.4.15.
