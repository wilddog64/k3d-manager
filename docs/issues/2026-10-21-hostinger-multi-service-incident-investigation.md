# Hostinger multi-service incident — read-only follow-up

**Investigated:** 2026-10-21 22:57 UTC; targeted historical follow-up 2026-10-22

**Scope:** Read-only follow-up to [the 2026-10-20 incident](../bugs/2026-10-20-hostinger-multi-service-502-kubernetes-api-timeouts.md). No runtime changes were made.

**Result:** The current API path and workloads are healthy, and historical metrics confirm a time-bounded public frontend 502 while other sampled public endpoints remained available. Evidence still does not identify which segment caused the temporary M4-to-Hostinger API-path interruption. Keep the canonical incident OPEN.

## Current read-only checks

Commands below were run on 2026-10-21 around 22:56–22:57 UTC. Contexts available were `k3d-k3d-cluster` and `ubuntu-hostinger`.

| Check | Result |
|---|---|
| `kubectl --context ubuntu-hostinger --request-timeout=5s get --raw=/readyz` | `ok` |
| `kubectl --context ubuntu-hostinger --request-timeout=8s get nodes -o wide` | `srv1754834` is `Ready`, k3s `v1.36.5+k3s1`, Ubuntu 24.04.4, public IPv4 `2.25.146.252`. |
| Node conditions (`kubectl ... describe node srv1754834`) | `Ready=True`; MemoryPressure, DiskPressure, and PIDPressure are False; no node events. Lease renewed `2026-10-21 15:56:36 -0700`. |
| App pods (`shopping-cart-apps`) | Basket, frontend, order, and product-catalog pods all `1/1 Running`; order-service has two restarts, last 4d4h ago. |
| Data pods and StatefulSets (`shopping-cart-data`) | MinIO, three PostgreSQL StatefulSets, RabbitMQ, and both Redis StatefulSets are all `1/1` / `1/1 Ready`. Each pod's single restart was last 4d4h ago. |
| Public frontend, five sequential GETs | `200` for all five; elapsed times 0.217, 0.362, 0.335, 0.215, and 0.275 seconds. |
| `ClusterSecretStore/vault-backend` | `Ready=True`, reason `Valid`, message `store validated`, last transition `2026-10-20T21:31:40Z`. |
| ExternalSecrets (`kubectl ... get externalsecrets -A`, condition columns only) | All 19 listed ExternalSecrets report `Ready=True` / `SecretSynced`. No Secret objects or values were read. |
| Vault (`kubectl ... exec vault-0 -- vault status -format=json`) | `initialized=true`, `sealed=false`, Vault `1.20.1`, raft applied and committed indexes equal. This status command returned no credentials or Secret values. |
| Vault watchdog | `vault-unseal-watchdog-29877055` completed; it was created about 115 seconds before the events query. No conclusion about the watchdog's necessity during the incident is inferred. |
| Hostinger Argo CD Applications (queried from hub context, namespace `cicd`) | `ubuntu-hostinger-data-layer`, `ubuntu-hostinger-shopping-cart-namespace`, frontend, and other Hostinger applications were `Synced/Healthy`; reconciliation timestamps were 2026-10-21 22:54 UTC. This is fresh supporting status, not proof by itself of service health. |
| Public Argo CD `/api/v1/session` GET | HTTP 405. This establishes endpoint reachability only; GET is not the login method, and no direct password login was attempted. The earlier direct-login failure remains untriaged. |
| Host-side local Prometheus endpoint `127.0.0.1:19200/-/ready` | Connection refused. A read-only query was instead made inside the Hostinger Prometheus pod. |

## Time-correlated incident evidence

Queried the hub Prometheus pod using its read-only HTTP API:

```text
kubectl --context k3d-k3d-cluster -n monitoring exec prometheus-kube-prometheus-stack-prometheus-0 -- wget -qO- --post-data='query=probe_http_status_code%7Bjob%3D%22blackbox-public-ui%22%7D&start=1792530600&end=1792532400&step=60' http://127.0.0.1:9090/api/v1/query_range
```

The query returned a successful matrix. `probe_http_status_code` for `https://frontend.3ai-talk.org/` was `502` at every 60-second sample from `2026-10-20T21:10:00Z` through `21:36:00Z` (27 one-minute samples spanning 26 minutes), and `200` from `21:37:00Z` through `21:40:00Z`. In the same interval, Argo CD returned 200 throughout, Grafana 302 throughout, and Keycloak 302 throughout. This substantiates a prolonged frontend-origin/path failure relative to those independent public endpoints; the sampled endpoints do not prove all Hostinger services or its Kubernetes API were healthy.

The Hostinger Prometheus `node_boot_time_seconds` query returned value `1792260652`, which converts to `2026-10-17T18:10:52Z`, and a sample timestamp of `2026-10-21T22:57:05Z`. This matches the boot time already recorded in the incident investigation and predates the outage by over three days. The current node's Kubernetes age is 91 days. Together these observations weigh against a VM reboot during the 2026-10-20 incident; they do not replace Hostinger hypervisor audit history.

The incident's contemporaneous evidence remains the earlier M4 port-forward log (`dial tcp 2.25.146.252:6443: i/o timeout`, forwarding resumed around 21:26Z), approved Kubernetes diagnostic timeout waiting for API headers, and Hostinger journal's API-proxy WebSocket EOF/reset messages. The existing read-only SSH/journal review reported no reboot, OOM, link transition, conntrack, or disk/I/O errors in the incident window. This new query aligns the public frontend recovery around 21:37Z but cannot distinguish a transient network route/firewall/path issue from a short-lived API-service or control-plane issue that affected M4 access.

## Historical regression comparison

- **2026-10-17 Hostinger poweroff:** The separate node issue records Hostinger support attributing that earlier shutdown to emergency security-patch maintenance. Current boot telemetry agrees with its 2026-10-17 18:10:52Z boot time and provides no evidence of a second restart on Oct 20. The prior hypervisor event is not evidence that this incident had the same cause.
- **Vault unseal watchdog:** The earlier watchdog defect is recorded as fixed and LIVE-VERIFIED on Oct 18. Current Vault reports unsealed, the store is Ready, all observed ExternalSecrets are Ready, and a recent watchdog Job completed. Those current checks do not show a Vault/ESO failure during the earlier API-path window. No evidence establishes a recurrence or identifies Vault as the trigger.
- **CNI/IPAM exhaustion:** The prior leaked-reservation issue is recorded as fixed and LIVE-VERIFIED. Current app and data pods are scheduled and Ready, and the watchdog can create and complete Jobs. No current pod scheduling failure or other evidence of IPAM exhaustion was observed. The node's CNI reservation state was not inspected, so this is not a direct audit of the sweep or a historical exclusion of IPAM behavior.

## Assessment and limits

**Supported:** the public frontend returned 502 for 27 one-minute samples spanning 26 minutes, while three other public endpoints stayed reachable; the M4's port-forward/API path timed out during the incident; the current Hostinger API is reachable and ready; and current app, data, Vault, ESO, and `vault-backend` checks are healthy. Current and historical boot evidence does not support an Oct 20 reboot. Current observations do not show a Vault/ESO or CNI/IPAM recurrence.

**Unresolved:** the exact network/control-plane segment that interrupted TCP/6443 access; Hostinger provider-side event/audit records for that interval; current and historical direct Argo CD password-login behavior; and the original 35-count ESO `UpdateFailed` event's exact timestamps and transition history. The event's prior first-seen time was approximately three days before the incident, so it cannot be assumed to have started with this outage. No M4 port-forward process state or incident-window Hostinger-local API probe was available in this read-only session.

No causality is assigned. No host restart, pod restart, Argo CD sync, Vault unseal, rollout, provider action, configuration mutation, or Secret access was performed. The five public frontend successes and current `/readyz` establish recovery at this observation time; the historical record's fresh API/data checks add evidence for recovery on Oct 20. This investigation does not establish a prevention test or alert that would identify the failed path. Keep the canonical bug OPEN pending attribution of the API-path failure and separate triage of direct password login.

## Targeted historical follow-up — 2026-10-22

This follow-up reviewed the retained `cloud-requests` branch records and their request/response timestamps, the incident bug timeline above, and the available repository diagnostics. It did not repeat current health probes.

### Provider, API-proxy, and tunnel evidence

The accessible `cloud-requests` branch contains 312 tree entries. Its incident-window material includes the queued/completed diagnostic request and public probe responses, but no Hostinger provider audit/event export, raw M4 tunnel or port-forward log, or raw k3s API-proxy journal. The existing incident record is therefore the only available representation of the M4 port-forward timeouts and the SSH journal review: TCP/6443 dial timeouts from about 21:09–21:26Z; API-proxy WebSocket EOF/reset messages; and no matching reboot, OOM, link transition, conntrack, or disk/I/O errors. The underlying logs and provider records were not available in the examined evidence set for independent timestamp or message-level review.

The retained probes establish this sequence (UTC; PDT is UTC−7 on this date):

| UTC | PDT | Evidence |
|---|---|---|
| 21:00:08 | 14:00:08 | `hostinger-status` job `5a80b6ca` completed: 20 checks passed and one failed. Frontend, Pushgateway, product images, data layer (4/4), ESO, and SSO checks passed; direct Argo CD login was `HTTP unavailable`. |
| 21:09–21:26 | 14:09–14:26 | Existing M4 forwarding record reports TCP/6443 timeouts, followed by forwarding resumption at about 21:26Z. |
| 21:10–21:36 | 14:10–14:36 | Hub Prometheus public probe history sampled frontend HTTP 502 each minute; Argo CD, Grafana, and Keycloak probes stayed reachable. Frontend samples returned to HTTP 200 at 21:37Z. |
| 21:21:54 | 14:21:54 | Public probe job `98ec31a9` completed with frontend 0/5 (all 502); six other public endpoints passed their five samples. |
| 21:22:37 | 14:22:37 | Approved Hostinger pod diagnostic returned a Kubernetes API timeout waiting for response headers. Its wrapper said `success`, but the diagnostic output itself records the timeout. |
| 23:08:18 | 16:08:18 | Hostinger status job `8a78c34d` completed: frontend and product images returned 502, Pushgateway refused connections, Hostinger ESO checks timed out, and two data-layer components were not ready. Argo CD direct login remained unavailable while SSO passed. |
| 23:11:57 | 16:11:57 | Fresh Hostinger status job `dc9e4089` completed with frontend, Pushgateway, product images, all four data-layer checks, ESO and SSO passing. Direct Argo CD login remained `HTTP unavailable`. |

The 21:00Z status is an earlier healthy sample, not evidence that the API stayed healthy through the later timeouts. Together, the timed TCP/6443 errors and API-header timeout establish loss of the M4-to-API access path during the degradation; the frontend and ancillary Hostinger checks recovered later. They do not discriminate between an M4-side route/tunnel interruption, a Hostinger network/API-proxy issue, or a short-lived control-plane/API event. The summarized journal findings weigh against a VM reboot or the listed kernel/node failures, but absent raw logs and provider audit records, they do not exclude other node or control-plane causes. The sampled independent public endpoints and prior all-service checks also do not by themselves prove the shared tunnel or every Hostinger service was healthy.

### Argo CD direct-password login, assessed separately

The direct-password failure is not time-bounded to the frontend/API incident: it appears in job `5a80b6ca` completed at 21:00:08Z (before the documented 21:09Z first port-forward timeout), during the incident in job `8a78c34d`, and after recovery in job `dc9e4089` at 23:11:57Z. SSO succeeded in these status runs, and the public Argo CD endpoint answered HTTP 200 in the status checks. This separates the direct-login symptom from the frontend/API-path outage and demonstrates that the password-login check continued failing after the other observed services recovered.

The status implementation posts the admin password from `Vault argocd/admin` to `/api/v1/session`; it reports `HTTP unavailable` when that request raises an exception. The recorded output therefore does not reveal whether the failure was a connection/TLS/timeout problem or another exception, and it does not establish whether Argo CD rejected the password. No password, Secret value, or authenticated POST was read or replayed during this follow-up. The existing read-only `GET /api/v1/session` result of HTTP 405 establishes route reachability for GET only. The cause of the direct-password failure remains unknown and should be tracked separately from the incident's unassigned API-path fault domain.

### Evidence availability and conclusion

Evidence examined includes the [public probe result](https://raw.githubusercontent.com/wilddog64/k3d-manager/cloud-requests/responses/20261020T212043Z-make-status-public.final.json), [Hostinger diagnostic result](https://raw.githubusercontent.com/wilddog64/k3d-manager/cloud-requests/responses/20261020T212245Z-job-status-frontend-pods.json), [21:00Z Hostinger status result](https://raw.githubusercontent.com/wilddog64/k3d-manager/cloud-requests/responses/20261020T205950Z-job-status-hostinger.json), [incident-window Hostinger status result](https://raw.githubusercontent.com/wilddog64/k3d-manager/cloud-requests/responses/20261020T230736Z-job-status.json), and [post-recovery Hostinger status result](https://raw.githubusercontent.com/wilddog64/k3d-manager/cloud-requests/responses/20261020T231148Z-job-status.json). The earlier report provides the Prometheus query and summarized SSH/journal findings; the retained evidence set has no corresponding raw API-proxy/tunnel logs or provider audit records.

No validated primary fault domain can be assigned from the available evidence. The best-supported boundary is an interruption affecting M4 access to Hostinger Kubernetes API at the same time as frontend and other Hostinger checks degraded, with spontaneous recovery. Whether it began in the M4 path, provider/network path, API proxy, or control plane remains unresolved. Argo CD direct-password login is a separate persistent symptom with SSO working; its failure mode cannot be narrowed further without a safe diagnostic that preserves credential secrecy. No provider API, authentication attempt, runtime probe, or configuration change was made in this follow-up.
