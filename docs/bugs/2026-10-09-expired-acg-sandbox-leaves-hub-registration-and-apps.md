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
- Eight generated Applications still target `ubuntu-k3s`, all with sync status `Unknown`:
  `ubuntu-k3s-{data-layer,grafana-dashboards,shopping-cart-basket,-frontend,-namespace,-order,-payment,-product-catalog}`.

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

The operator runs this. It is the same function `destroy_cluster` calls, and it touches only
`cluster-ubuntu-k3s` and apps whose destination is `ubuntu-k3s`. Read
`_k3s_aws_deregister_cluster` before running it. Then confirm `ubuntu-k3s-app-cluster` and
`cluster-ubuntu-hostinger` are untouched.

## What NOT to do

- **Never delete `ubuntu-k3s-app-cluster`.** Despite its name it registers the **hub itself**
  (`cluster-name: k3d-cluster`), and four ApplicationSets select it for the hub's ESO.
- Do not deregister on unreachability alone.
- Do not delete the Applications before the registration Secret: the ApplicationSet would
  regenerate them.
