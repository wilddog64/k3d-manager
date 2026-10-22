# Dispatch spec: Hostinger multi-service incident read-only triage

## Targeted follow-up (2026-10-22)

The previous report established recovery and current read-only health but did
not identify the incident's fault domain. Focus on remaining questions rather
than repeating healthy-state checks:

- Look for available historical Hostinger provider/audit records and
  incident-window control-plane/API-proxy and tunnel evidence that can
  distinguish provider/network-path interruption from a short-lived API or
  control-plane event.
- Separately determine whether safe existing evidence resolves the Argo CD
  direct-password-login failure. Do not conflate it with the frontend/API
  incident; if unrelated or still unknown, report it separately.
- Reconcile source timestamps. If records or authorized access are
  unavailable, say so explicitly and leave causality unassigned.
- Avoid repeating current health probes already recorded unless a bounded
  read is needed to interpret historical evidence.

Investigate the unconfirmed fault domain for the recovered 2026-10-20 Hostinger multi-service outage. Reconcile existing evidence with current read-only health and available API/control-plane logs; distinguish M4-to-cluster API path failure from node/control-plane, ingress, data, Vault/ESO, and Argo CD login issues. Do not claim causality without evidence.

Only read-only probes, bounded kubectl get/describe/logs, Prometheus queries, and Argo CD status are permitted. No restart, reboot, unseal, sync, rollout, repair, provider action, configuration mutation, or secret access. If evidence is unavailable, record uncertainty.

Write findings only to `docs/issues/2026-10-21-hostinger-multi-service-incident-investigation.md`.

## Files

- `docs/issues/2026-10-21-hostinger-multi-service-incident-investigation.md`
