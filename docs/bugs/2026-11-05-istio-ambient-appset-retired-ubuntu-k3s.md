# P2: istio-ambient ApplicationSet targets retired ubuntu-k3s

**Date:** 2026-11-05
**Status:** OPEN — live verification pending
**Priority:** P2
**Branch:** bug/2026-11-05-istio-ambient-retired-cluster (based on main)

## Observed
Argo CD ApplicationSet `cicd/istio-ambient` is Degraded, reporting 2 Errors and 1 Info. Screenshot last updated 2026-11-04 09:45:25 PST. Visible error: `application destination spec is invalid: there are no clusters with this name: ubuntu-k3s`.

## Repository evidence
- `scripts/etc/argocd/applicationsets/istio-ambient.yaml` uses `destination.name: ${APP_CLUSTER_NAME}` and names generated children with this variable.
- `scripts/plugins/istio_ambient.sh` silently defaults `APP_CLUSTER_NAME` to `ARGOCD_APP_CLUSTER_NAME` or `ubuntu-k3s`.
- `docs/issues/2026-08-13-stale-istio-ubuntu-k3s-applications.md` documents retired ubuntu-k3s applications and confirms `ubuntu-hostinger` was the intended active target.
- CHANGELOG documents a previous `deploy_argocd_applicationsets` fix to preserve live destinations and provider-specific CNI paths when re-pinning. Check whether a different reconciliation/rebuild path bypasses that fix.

## Hypothesis (not yet proven)
A reapply during hub migration/rebuild or another deployment path may have substituted the legacy default. Screenshot does not establish which operation triggered the change, or the second error.

## Investigation
1. Read full ApplicationSet status.conditions, generated child Applications, and registered Argo CD cluster names; do not expose secrets.
2. Check `ubuntu-hostinger` registration and Istio workloads before any mutation.
3. Trace hub migration/rebuild and `deploy_argocd_applicationsets` / `deploy_istio_ambient` activity around Nov 4 09:45 PST.
4. Compare with August 13 incident; determine whether this is a recurrence or a new failure mode.
5. Investigate the second ApplicationSet error independently.

## Acceptance criteria
- Fail closed when no valid target is selected; do not silently fall back to retired `ubuntu-k3s`.
- Reconciliation and one-command hub rebuild preserve intended registered cluster destination and provider-specific CNI configuration.
- Regression tests cover absent APP_CLUSTER_NAME, missing registration, hub migration, and existing destination preservation.
- Live verify ApplicationSet healthy, expected children and destination, Hostinger Istio healthy, no unintended pruning.
- Do not re-register retired clusters, force-delete finalizers, or prune applications without confirming intended lifecycle.

## Cloud-bridge live evidence — 2026-11-05 07:45–07:46 PST
Read-only requests filed on the orphan `cloud-requests` branch and acknowledged by the live hub bridge:
- `diagnose-appsets` job `cb0d79a0`: SUCCESS; `istio-ambient` exists among 13 ApplicationSets, age ~5d18h.
- `diagnose-app istiod-ubuntu-k3s` job `5fb6a393`: returned Kubernetes NotFound (that legacy child Application is absent).
- `diagnose-apps` job `5fd7977c`: SUCCESS; returned output tail includes multiple `ubuntu-hostinger-*` Applications `Synced Healthy`. This response is truncated to an output tail and **does not prove the absence of Istio children**.
- Operator suspects ACG sandbox up/down lifecycle leaves stale resources. Investigate ACG teardown and stale registration cleanup, but do not assume ACG owns the persistent Istio ApplicationSet or delete any Hostinger resources.

### Next check
Compare live `istio-ambient` ApplicationSet spec/template destination and all status conditions to the registered clusters and current ACG lifecycle state. The bridge's `diagnose-appsets` action only lists names/ages, so the exact live spec, second error, and causal operation remain unverified.

## Lifecycle wiring confirmed from current main Makefile
- `CLEANUP_STALE ?= 0`; the `down` target invokes `cleanup-stale-resources CONFIRM=1` **only** with `CLEANUP_STALE=1`.
- The `up` target has no `cleanup-stale-resources` invocation. Thus `make up` can run with prior stale Argo CD registrations unless another background reconciler handles them.
- Existing targets: `cleanup-stale-sandbox` (local state), `cleanup-stale-clusters` (expired managed registrations), `cleanup-stale-registration CLUSTER=...` (exact-name legacy/unmanaged), and `cleanup-stale-resources` (both guarded paths).
- A separate `install-sandbox-reaper` launchd target exists and periodically cleans eligible expired sandbox registrations, but its installation/live state has not been verified.
- `docs/bugs/2026-09-29-stale-unmanaged-argocd-registration.md` previously fixed the missing explicit exact-name cleanup pathway for `managed=false` registrations. The managed-only cleanup intentionally excludes these.

### Scope refinement
Test and document lifecycle-aware **preflight** on ACG up: read-only inventory and identification of stale prior sandbox registrations, then safe cleanup *only* after confirming exact sandbox identity and expiration/teardown, with operator approval for unmanaged registrations. Do not blindly call `cleanup-stale-resources CONFIRM=1` at startup. Validate that any fix also preserves the persistent `ubuntu-hostinger` Istio target and does not conflate ACG cleanup with `istio-ambient` destination overwrite.

## Operator reproduction hypothesis — 2026-11-05
The operator reports an earlier `make up` of an ACG sandbox, followed by natural sandbox expiration without running `make down` or manual cleanup. This can leave Argo CD state that requires lifecycle reconciliation. Treat this as a **likely event sequence, not verified root cause**.

Assess whether the sandbox reaper was installed/running and whether it skipped this cluster because `k3d-manager/managed=false`, missing expiration metadata, or another eligibility/health check. Distinguish:
1. expired sandbox registration and stale generated Applications;
2. the still-live `istio-ambient` ApplicationSet's `destination.name: ubuntu-k3s` (which may require a separate safe retarget after cleanup).

Acceptance addition: expiration without operator-initiated down must eventually converge to clean hub state, with observable/audited decisions, without touching persistent Hostinger Applications.
