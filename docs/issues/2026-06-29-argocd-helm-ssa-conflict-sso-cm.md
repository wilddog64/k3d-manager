# ArgoCD helm upgrade SSA field conflict on argocd-cm / argocd-rbac-cm

**Found:** 2026-06-29, during live validation of the ArgoCD metrics
ServiceMonitor change (commit `60cd500c`). Helm v4.2.2.

## Symptom

`helm upgrade argocd argo/argo-cd -n cicd ...` fails:

```
UPGRADE FAILED: conflict occurred while applying object cicd/argocd-cm:
  conflicts with "kubectl-patch": .data.oidc.config, .data.url
conflict occurred while applying object cicd/argocd-rbac-cm:
  conflicts with "kubectl-client-side-apply": .data.policy.csv, .data.scopes
```

The upgrade is non-atomic: chart-templated objects (e.g. the metrics
Services/ServiceMonitors) still apply, but the release is marked `failed`.
`--take-ownership` does NOT clear the field-level conflict.

## Root cause

`bin/cluster-up` configures ArgoCD SSO out-of-band at Step 10f:
- `kubectl apply` of `argocd-cm.yaml` / `argocd-rbac-cm.yaml` from
  shopping-cart-infra -> field manager `kubectl-client-side-apply` owns
  `.data.policy.csv` / `.data.scopes`.
- `kubectl patch configmap argocd-cm --type merge` for the Cloudflare public
  `url` + `oidc.config` -> field manager `kubectl-patch` owns those fields.

Helm does not own those fields, so any later helm upgrade collides under
server-side apply.

## Why this is NOT a normal-flow bug

- `deploy_argocd` runs the helm install at cluster-up Step **3.6**, before the
  SSO config at Step **10f**, so metrics/chart values apply cleanly on a fresh
  hub.
- The refresh path calls `deploy_argocd_bootstrap`, which does not re-run helm.
- `deploy_argocd` hard-codes `release_exists=0` -> plain `helm upgrade --install`.

The conflict only fires on a *manual* `helm upgrade` / `deploy_argocd` against an
already-SSO-patched live release.

## Remediation

- Prefer redeploying from a fresh hub (helm install precedes SSO patches).
- If a release is already `failed`: `helm rollback argocd -n cicd`.
- Do NOT `--force` against a live release - it risks clobbering the live ArgoCD
  OIDC/RBAC config.
- Long-term option (not yet scoped): fold the SSO `argocd-cm`/`argocd-rbac-cm`
  config into the helm values so there is a single field-manager owner.
