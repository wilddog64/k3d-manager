# P2: ArgoCD bootstrap manifests contain stale metadata and namespaces

**Date:** 2026-03-01
**Reported:** Claude during ArgoCD Phase 1 planning
**Status:** FIXED — manifests converted to templates with correct namespaces/org
**Severity:** P2
**Type:** Bug — manifests drifted from repo defaults, blocking cicd rollout

---

## What Happened

The ArgoCD AppProject and sample ApplicationSets were exported directly from a
cluster in late 2025. The YAMLs under `scripts/etc/argocd/{projects,applicationsets}`
still contained:

- Hardcoded `namespace: argocd` metadata (pre-v0.3.0 naming)
- Destination namespaces pointing to `vault`, `jenkins`, `directory`, etc.
- `your-org` placeholder GitHub URLs
- Kubernetes server metadata (`uid`, `resourceVersion`, `status`, etc.) that cannot
  be applied cleanly to a fresh cluster

Attempting to run `deploy_argocd_bootstrap` on v0.3.1 fails with namespace mismatches
and ArgoCD refuses to sync the ApplicationSets.

---

## Root Cause

The manifests were captured via `kubectl get ... -o yaml` and checked in verbatim.
No templating or namespace substitution occurred during bootstraps, so the files
never picked up the v0.3.0 namespace renames (`vault`→`secrets`, `jenkins`→`cicd`,
`directory`→`identity`).

---

## Fix

- Replaced `projects/platform.yaml` with `platform.yaml.tmpl`, a clean declarative
  manifest that references `${ARGOCD_NAMESPACE}` and v0.3.0 destinations.
- Stripped server metadata from `applicationsets/{platform-helm,services-git,demo-rollout}.yaml`.
- Updated metadata namespaces to `cicd` and corrected GitHub URLs to
  `https://github.com/wilddog64/k3d-manager`.

`_argocd_deploy_appproject` now renders the template via
`envsubst '$ARGOCD_NAMESPACE'` before applying it, ensuring the namespace can be
overridden at runtime.

---

## Verification

- `shellcheck scripts/plugins/argocd.sh`
- `PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/plugins/argocd.bats` (new suite
  covering help text, namespace defaults, CLUSTER_ROLE guard, and template errors)

Manual redeploy instructions: `./scripts/k3d-manager deploy_argocd --bootstrap` now
applies the cleaned manifests without namespace diffs.

---

## Impact

Without the fix, ArgoCD Phase 1 cannot land (wrong namespace + bad metadata) and
GitOps bootstrap repeatedly fails. The new templates keep the manifests aligned
with the repo defaults and safe for future namespace changes.
