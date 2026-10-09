# postgres-keycloak rolling update runs two postmasters on one data directory

**Status:** FIXED (merged) — shopping-cart-infra #109 `7028ae5` 2026-10-09; hub sync to `Recreate` pending at merge time. Follow-up: `identity/ldap/deployment.yaml` (`ldap`, Deployment + RWO PVCs) has the same risk, not changed.
**Priority:** P2 — every pod-template change to `postgres-keycloak` risks corrupting the Keycloak database
**Component:** `shopping-cart-infra` `identity/keycloak/postgres.yaml` (Deployment `identity/postgres-keycloak`, hub)
**Found:** 2026-10-09, while verifying the probe fix (shopping-cart-infra #108, `03c6206`)
**Related:** `docs/bugs/2026-10-09-frontend-login-callback-hangs-when-keycloak-db-restarts.md` (same Deployment; item B, moving the database off agent-0)

## Symptom

After #108 synced, the new `postgres-keycloak` pod restarted once, 60 s after it started. One
`keycloak-realm-reconcile` pod failed with `UnknownError`; the next one succeeded.

## Evidence (hub, read-only, 2026-10-09 UTC)

| Time | Event |
|---|---|
| 14:17:13 | new ReplicaSet `897bc7b6c` creates its pod; the old pod `8554cc89d5-h6gd9` is still running |
| 14:17:19 | new postmaster: `database system is ready to accept connections` |
| 14:17:28 | old pod killed (`Killing`), so for about 10 s both postmasters had the same data directory open |
| 14:18:19 | new postmaster: `could not open file "postmaster.pid"` → `performing immediate shutdown because data directory lock file is invalid` → exit 0 |
| 14:18:21 | container restarted; clean since, no FATAL or PANIC |

- Deployment strategy is `RollingUpdate` with `maxSurge: 25%`, which rounds up to 1 pod at `replicas: 1`.
- The PVC `postgres-keycloak-pvc` is `ReadWriteOnce` on `local-path`, pinned to agent-0. RWO is
  enforced per **node**, not per pod, so the surge pod lands on the same node and mounts the same volume.
- The old postmaster removed `postmaster.pid` on shutdown; the new one found its lock file gone
  and shut itself down. That self-check saved the database this time. During the overlap, two
  postmasters were writing to one data directory.

## Root cause

A single-writer database is run as a `Deployment` with the default `RollingUpdate` strategy on an
RWO volume. Every template change (image bump, probe change, env change) starts the replacement
before the old pod stops.

## Implementation spec (Codex)

**Repo:** `shopping-cart-infra`. **Branch:** `fix/keycloak-postgres-recreate-strategy` from `origin/main`.
**Files:** `identity/keycloak/postgres.yaml`, `CHANGELOG.md` (`[Unreleased]` → `### Fixed`). Nothing else.

**OLD:**
```yaml
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: postgres-keycloak
```
**NEW:**
```yaml
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app.kubernetes.io/name: postgres-keycloak
```

Also check every other `kind: Deployment` in the repo that mounts a `ReadWriteOnce` PVC
(`grep -rn -A40 'kind: Deployment'` and look for `persistentVolumeClaim`). List them in the
report; do **not** change them in this commit.

**Gates:** `kubectl kustomize identity/keycloak >/dev/null`; `python3 -c 'import yaml; list(yaml.safe_load_all(open("identity/keycloak/postgres.yaml")))'`.
Push with `git push -u origin <branch>` and confirm with `git ls-remote`. No PR, no merge, no `main`, no `--no-verify`, nothing applied to a cluster.

**Commit message (exact):**
```
fix(keycloak): use Recreate so postgres never runs two postmasters on one volume

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

## Rollout note

Syncing the fix changes the Deployment spec but not the pod template, so it does not restart the
pod. The next template change uses `Recreate`, which means about 10–30 s of Keycloak database
downtime instead of an overlap.
