# Dispatch spec: Hostinger multi-service incident read-only triage

Investigate the unconfirmed fault domain for the recovered 2026-10-20 Hostinger multi-service outage. Reconcile existing evidence with current read-only health and available API/control-plane logs; distinguish M4-to-cluster API path failure from node/control-plane, ingress, data, Vault/ESO, and Argo CD login issues. Do not claim causality without evidence.

Only read-only probes, bounded kubectl get/describe/logs, Prometheus queries, and Argo CD status are permitted. No restart, reboot, unseal, sync, rollout, repair, provider action, configuration mutation, or secret access. If evidence is unavailable, record uncertainty.

Write findings only to `docs/issues/2026-10-21-hostinger-multi-service-incident-investigation.md`.

## Files

- `docs/issues/2026-10-21-hostinger-multi-service-incident-investigation.md`
