# Hub Kine history saturation and Hostinger cosign role drift

**Filed:** 2026-09-09
**Area:** hub k3s datastore, ArgoCD stale-cluster registration, Vault/ESO signing recovery
**Status:** mitigated; durable Kine-retention/rebuild work remains

## What happened

`make status CLUSTER_PROVIDER=k3s-hostinger` initially returned:

```text
Overall: UNKNOWN
  ! status source: webhook unavailable
  ! hub agent-0: Up 2 minutes
  hint: make restart-webhook
make: *** [status] Error 2
```

The webhook process and its `127.0.0.1:7443` listener were healthy. Its health
handler exceeded the caller budget while hub Kubernetes API calls were blocked.
The hub API reported failed `etcd`/`etcd-readiness` checks, K3s logs showed slow
Kine SQL, API handler timeouts, and failed lease updates.

Offline inspection of a stopped, rollback-backed datastore found:

```text
state.db      8.3G
state.db-wal  537M
page_count    2152311
freelist      0
kine rows     1013597
```

`PRAGMA integrity_check` succeeded. `VACUUM INTO` produced another 8.3G file,
proving this is retained Kine history rather than reclaimable SQLite free pages.
The compacted copy was not promoted; the original hub database was restarted
unchanged.

ArgoCD additionally retained a stale `cluster-ubuntu-k3s` registration pointing
at `https://host.k3d.internal:6443`. Its ACG applications were `Unknown`, causing
reconciliation pressure after that sandbox became unavailable.

## Immediate mitigation and verification

- Paused heavy hub observability workloads; Grafana stayed available.
- Removed only ArgoCD's registration label from the stale ACG cluster Secret;
  Secret data was retained.
- Temporarily scaled `argocd-application-controller` to zero to stop the retry
  storm. It remains paused pending a deliberate stale-Application cleanup and
  durable retention fix.
- Restarted the hub after the offline verification. `/readyz` returned `ok`.
- Repaired the remaining Hostinger ESO failure: `kyverno/cosign-public-key` was
  denied on `secret/data/cosign/signing` because the Hostinger auth role did not
  grant `cosign-verify`.

The post-repair status result was:

```text
  ✓ ArgoCD: HTTP 200
  ✓ Frontend: HTTP 200
  ✓ Keycloak: HTTP 200
  ! Prometheus: monitoring paused (make monitoring-resume)
  ✓ Grafana: HTTP 200
  ✓ Product images: 20/20 have image_url
  ✓ ESO ClusterSecretStore: Ready=True
  ✓ ESO ExternalSecrets: 20/20 synced
  ✓ Data layer: 4/4 ready
  ! Keycloak login: no credentials (k3dm-smoke-user Secret absent; set K3DM_SMOKE_KC_USER/PASS)
  ! Frontend login: skipped (no Keycloak token)
  ✓ ArgoCD login: HTTP 200
  ! Grafana login: monitoring paused (make monitoring-resume)
Overall: WARN (4 warnings)
```

## Root cause and code fix

`_signing_grant_eso_read` hard-coded `auth/kubernetes`. Hub ESO uses that mount,
but Hostinger ESO uses `auth/kubernetes-ubuntu-hostinger` and role
`eso-app-cluster`; its policy grant therefore never reached the role making the
failed request. `SIGNING_ESO_AUTH_MOUNT` now defaults to `kubernetes` for
backward compatibility and allows a provider-specific mount. BATS covers the
Hostinger-mount read/write path.

## Follow-up

1. Design a supported K3s/Kine retention or hub rebuild procedure; do **not**
   manually delete Kine rows, because they implement Kubernetes revision/watch
   semantics.
2. Remove stale ACG `Application` objects and their generating configuration
   before resuming `argocd-application-controller`; otherwise its retry storm can
   return.
3. Resume hub monitoring only after the datastore load is stable, then provision
   the optional Keycloak smoke credentials if a warning-free status is required.
