# Bug: postgres-keycloak's 1 s `pg_isready` probes time out on the hub

**Status:** OPEN
**Priority:** P3 — warnings only so far (0 restarts in 8 days); a run of three liveness misses would restart Keycloak's only database replica and stall logins for about a minute.
**Severity:** low
**Release:** v1.43.6 (bug; exempt from the plan cap)
**Filed:** 2026-10-24, by Claude, during the frontend-login live check
**Approval:** pending — filed for triage; not dispatched.
**Component:** shopping-cart-infra `postgres-keycloak` Deployment (namespace `identity`, ArgoCD app `cicd/shopping-cart-identity`)
**Related:** `docs/bugs/2026-08-27-keycloak-restart-loop-tight-probes.md` (same disease, Keycloak itself), `docs/bugs/2026-10-09-frontend-login-callback-hangs-when-keycloak-db-restarts.md` (fix C changed this probe's command)

## Symptom

Read-only, hub context `k3d-k3d-cluster`, 2026-10-24 about 10:08 PDT. Events on pod
`postgres-keycloak-897bc7b6c-lvmn8` before its operator-run restart:

- 27 min earlier: `Liveness probe failed: command timed out: "sh -c pg_isready ..." timed out after 1s`
- 6 min earlier: `Readiness probe failed: ... timed out after 1s`

The pod showed 0 restarts, so no run of liveness misses reached `failureThreshold`.

## Root cause (probable)

`timeoutSeconds: 1` on an `exec` probe that forks `sh` and `pg_isready` on a CPU-contended hub
node. This is the same pattern as the Keycloak and Grafana probe kills. The 1 s budget covers the
exec round-trip through containerd as well as the Postgres check.

## Fix

- **F1.** In shopping-cart-infra, raise the liveness and readiness `timeoutSeconds` to 5, and set
  the liveness `failureThreshold` to at least 6. Add a `startupProbe` so a cold start isn't killed.
- **F2.** No change to the probe command. Fix C's `sh -c 'pg_isready -U "$POSTGRES_USER" ...'` stays.

## Acceptance

```yaml
must:
  - id: M1
    text: The postgres-keycloak liveness and readiness probes have timeoutSeconds >= 5, the liveness failureThreshold is >= 6, and a startupProbe exists.
must_not:
  - id: N1
    text: The probe command must not drop the -U "$POSTGRES_USER" form (red on a mutant that reverts to bare pg_isready, which logs role "root" errors).
  - id: N2
    text: The probes must not be removed (red on a manifest with no livenessProbe).
evidence:
  - id: E1
    kind: offline
    proves: [M1, N1, N2]
    text: A manifest test in shopping-cart-infra that parses the Deployment; N1 and N2 shown red on mutants.
  - id: E2
    kind: live
    proves: [M1]
    text: After ArgoCD syncs, Claude reads the live probe spec, and 24 h of identity events show no probe timeout on postgres-keycloak.
interface:
  - shopping-cart-infra postgres-keycloak Deployment manifest
```
