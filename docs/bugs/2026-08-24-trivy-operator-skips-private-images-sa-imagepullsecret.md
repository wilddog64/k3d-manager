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

## Root cause

trivy-operator 0.32.0 **does not resolve a ServiceAccount-level `imagePullSecrets`** when building
the scan job. The shopping-cart workloads pull with a secret (`ghcr-pull-secret`) attached to the
**workload ServiceAccount**, not referenced in the pod spec's `imagePullSecrets`. The operator only
wires pull creds it finds on the **pod spec**, so it treats the private image as unpullable and
emits no scan job (no diagnostic — the skip is silent).

Proof the image itself is scannable: a one-off Job that mounts `ghcr-pull-secret` as
`DOCKER_CONFIG` and runs `trivy image --server …` succeeds in ~5 s
(`diag-trivy-scan.yaml` in the session scratchpad).

## What did NOT work (config levers, all no-op)

Tried on the live operator, none produced a scan job for the private images:

- `scanJob.useGCRServiceAccount=false` (trivy config CM)
- `vulnerabilityReports.scanJobsInSameNamespace=true` (operator CM)
- `OPERATOR_ACCESS_GLOBAL_SECRETS_SERVICE_ACCOUNTS=true` (operator env)

All three were reverted to chart defaults after they proved ineffective.

## Workaround applied (2026-08-24) — manual VulnerabilityReport CRs from real scans

To unblock panel ② now, real trivy client scans were run for each of the five images as one-off
Jobs that mount `ghcr-pull-secret`, and the JSON was transformed into `VulnerabilityReport` CRs that
mirror what the operator would have written (same name
`replicaset-<rs>-<container>`, labels, `ownerReferences` → the live ReplicaSet). Applied to
hostinger with `kubectl apply --server-side`.

Result — hub exporter now emits **352** `trivy_vulnerability_inventory` series for
`image_repository=~"wilddog64/shopping-cart-.*"` (basket 9, order 20, payment 120,
product-catalog 203; frontend 0 → no series). Prometheus confirms
`count(...) = 352`. **Panel ② populated + verified.**

CRD gotchas discovered while building the CRs:
- Each `report.vulnerabilities[]` entry **requires** both `publishedDate` and `lastModifiedDate`
  (apply is rejected otherwise). trivy JSON supplies `PublishedDate`/`LastModifiedDate`; fall back
  to scan time when a finding omits them.
- The exporter reads `finding.primaryURL` but the CR field is `primaryLink` — cosmetic, the
  `primary_url` label just comes through empty. Non-blocking.

### Payment namespace egress
`shopping-cart-payment` has a `default-deny-all` NetworkPolicy that blocks scan-pod egress. A
scoped `allow-cve-scan-egress` NetworkPolicy (podSelector `cve-scan: "true"`, egress `[{}]`) was
added so a labelled scan pod can reach trivy-server + registry. Left in place for future re-scans;
it selects a label no real workload carries, so it is inert otherwise.

## Limitation

Manual CRs are a **point-in-time snapshot** — they do not refresh and will drift as images change.
This is a stopgap to fill the panel, not a durable pipeline.

## Durable options (decision pending — user's call)

1. **Add `imagePullSecrets` to the pod specs** (shopping-cart repos, cross-repo PRs). Makes the
   operator scan natively. Needs CPU headroom for a rollout on the 98%-reserved 2-CPU node.
2. **Productize the scan → CR generation as a CronJob** on hostinger (mount `ghcr-pull-secret`,
   scan the five images, apply CRs). Keeps reports fresh without touching the app pod specs.
   The session scratchpad `gen-cve-reports.py` is the working prototype.
3. **Upgrade trivy-operator** past 0.32.0 to a release that resolves SA-level `imagePullSecrets`
   (verify the changelog first — behavior was still SA-blind as of 0.32.0).

## Definition of Done

- [x] Root cause identified (SA-level `imagePullSecrets` not resolved by operator 0.32.0).
- [x] Config levers ruled out and reverted.
- [x] Panel ② populated (352 series) + Prometheus-verified.
- [ ] Durable path chosen and implemented (options above) — **open**.
