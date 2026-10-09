# Frontend login hangs on "Completing login..." when Keycloak's Postgres restarts

**Filed:** 2026-10-09, Claude (operator saw the spinner on `frontend.3ai-talk.org`)
**Branch:** k3d-manager-v1.42.0 (bug docs are exempt from the 5-plan cap)
**Status:** PARTIAL — fix A merged as shopping-cart-frontend #115 (`3623e5b2`). It is **not live yet**: Hostinger's frontend is still pinned to `sha-85265e7` in `services/shopping-cart-frontend/kustomization.yaml`, and the change needs a repin. Fix C merged as shopping-cart-infra #108 (`03c6206f`) and was verified live 2026-10-09: the hub probe runs `sh -c 'pg_isready -U "$POSTGRES_USER" ...'`, with 0 `role "root"` log lines in 1h. B is deferred because the PV is pinned to agent-0.
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

---

## Findings (2026-10-09, Claude, read-only)

- **B cannot be fixed by scheduling alone.** `postgres-keycloak-pvc` is `local-path`, and its PV has
  required node affinity `kubernetes.io/hostname In [k3d-k3d-cluster-agent-0]`. Any affinity
  that steers the pod away from agent-0 would leave it Pending. Moving the database means a data
  migration (new PV on another node, dump/restore or realm re-import). That is a live operator
  decision, so B is **deferred** and is not in this spec. Since the node-health-watch fix
  (`90d8942a`), an agent-0 restart is automatic and takes about a minute, so the outage window is
  short; A makes it visible and recoverable for the user.
- **C is confirmed as the probes.** The `FATAL: role "root" does not exist` lines arrive three
  per 10 s, which is exactly the 5 s readiness probe plus the 10 s liveness probe.

## Implementation spec — A (frontend) and C (infra probe) (Codex, 2026-10-09)

Two repos, one commit each. Each repo: create the branch from `origin/main`
(`git fetch origin && git checkout -b <branch> origin/main`). Untracked files already in the
frontend checkout (`docs/issues/stripe-checkout-orchestration-blocker.md`,
`docs/plans/stripe-test-card-checkout.md`) are someone else's: leave them alone and never
`git add` them.

### A — `shopping-cart-frontend`, branch `fix/login-callback-timeout`

**Files:** `src/pages/LoginCallback.tsx`, new `src/pages/LoginCallback.test.tsx`. Nothing else.

**NEW `src/pages/LoginCallback.tsx`** (replace the whole file):
```tsx
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from 'react-oidc-context'
import LoadingSpinner from '@/components/ui/LoadingSpinner'

export const CALLBACK_TIMEOUT_MS = 15000

export default function LoginCallback() {
  const auth = useAuth()
  const navigate = useNavigate()
  const [timedOut, setTimedOut] = useState(false)

  const params = new URLSearchParams(window.location.search)
  const hasAuthResponse = params.has('code') || params.has('error')

  useEffect(() => {
    if (auth.isAuthenticated) {
      // Get the return URL from state, or default to home
      const returnTo = (auth.user?.state as { returnTo?: string })?.returnTo || '/'
      navigate(returnTo, { replace: true })
    }
  }, [auth.isAuthenticated, auth.user?.state, navigate])

  useEffect(() => {
    if (!hasAuthResponse && !auth.isLoading && !auth.isAuthenticated && !auth.error) {
      navigate('/', { replace: true })
    }
  }, [hasAuthResponse, auth.isLoading, auth.isAuthenticated, auth.error, navigate])

  useEffect(() => {
    if (auth.isAuthenticated || auth.error) {
      return
    }
    const timer = window.setTimeout(() => setTimedOut(true), CALLBACK_TIMEOUT_MS)
    return () => window.clearTimeout(timer)
  }, [auth.isAuthenticated, auth.error])

  if (auth.error) {
    return (
      <div className="flex h-64 flex-col items-center justify-center gap-4">
        <p className="text-red-600">Authentication error: {auth.error.message}</p>
        <button onClick={() => navigate('/')} className="text-primary-600 hover:underline">
          Return to Home
        </button>
      </div>
    )
  }

  if (timedOut && !auth.isAuthenticated) {
    return (
      <div className="flex h-64 flex-col items-center justify-center gap-4">
        <p className="text-gray-700">Login took too long. The sign-in service may be restarting.</p>
        <div className="flex gap-4">
          <button onClick={() => void auth.signinRedirect()} className="text-primary-600 hover:underline">
            Try again
          </button>
          <button onClick={() => navigate('/')} className="text-primary-600 hover:underline">
            Return to Home
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="flex h-64 flex-col items-center justify-center gap-4">
      <LoadingSpinner size="lg" />
      <p className="text-gray-600">Completing login...</p>
    </div>
  )
}
```

**NEW `src/pages/LoginCallback.test.tsx`.** Follow `src/pages/CheckoutPage.test.tsx`: import
`render`/`screen`/`fireEvent`/`act` from `@/test/test-utils` (add `act` from
`@testing-library/react` if test-utils does not re-export it), and mock `useNavigate` the same way.
Mock `react-oidc-context` so `useAuth` returns a mutable object
(`{ isAuthenticated, isLoading, error, user, signinRedirect: vi.fn() }`). Set the URL with
`window.history.pushState({}, '', '/callback?code=abc&state=xyz')` before each render (reset it
in `afterEach`). Tests:
1. **Never-resolving callback shows the retry UI after the timeout.** `vi.useFakeTimers()`;
   `isLoading: true`, not authenticated, no error, URL has `code`. Render: "Completing login..."
   is shown and "Login took too long" is not. `act(() => vi.advanceTimersByTime(CALLBACK_TIMEOUT_MS))`:
   "Login took too long" is shown. Click "Try again": `signinRedirect` called once.
   `vi.useRealTimers()` in `afterEach`.
2. **Callback URL without `code`/`error` goes home.** URL `/callback`, `isLoading: false`, not
   authenticated: `navigateMock` called with `'/', { replace: true }`.
3. **Success still navigates to returnTo.** `isAuthenticated: true`,
   `user: { state: { returnTo: '/orders' } }`: `navigateMock` called with `'/orders', { replace: true }`.
4. **Error still shows the error.** `error: new Error('boom')`: text `Authentication error: boom`.

**RED gate:** run the new test file against the **old** component before replacing it
(write the new test file first, run `npx vitest run src/pages/LoginCallback.test.tsx`, paste
the output). Tests 1 and 2 must fail (test 1 also fails to import `CALLBACK_TIMEOUT_MS`: for the
RED run, use the literal `15000` in the test, then switch to the import after the fix).

**Gates:** `npm run lint`, `npx tsc -b`, `npm test` (whole suite). Paste the summary lines.

**Commit message (exact):**
```
fix(login): time out a stuck /callback with a retry, and send a bare /callback home

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

### C — `shopping-cart-infra`, branch `fix/keycloak-postgres-probe-user`

**File:** `identity/keycloak/postgres.yaml` only.

Kubelet does not expand `$(VAR)` in exec probes, so `pg_isready` runs with a literal or empty
user and Postgres logs `role "root" does not exist` on every probe.

**OLD** (appears twice, under `livenessProbe` and under `readinessProbe`):
```yaml
          exec:
            command:
            - pg_isready
            - -U
            - $(POSTGRES_USER)
```
**NEW** (both places):
```yaml
          exec:
            command:
            - sh
            - -c
            - pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"
```
Keep `initialDelaySeconds` / `periodSeconds` unchanged.

**Gates:** `kubectl kustomize identity/keycloak >/dev/null` (client-side render only, no
cluster), and `python3 -c 'import yaml; list(yaml.safe_load_all(open("identity/keycloak/postgres.yaml")))'`.
If the repo has a CI lint for manifests (check `.github/workflows/`), run its local equivalent.

**Commit message (exact):**
```
fix(keycloak): expand POSTGRES_USER in the postgres probes via sh -c

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

### Both repos
- `git push -u origin <branch>`, then confirm with `git ls-remote origin refs/heads/<branch>`.
- Do NOT open a PR, merge, push to `main`, or use `--no-verify`.
- Do NOT touch any other file, and do NOT edit k3d-manager.
- Do NOT apply anything to a cluster.
