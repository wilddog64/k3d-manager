# Bug: trivy-operator 0.32.0 silently skips private images whose pull cred is a ServiceAccount `imagePullSecrets`

**Cluster:** `ubuntu-hostinger` (app-cluster)
**Component:** trivy-operator 0.32.0 (chart 0.34.0), trivy 0.72.0, ClientServer mode
**Impact:** CVE dashboard **panel ② ("Shopping-cart Unique CVEs")** stays empty — the private
`ghcr.io/wilddog64/shopping-cart-*` workloads never get a `vulnerabilityreport`.

---

## Symptom

After the scan-job CPU-request and timeout fixes
(`2026-08-23-hostinger-trivy-scanjob-cpu-request-unschedulable.md`) let scan jobs schedule and
run, hostinger produced **13 `vulnerabilityreports` — all for public images** (istio, postgres,
minio, rabbitmq, loki, coredns, …). The five private `wilddog64/shopping-cart-*` workloads
(basket, frontend, order, product-catalog, payment) got **no scan job at all** — no Pending pod,
no Failed job, no error event. Silently skipped.

## Root cause (CORRECTED — the title's "ServiceAccount imagePullSecrets" was the initial hypothesis)

The workloads carry **no `imagePullSecrets` anywhere** — not on the pod spec **and not on the
ServiceAccount** (all use `default`, verified: pod-spec and SA `imagePullSecrets` both empty). They
pull the private `ghcr.io/wilddog64/shopping-cart-*` images via a **node-level k3s/containerd
registry credential** (`/etc/rancher/k3s/registries.yaml`), which is invisible to trivy-operator.
The operator discovers pull creds only from the pod spec / ServiceAccount, finds none, treats the
image as unpullable, and emits no scan job — silently (no diagnostic).

This is why an **operator upgrade would NOT help**: there is no in-cluster imagePullSecret for any
version of the operator to discover.

Proof the image itself is scannable: a one-off Job that mounts `ghcr-pull-secret` as
`DOCKER_CONFIG` and runs `trivy image --server …` succeeds in ~5 s
(`diag-trivy-scan.yaml` in the session scratchpad).

## Fix (DURABLE, NATIVE) — `operator.privateRegistryScanSecretsNames`

trivy-operator supports pointing scan jobs at a **named secret per namespace** for exactly this case
("used to authenticate in private registries in case [there are] no imagePullSecrets provided",
upstream issue #2158). Set in `scripts/etc/helm/observability/trivy-operator-acg-values.yaml`
(commit `aac9cb27`):

```yaml
operator:
  accessGlobalSecretsAndServiceAccount: true       # chart default true; pinned explicitly
  privateRegistryScanSecretsNames:
    shopping-cart-apps: ghcr-pull-secret
    shopping-cart-payment: ghcr-pull-secret
```

Renders to env `OPERATOR_PRIVATE_REGISTRY_SCAN_SECRETS_NAMES={"shopping-cart-apps":"ghcr-pull-secret","shopping-cart-payment":"ghcr-pull-secret"}`.
The operator then runs its own scan jobs **in the target namespace** (to mount the secret) and
writes self-refreshing `VulnerabilityReport`s (report-ttl `24h`) under its configured
`ignoreUnfixed: true` + `severity: CRITICAL,HIGH` policy — consistent with every other workload.

**Live-verified (2026-08-24):** after adding the env + operator restart, all 5 private workloads got
native operator-generated reports; hub Prometheus `count(trivy_vulnerability_inventory{image_repository=~"wilddog64/shopping-cart-.*"}) = 75`
actionable series. Panel ② fills with self-refreshing native data.

### Companion requirement — payment namespace egress
`shopping-cart-payment` has a `default-deny-all` NetworkPolicy. Because the scan job runs **in that
namespace** (to mount the secret) and, in ClientServer mode, the client pod must egress to the
registry (pull layers) + trivy-server, the scan pod needs an egress allow. Live-applied
`allow-cve-scan-egress` (podSelector `app.kubernetes.io/managed-by=trivy-operator`, egress `[{}]`).
**Durable home = the shopping-cart-payment repo** (cross-repo companion; tracked separately). Without
it, the four `shopping-cart-apps` workloads still scan (no default-deny there), but payment does not.

## What did NOT work (earlier config levers, all no-op → reverted)

- `scanJob.useGCRServiceAccount=false` (trivy config CM)
- `vulnerabilityReports.scanJobsInSameNamespace=true` (operator CM)
- `OPERATOR_ACCESS_GLOBAL_SECRETS_SERVICE_ACCOUNTS=true` **alone** (operator env) — necessary but
  not sufficient; it needs `privateRegistryScanSecretsNames` to name the secret, since there is no
  imagePullSecret on the workload to auto-discover.

## Interim stopgap (2026-08-24, now SUPERSEDED by the native fix)

Before the native fix was found, panel ② was filled with **manual `VulnerabilityReport` CRs** built
from one-off trivy scans (mount `ghcr-pull-secret`, transform JSON → CRs mirroring the operator's
name/labels/ownerRefs, `kubectl apply --server-side`). That produced **352** series (all severities,
unfixed included). It was a point-in-time snapshot that would drift, so it was **deleted** and the
operator regenerated the reports natively once `privateRegistryScanSecretsNames` was set.

CRD gotcha worth keeping (if ever hand-authoring CRs again): each `report.vulnerabilities[]` entry
**requires** both `publishedDate` and `lastModifiedDate` or the apply is rejected. Also the exporter
reads `finding.primaryURL` but the CR field is `primaryLink` — cosmetic, `primary_url` label comes
through empty.

**352 vs 75:** the manual scan captured every severity + unfixed; the native operator applies
`ignoreUnfixed: true` + `severity: CRITICAL,HIGH`, so it reports **75 actionable** series — the
correct, dashboard-consistent number (shopping-cart is now scored the same way as every other
service, not artificially inflated).

## The three originally-documented "durable options" — reassessed

1. **Add `imagePullSecrets` to the pod specs** — UNNECESSARY for scanning now (native fix covers it);
   remains optional hardening (explicit pull creds vs node-level). Cross-repo, gated.
2. **Scan → CR CronJob** — REJECTED. Now redundant *and* harmful: it would fight the operator for
   ownership of the same CR names (ownerReferences → the ReplicaSet) and double-scan.
3. **Upgrade trivy-operator** — DEAD END. There is no in-cluster imagePullSecret to discover; no
   version resolves a node-level containerd credential. An upgrade cannot fix this root cause.

The native `privateRegistryScanSecretsNames` fix (above) supersedes all three.

## Definition of Done

- [x] Real root cause identified (NO imagePullSecret on pod spec or SA; node-level containerd cred).
- [x] Native durable fix (`privateRegistryScanSecretsNames`) committed `aac9cb27` + live-verified.
- [x] Panel ② populated (75 actionable series) + Prometheus-verified; native reports self-refresh (24h TTL).
- [x] Manual-CR stopgap deleted; earlier config-lever drift reverted.
- [x] `acg-trivy-operator` ArgoCD app synced to git (2026-08-24) — converged the 3 OutOfSync
      resources via a manual sync operation (app `$values` ref = `k3d-manager-v1.27.0`, which
      contains `aac9cb27`, so the sync preserved `OPERATOR_PRIVATE_REGISTRY_SCAN_SECRETS_NAMES` +
      `ACCESS_GLOBAL_SECRETS=true`). App now **Synced/Healthy**, operator 1/1, all 5 private
      workloads still scanned (28–33m fresh); panel ② held at 75 across the sync.
- [x] `allow-cve-scan-egress` NetworkPolicy durable home spec'd in the shopping-cart-payment repo —
      `docs/plans/durable-trivy-scan-coverage.md`, branch `feat/trivy-scan-egress-netpol` (`3ca0dca`,
      pushed, PR gated). Flags the kustomize `commonLabels`→selector gotcha; also covers the optional
      SA `imagePullSecrets` hardening. Live netpol remains drift until that merges + reconciles.
