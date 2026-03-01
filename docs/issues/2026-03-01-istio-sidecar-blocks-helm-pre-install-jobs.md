# P2: Istio sidecar injection blocks Helm pre-install Job completion

**Date:** 2026-03-01
**Reported:** Claude during ArgoCD live deploy (v0.5.0)
**Status:** PARTIALLY FIXED — Keycloak template disables injection; ArgoCD still needs manual workaround
**Severity:** P2
**Type:** Operational — Helm install hangs indefinitely without manual intervention

---

## What Happened

Running `deploy_argocd --enable-ldap --enable-vault --bootstrap` against the infra
cluster caused the Helm install to hang at `pending-install`. The deploy script timed
out waiting for ArgoCD pods that never started because the pre-install hook job
`argocd-redis-secret-init` never completed.

```
NAME      NAMESPACE  REVISION  STATUS           CHART          APP VERSION
argocd    cicd       1         pending-install  argo-cd-9.4.5  v3.3.2
```

---

## Root Cause

Istio injects a sidecar (`istio-proxy`) into every pod in namespaces with the
`istio-injection: enabled` label — including Kubernetes Job pods. When the Job's
main container (`secret-init`) finishes successfully (exit code 0), the Istio
sidecar keeps running. Kubernetes cannot mark the Job as `Complete` while any
container is still alive, so:

1. `argocd-redis-secret-init` Job → never `Complete`
2. Helm pre-install hook → never acknowledged
3. `helm upgrade --install` → stuck at `pending-install` forever

The `secret-init` container itself completed cleanly — the Vault SecretStore
validated, the Redis secret was confirmed present. The issue was entirely the
Istio sidecar lifecycle.

```
# Container states at time of diagnosis:
secret-init:   Terminated  exit=0  ← done, clean
istio-init:    Terminated  exit=0  ← done, clean
istio-proxy:   Running            ← BLOCKING job completion
```

---

## Workaround (applied 2026-03-01)

Signal the Istio proxy to exit via its admin API:

```bash
kubectl -n cicd exec argocd-redis-secret-init-<pod-id> -c istio-proxy \
  -- pilot-agent request POST 'quitquitquit'
```

This causes the sidecar to exit cleanly (exit code 0), the Job reaches `Complete`,
and the Helm install proceeds normally. ArgoCD was fully deployed after this step.

**Time to detect and resolve:** ~5 minutes.

---

## Proper Fix

### Option A — Disable sidecar injection on specific Jobs (recommended)

Add `sidecar.istio.io/inject: "false"` to the Job pod via Helm values.

**ArgoCD chart** (no clean upstream knob — workaround required unless patching chart):
The `argocd-redis-secret-init` job template is not directly configurable via values.
Continue to use the `quitquitquit` workaround for ArgoCD re-deploys, or exclude the
`cicd` namespace from Istio injection (too broad — affects Jenkins sidecars too).

**Keycloak chart (Bitnami)** — the `keycloak-config-cli` job IS configurable.
`scripts/etc/keycloak/values.yaml.tmpl` now ships with
`keycloakConfigCli.podAnnotations.sidecar.istio.io/inject: "false"`, preventing
the job from hanging during `deploy_keycloak`.

### Option B — Istio mesh-wide Job sidecar exit (Istio 1.12+)

Configure Istio to automatically exit the sidecar when the application container
exits with code 0. Add to the Istio installation values:

```yaml
meshConfig:
  defaultConfig:
    proxyMetadata:
      EXIT_ON_ZERO_ACTIVE_CONNECTIONS: "true"
```

This is a global fix — all Job sidecars exit cleanly when their main container
finishes. No per-chart annotation needed.

---

## Impact on Current and Future Deployments

| Deployment | Risk | Mitigation |
|---|---|---|
| `deploy_argocd` (re-deploy) | Will hang again on `argocd-redis-secret-init` | Use `quitquitquit` workaround |
| `deploy_keycloak` (Bitnami) | `keycloak-config-cli` job will hang | Add `sidecar.istio.io/inject: "false"` to values template |
| Any future Helm chart with pre/post hooks | Same issue if Istio injected | Add annotation or use Option B |

---

## Is This a Blocker?

**No** — ArgoCD is fully deployed and healthy. All 7 pods `2/2 Running`, all
ExternalSecrets `SecretSynced`.

However, `deploy_keycloak` **will hit the same issue** via the `keycloak-config-cli`
job unless `sidecar.istio.io/inject: "false"` is added to the Bitnami values
template before Codex commits. This should be included in the Keycloak plugin
implementation (Part B, v0.5.0).

---

## References

- Istio issue: https://github.com/istio/istio/issues/11045
- Bitnami Keycloak values: `keycloakConfigCli.podAnnotations`
- Workaround command: `pilot-agent request POST 'quitquitquit'`
