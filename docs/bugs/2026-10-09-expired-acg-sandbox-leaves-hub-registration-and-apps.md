# An expired ACG sandbox leaves its hub ArgoCD registration and 8 apps behind

**Filed:** 2026-10-09, Claude (operator: "can we automatically clean up these after acg sandbox tear down")
**Branch:** k3d-manager-v1.42.0 (bug docs are exempt from the 5-plan cap)
**Status:** OPEN — filed; not specified
**Priority:** P3 — noise in ArgoCD, and alert/dashboard pollution; no outage
**Severity:** Low
**Component:**
- `scripts/lib/providers/k3s-aws.sh` (`_k3s_aws_deregister_cluster`, the sandbox watcher)
- Hub ArgoCD (`cicd`)

**Related:**
- `docs/bugs/v1.25.0-bugfix-k3s-aws-hub-deregister.md`: added the deregister, but only to
  `destroy_cluster`.
- `docs/bugs/2026-05-20-acg-up-expired-sandbox-auto-restart.md`

## Symptom (2026-10-09)

- Hub Secret `cicd/cluster-ubuntu-k3s` (`k3d-manager/provider: k3s-aws`) still exists. It was
  created 2026-10-06 00:44 UTC; the sandbox lives at most 8h.
- Ten generated Applications still target the sandbox, all with sync status `Unknown`:
  - Eight by destination name `ubuntu-k3s`:
    `ubuntu-k3s-{data-layer,grafana-dashboards,shopping-cart-basket,-frontend,-namespace,-order,-payment,-product-catalog}`.
  - Two by server `https://host.k3d.internal:6443` (the sandbox tunnel endpoint):
    `ubuntu-k3s-eso` and `ubuntu-k3s-platform`. The hub's own ESO is `k3d-cluster-eso`
    (`kubernetes.default.svc`) and is not matched.

## Root cause

`_k3s_aws_deregister_cluster` (`k3s-aws.sh:304`) deletes the registration Secret and the
generated Applications. It runs **only from `destroy_cluster --confirm`**. When the sandbox ends
any other way, nothing removes the registration:
- ACG expiry (4h, or 8h with the extension)
- a Pluralsight-side delete
- a laptop sleep through expiry

## Fix direction (to spec)

Deregister automatically once the sandbox is provably gone, not merely unreachable for a moment:
- **Watcher path:** when `acg_watch` sees the sandbox expire or end, call
  `_k3s_aws_deregister_cluster`.
- **Reaper path:** this backs up the watcher, since it dies with the laptop session. A periodic
  hub-side check deregisters `cluster-ubuntu-k3s` when **both** of these hold:
  - its apps have been `Unknown` for at least 30 min, and
  - a positive gone signal exists: the CloudFormation stack is absent, or the sandbox credentials
    return `InvalidClientTokenId` / expired.
  It must never act on reachability alone, because a tunnel blip is not a teardown.
- Log every deregister. Add a BATS test with stubbed AWS and kubectl: "stack gone + Unknown"
  deregisters; "Unknown only" does not. RED first.

## Immediate cleanup (operator)

Use the dedicated target, not `make down`. It is dry-run by default. It was broken (exit 2 on
every call) until fixed alongside this doc; see the CHANGELOG.
```
make cleanup-stale-registration CLUSTER=ubuntu-k3s            # preview: 1 Secret + 10 apps
make cleanup-stale-registration CLUSTER=ubuntu-k3s CONFIRM=1  # delete Secret first, then apps
```
It selects by the label `argocd.argoproj.io/cluster-name=ubuntu-k3s`, so `ubuntu-k3s-app-cluster`
(`cluster-name: k3d-cluster`, the hub) is never selected.

### Why not `make down`

`make down` (the default provider is k3s-aws, and the default `KEEP_LOCAL=1` keeps the hub) does
call `_k3s_aws_deregister_cluster`. After the provider `case` in `bin/cluster-down`, however,
these steps run **without** a `_keep_hub` guard:
- It kills `vault-pf.pid` and unloads and removes `com.k3d-manager.vault-port-forward`.
  That LaunchAgent forwards the **hub's** Vault (`vault-0 18200:8200 --context k3d-k3d-cluster`),
  so the hub loses its local Vault access.
- It stops the frontend port-forward PID and the ACG Prometheus port-forward.

That is an over-broad teardown with the hub kept. Confirm and fix it in the spec. Until then, use
the cleanup target above for a sandbox that has already expired.

## What NOT to do

- **Never delete `ubuntu-k3s-app-cluster`.** Despite its name it registers the **hub itself**
  (`cluster-name: k3d-cluster`), and four ApplicationSets select it for the hub's ESO.
- Do not deregister on unreachability alone.
- Do not delete the Applications before the registration Secret: the ApplicationSet would
  regenerate them.
