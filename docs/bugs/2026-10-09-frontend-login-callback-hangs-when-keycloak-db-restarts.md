# Frontend login hangs on "Completing login..." when Keycloak's Postgres restarts

**Filed:** 2026-10-09, Claude (operator saw the spinner on `frontend.3ai-talk.org`)
**Branch:** k3d-manager-v1.42.0 (bug docs are exempt from the 5-plan cap)
**Status:** OPEN — filed; not specified
**Priority:** P2 — login recovers on its own once the DB is back, but the page never tells the user
**Severity:** Medium
**Component:**
- `shopping-cart-frontend`: `src/pages/LoginCallback.tsx`
- `shopping-cart-infra`: `identity/keycloak` (the `postgres-keycloak` Deployment, ArgoCD app `cicd/shopping-cart-identity`)

**Related:**
- `docs/bugs/2026-10-09-node-health-watch-ignores-ready-node-with-dead-kubelet-tunnel.md`:
  the fix there makes agent-0 restarts automatic, so this will happen more often.
- `docs/issues/2026-08-19-agent0-kubelet-proxy-instability.md`

## Symptom (2026-10-09)

1. At about 11:19 UTC the operator ran `docker restart k3d-k3d-cluster-agent-0` to recover ArgoCD.
2. `postgres-keycloak` (1 replica, no affinity) runs on agent-0, so the restart also killed it.
   The sandbox was recreated at 11:18:59Z, and the pod shows 2 restarts.
3. Keycloak (on agent-1) logged
   `Connection to postgres-keycloak.identity.svc.cluster.local:5432 refused`.
   Its readiness check returned 503 once, which was not enough failures to mark it NotReady.
4. A login during that window sat on the frontend's **"Completing login..."** spinner
   with no error and no way out.
5. By 11:25 UTC everything was healthy:
   - `/health/ready` reported the database check UP.
   - The auth page and the token endpoint answered in 0.08–0.24 s.

## Root causes

### A. The callback page has no timeout (frontend)

`LoginCallback.tsx` renders the spinner until `auth.isAuthenticated` or `auth.error`. A token
exchange that hangs, or a callback URL that is reloaded after its code was used (or expired),
gives neither. The spinner then runs forever.

### B. Keycloak's only database replica sits on the unstable node (infra)

`postgres-keycloak` has one replica, no affinity, and no PodDisruptionBudget. Agent-0 is the node
whose kubelet tunnel keeps dying (2026-08-19, 2026-10-05 to 10-09). Every restart of agent-0 is
therefore a short login outage.

### C. (minor) `FATAL: role "root" does not exist` every few seconds

The Postgres log shows this repeatedly. Some client connects without a username. The liveness
and readiness probes use `pg_isready -U $(POSTGRES_USER)`, but kubelet does **not** expand
`$(VAR)` in exec probes, so check whether the probe is the source first. Unrelated to the hang,
but it is log noise that hides real errors.

## Fix direction (to spec)

1. **Frontend:** after about 15 s on `/callback` with no result, show
   "Login took too long" plus a retry link that starts a fresh `signinRedirect()`. Also handle
   a `/callback` load with no `code` or `state` by redirecting home immediately.
   - Test: mock an auth context that never resolves; assert the retry UI appears after the
     timeout (fake timers). RED first.
2. **Infra:** keep `postgres-keycloak` off the flaky node, or make Keycloak ride out a short DB
   restart. Decide in the spec. Options:
   - Soft anti-affinity away from agent-0 (or a preferred node). This is cheap, but it is
     node-name coupling.
   - Keycloak DB pool settings (`KC_DB_POOL_*`, connection validation) so in-flight logins
     retry instead of failing.
   - Real HA Postgres. Probably too much for the hub.
3. **Probe noise:** identify the `root` client. If it is the probe, use a shell wrapper so the
   variable expands (`sh -c 'pg_isready -U "$POSTGRES_USER"'`).

## What NOT to do

- Do not hard-pin Keycloak or Postgres to one node with `nodeName` or required affinity.
- Do not lengthen Keycloak's readiness threshold to hide DB outages.
- Do not edit the live Deployment: ArgoCD self-heal reverts it. Change `shopping-cart-infra`
  via spec plus Codex on a feature branch.
