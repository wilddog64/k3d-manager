# P1: Hostinger multi-service outage — frontend 502, Kubernetes API timeouts, data-layer and ESO degradation

**Filed:** 2026-10-20 (operator-approved live incident triage)
**Branch:** `k3d-manager-v1.43.5`
**Release:** v1.43.5 (bug; no new plan slot)
**Status:** OPEN — incident recovered at last check; root cause unconfirmed; ArgoCD direct-login endpoint remains unavailable
**Priority:** P1 — public frontend unavailable and multiple critical application/data services degraded
**Severity:** high
**Approval:** operator, 2026-10-20 ~14:29 PDT: "go ahead to file P1 bug"
**Component:** `k3s-hostinger` node/control plane, public frontend ingress/port-forward, shopping-cart data layer, Vault/ESO; precise fault domain TBD
**Affected:** `ubuntu-hostinger`, `https://frontend.3ai-talk.org/`, `shopping-cart-apps`, `shopping-cart-data`, Hostinger `ClusterSecretStore/vault-backend`
**Related:**
- `docs/bugs/2026-10-17-hostinger-node-unresponsive-then-rebooted.md` (earlier 25-minute hypervisor-initiated Hostinger shutdown; **not proven to recur**)
- `docs/bugs/2026-10-17-hostinger-vault-sealed-after-reboot-no-unseal-watchdog.md` (prior sealed-Vault defect fixed and LIVE-VERIFIED Oct 18; **do not assume same root cause**)
- `docs/bugs/2026-10-17-hostinger-pod-ip-pool-exhausted-leaked-cni-reservations.md` (previous CNI IPAM exhaustion and remediation)
- `docs/issues/2026-09-02-hub-control-plane-saturation-causing-public-502.md` (distinct historical fault domain)

## Operator impact / incident summary

At about 14:18 PDT on 2026-10-20, the operator received the critical `PublicEndpointDown` notification: `https://frontend.3ai-talk.org/` failed the hub blackbox probe for five minutes, last HTTP status **502**. While the operator was away from the M4, ChatGPT used the existing **read-only cloud-bridge `cloud-requests`** transport to trigger allowed probes and diagnostics. No runtime changes were requested or performed. Later checks show the public frontend and core Hostinger workloads recovered without intervention; the original fault domain is still unconfirmed, and a separate ArgoCD direct-login endpoint failure persists.

The scope expanded from one failing frontend to a Hostinger app-cluster incident: Kubernetes API requests timed out, several data components were not ready, Hostinger Pushgateway refused connections, and app-cluster ExternalSecrets showed degraded state. An ArgoCD global view initially showed 30 Healthy/Synced apps, but two *Hostinger-specific* Application tiles subsequently showed **Degraded/Synced**, illustrating that global/cached status and application-specific health differ.

## Evidence and timeline (2026-10-20, UTC)

| UTC (approx.) | Source | Observation |
|---|---|---|
| 21:18:24 | Alertmanager warning email / critical SMS | `PublicEndpointDown`, `instance=https://frontend.3ai-talk.org/`, `job=blackbox-public-ui`, last status HTTP **502** for 5 min. |
| 21:21:24 | Bridge request `20261020T212043Z-make-status-public` | `make-status-public` queued as webhook job `98ec31a9`. |
| 21:21:54 | Bridge final job result | Five samples: frontend **0/5**, status `[502,502,502,502,502]`. Other endpoints (ArgoCD, Keycloak, Prometheus, Alertmanager, Grafana, webhook) **5/5** each. Verdict `SINGLE-SERVICE` at probe time; this is *not* proof that the Hostinger Kubernetes API or data plane is healthy. |
| 21:21–21:23 | Cloud pod diagnostic | Initial `namespace=frontend` request rejected (not approved namespace). Corrected to `provider=hostinger, namespace=shopping-cart-apps`: queued job `88461022`. Returned `Unable to connect to the server: net/http: request canceled while waiting for connection (Client.Timeout exceeded while awaiting headers)`. Webhook job reported `success` despite underlying kubectl failure text — a **diagnostic success-classification gap**, investigate separately. |
| ~21:23 | Operator Slack `hostinger-status` screenshot | Cluster status **FAIL (13 OK / 0 warn / 8 fail)**; frontend 502, product images 502, Pushgateway connection refused, ClusterSecretStore kubectl timed out, ExternalSecrets kubectl timed out, data layer **4 not ready** (including `postgres-orders` and `postgresql-payment`), ArgoCD password login HTTP unavailable. Public ArgoCD/Keycloak/Grafana/Prometheus remained reachable through their exposed endpoints. |
| ~21:25–21:26 | Operator ArgoCD screenshots | `ubuntu-hostinger-data-layer` and `ubuntu-hostinger-shopping-cart-namespace` both **Degraded / Synced**, destination `ubuntu-hostinger`. Last Sync Oct 18 is **not** last successful health refresh. Aggregate UI had previously displayed 30 Healthy/Synced; compare freshness and scope before interpreting. |
| ~21:27 | Operator ArgoCD resource/event screenshot | Multiple data-layer ExternalSecrets appear Degraded/Synced. One `UpdateFailed` message: `error processing spec.data[0] (key: secret/data/redis/orders-cache), err: ClusterSecretStore "vault-backend" is not ready`. Event counter **35**, first occurrence around **3 days ago**; this may predate today's public outage. |

## Investigation findings — 2026-10-20 (read-only)

| UTC (approx.) | Source | Observation |
|---|---|---|
| 21:09–21:26 | M4 frontend port-forward log | Repeated `dial tcp 2.25.146.252:6443: i/o timeout` errors; forwarding resumed at about 21:26 UTC (`Forwarding from 127.0.0.2:80 -> 8080`). Pushgateway port-forward logged retries/timeouts around 21:23–21:25 UTC, then resumed. The log contained 105 Kubernetes API timeout matches. |
| 21:00–21:40 | Hostinger SSH / system journal | VPS boot time was `2026-10-17 18:10:52` and k3s was active, ruling out a reboot during this incident window. Kernel journal search found no OOM, link transition, conntrack, or disk/I/O error matches. k3s logged WebSocket EOF and connection-reset errors on API proxy connections; these support an interrupted API path but do not identify which network segment caused it. |
| 23:02–23:09 | Read-only Kubernetes checks | `/readyz` returned `ok`; the single node was Ready; shopping-cart app pods and all seven data StatefulSets were ready; Vault pod was Running and `ClusterSecretStore/vault-backend` was `Ready=True`. No ExternalSecret with a non-Ready condition was returned. |
| 23:07–23:09 | Public and local endpoint probes | Five public frontend requests returned HTTP 200; a fresh frontend request and `/api/products` also returned HTTP 200. Local frontend and Pushgateway port-forward probes returned HTTP 200. |
| 23:11:57 | Fresh cloud-bridge `hostinger-status` job `dc9e4089` | 20 OK / 0 warn / 1 fail. ArgoCD, frontend, Keycloak, Grafana, Pushgateway, products, ESO, all four data-layer checks, and authenticated app flows passed. Prometheus returned expected HTTP 401 without auth. The sole failure was ArgoCD direct password login (`HTTP unavailable`); ArgoCD SSO login passed. Job wrapper returned `status=success` / `result_classification=passed`, which indicates the diagnostic completed, not that every probe passed. |
| 2026-10-20, operator screenshot (time not embedded) | `make status CLUSTER_PROVIDER=k3s-hostinger` | ArgoCD, frontend, Keycloak, Grafana, and Pushgateway returned HTTP 200; Prometheus returned expected HTTP 401; overall `HEALTHY`. Hub snapshot `20261009T170742Z` was reported 270 old, a stale snapshot separate from live endpoint health. |

**Assessment:** The best-supported explanation is a transient interruption of the M4-to-Hostinger Kubernetes API reachability used by the frontend and Pushgateway port-forwards. It matches the API timeouts, frontend 502s, Pushgateway refusal, subsequent forwarding recovery, and healthy current workloads. Evidence does **not** establish whether the interruption originated in Hostinger networking/API service or on the M4-side path. No evidence found for a Hostinger reboot, OOM, disk fault, or current database/Vault/ESO degradation. The remaining ArgoCD direct-login failure needs separate diagnosis; SSO works, and it was not the original public frontend 502.

No restart, sync, deletion, or other runtime remediation was performed. Keep this incident OPEN until the API-path cause is established and the ArgoCD direct-login failure is triaged or split into its own issue. Do not mark it VERIFIED or LIVE-VERIFIED based only on self-recovery.

**Evidence retained in GitHub cloud-requests branch:**

- [Public probe final response](https://github.com/wilddog64/k3d-manager/blob/cloud-requests/responses/20261020T212043Z-make-status-public.final.json) — five consecutive frontend 502s vs six healthy public endpoints.
- [Hostinger pod diagnostic result](https://github.com/wilddog64/k3d-manager/blob/cloud-requests/responses/20261020T212245Z-job-status-frontend-pods.json) — Kubernetes API timeout.
- [Hostinger-status initial request](https://github.com/wilddog64/k3d-manager/blob/cloud-requests/responses/20261020T212043Z-hostinger-status.json) — queued job `8a78c34d`; read its terminal response when available.
- [Hostinger-status recheck](https://github.com/wilddog64/k3d-manager/blob/cloud-requests/responses/20261020T212310Z-job-status-hostinger-recheck.json) — still running at last check.

## Known facts vs hypotheses

**Established at incident time:**

- Critical frontend blackbox 502 is real and reproducible across five fresh samples.
- Several Hostinger *application/data health checks* fail together; this is not solely an nginx symptom.
- An approved Kubernetes pod diagnostic timed out waiting for API headers during the incident.
- At least one data-layer ExternalSecret reports `vault-backend` not ready, and Hostinger ArgoCD apps are Degraded while Synced.

**Established at the last read-only check:**

- Public frontend and `/api/products` returned HTTP 200; frontend and Pushgateway local port-forwards responded HTTP 200.
- Hostinger API `/readyz` returned `ok`; node and app/data workloads were Ready; Vault and `vault-backend` were Ready.
- Fresh status had one remaining failure: ArgoCD direct password login unavailable; ArgoCD SSO login succeeded.

**Not established:**

- What happened inside the initial short-lived API/Kubernetes diagnostic timeout window; later node uptime establishes that the VPS did not reboot during the incident.
- Whether k3s API server is down, saturated, blocked by networking, or inaccessible only from M4's kubeconfig/tunnel.
- Whether Vault `secrets/vault-0` is *currently sealed*, or whether ESO `vault-backend` is degraded because of API/Vault network/auth errors; do **not** label this as a proven recurrence of the 2026-10-17 Vault watchdog bug.
- Whether previous Hostinger hypervisor poweroff, flannel/CNI IP exhaustion, exhausted disk, or resource pressure caused the present incident.
- Whether ESO's `UpdateFailed` event originated today; UI indicates first occurrence about 3 days earlier.
- Which network/API segment caused the transient TCP/6443 reachability loss, and why ArgoCD direct password login was unavailable in the fresh status job.

## Investigation plan (read-only evidence first)

1. **Establish node/control-plane availability:** On the operator's machine or approved Hostinger management interface, check VPS state/uptime, recent reboot/maintenance history, ping/SSH/TCP reachability, `kubectl --context ubuntu-hostinger --request-timeout=5s get --raw=/readyz`, and k3s/kubelet status. Do not bypass SSH host-key validation.
2. **Differentiate M4 access-layer vs Hostinger outage:** Correlate a direct, authorized Hostinger-local API probe with the failing M4 `kubectl` access path and the live app/public checks. Examine tunnel/port-forward logs read-only. All other public endpoints remaining healthy makes global Cloudflare failure less likely, not impossible.
3. **Check node health and workload scope:** Current boot timestamp, k3s and kernel journals, CPU/memory/swap/disk pressure, node Ready status, recent pod restarts, `shopping-cart-data` StatefulSets, and shopping-cart app pods. Do not conclude OOM/reboot without evidence.
4. **Check Vault and ESO chain after restoring API reachability:** `secrets/vault-0` readiness/sealed state, last `vault-unseal-watchdog` Job (installed fix from Oct 18), `ClusterSecretStore/vault-backend` conditions and observed generation, ESO events' precise timestamps. Do not expose Secret values, tokens, Vault unseal shards, or sensitive logs.
5. **Correlate timeline:** Match 502 start/recovery with `node_boot_time_seconds`, probe history, Prometheus scrape gaps, frontend proxy and nginx logs, pod readiness, and ESO condition transition times. An older ESO warning may be a *separate persistent defect*, not the trigger of today's outage.
6. **Recover only with operator approval:** After confirming fault domain, propose the smallest safe action and verify 5/5 public probes, Hostinger API `/readyz`, databases, Vault/ESO, and frontend path. Never blindly SYNC/DELETE ArgoCD apps, restart databases, reinitialize Vault, unseal using exposed credentials, or wipe data.

## Acceptance

```yaml
must:
  - id: M1
    text: Identify the validated primary fault domain and record time-correlated evidence for Hostinger VM, Kubernetes API, network access, and frontend origin.
  - id: M2
    text: Restore and verify https://frontend.3ai-talk.org/ successful public probes and accessible Hostinger Kubernetes API.
  - id: M3
    text: Verify shopping-cart data workloads, Vault state, ClusterSecretStore/vault-backend and dependent ExternalSecrets recover, or split independently persistent failures into tracked follow-ups.
  - id: M4
    text: Compare this incident with 2026-10-17 VPS poweroff, Vault unseal watchdog and CNI IPAM fixes without falsely attributing a regression.
  - id: M5
    text: Record the incident timeline, exact live checks, verified resolution and prevention test/alert evidence; only set LIVE-VERIFIED after actual recovery observations.
must_not:
  - id: N1
    text: No destructive remediation, forced ArgoCD sync/delete, Vault initialization, credential publication, or host restart without approved, evidence-based recovery plan.
  - id: N2
    text: Do not claim that sealed Vault, hypervisor poweroff, or IPAM exhaustion was the root cause until independently demonstrated.
  - id: N3
    text: Do not count cached ArgoCD Synced/Healthy or unrelated healthy hub public endpoints as proof of Hostinger recovery.
evidence:
  - id: E1
    kind: live
    proves: [M1, M4, N2, N3]
    text: Time-aligned node/API, gateway/tunnel, pod, Vault and ESO read-only evidence, with source and timestamps.
  - id: E2
    kind: live
    proves: [M2, M3, M5, N1, N3]
    text: Hostinger API ready, data-layer recovered, ClusterSecretStore and ExternalSecrets conditions checked, public frontend >=3/5 passing and no critical blackbox alert; record evidence and operator approval for any recovery step.
  - id: E3
    kind: offline
    proves: [M4, M5]
    text: If a software regression is found, focused regression tests and negative/mutation checks prevent recurrence.
interface:
  - scripts/etc/prometheus/rules*/**/*
  - docs/bugs/2026-10-20-hostinger-multi-service-502-kubernetes-api-timeouts.md
```

## Definition of Done

- [ ] Root cause established from evidence; avoid a guessed fix.
- [ ] Frontend and Hostinger API availability independently live-verified.
- [ ] Databases, Vault/ESO and dependent ExternalSecrets evaluated and repaired if necessary.
- [ ] Historical related fixes checked for genuine regression or ruled out.
- [ ] If remediation code is needed, implement/verify on the release branch with tests and operator-approved live recovery evidence.

## What NOT to Do

- Do not open a PR simply to file this incident.
- Do not commit this documentation to `main`; use `k3d-manager-v1.43.5`.
- Do not classify an unresponsive diagnostic as a healthy cluster merely because the webhook job status was `success`.
- Do not change live infrastructure in the course of filing this bug.
