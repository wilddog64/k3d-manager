# ArgoCD Login Smoke Uses Stale Initial Secret

## Symptom

`make status` reports ArgoCD health as HTTP 200 but the credentialed login smoke reports:

```text
❌ ArgoCD login: HTTP 401
```

## Evidence

The login smoke in `bin/k3dm-webhook` reads only `cicd/argocd-initial-admin-secret`:

```text
argo_pass = ... _smoke_secret("cicd", "password", "argocd-initial-admin-secret")
```

The live secret metadata shows the initial secret predates the monthly rotation:

```text
argocd-initial-admin-secret   2026-07-20T22:48:00Z   13034991
argocd-secret                 2026-07-20T22:46:38Z   17966949
active argocd-secret passwordMtime: 2026-08-11T00:16:32Z
```

The active `argocd-secret` contains `admin.password` and `admin.passwordMtime`; the initial secret is
not updated by the rotator. The cluster currently has no `argocd-admin-secret` ExternalSecret or
target Secret:

```text
Error from server (NotFound): secrets "argocd-admin-secret" not found
```

The ArgoCD and Grafana HTTP health endpoints remain healthy, so this is not a service outage.

## Root cause

The v1.24 rotator changes the active ArgoCD bcrypt in `argocd-secret` and writes the plaintext password
to Vault. The smoke test still authenticates with the one-time bootstrap password in
`argocd-initial-admin-secret`, which becomes stale after rotation. The intended ESO-managed
`argocd-admin-secret` path is not present in the live cluster.

## Recommended fix

Make the smoke test read the same authoritative rotated credential used by `make show-service-passwords`
(preferably a reconciled ESO Secret sourced from Vault, with a controlled Vault fallback), and add a
regression test proving the initial bootstrap Secret is not used after rotation. Reconcile or explicitly
remove the missing `argocd-admin-secret` ExternalSecret path as part of that fix. Do not patch
`argocd-initial-admin-secret` as a workaround; it is bootstrap state, not the active credential source.
