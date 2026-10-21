# Dispatch spec: expired ACG observability ApplicationSet triage

Read-only diagnosis of the open P2 degraded `observability-acg` state. Correlate source ownership, Argo CD state, destination-cluster registration, and authoritative sandbox expiry evidence. Distinguish confirmed destruction from API/network unreachability; recommend a safe owner/remediation without implementing it.

Read-only kubectl get/describe, Argo CD status/read commands, and provider state queries are permitted. No sync, refresh annotation, delete, prune, apply, registration change, provisioning, or AWS mutation. If live evidence cannot safely be obtained, report that limitation.

Write findings only to `docs/issues/2026-10-21-acg-observability-appset-investigation.md`.

## Files

- `docs/issues/2026-10-21-acg-observability-appset-investigation.md`
