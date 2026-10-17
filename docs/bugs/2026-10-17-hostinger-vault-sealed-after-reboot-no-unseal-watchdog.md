# Bug: Hostinger Vault stays sealed after a node reboot — no unseal watchdog there

**Status:** OPEN — cause confirmed live 2026-10-17; recovery needs the operator
**Priority:** P1
**Approval:** pending
**Found:** 2026-10-17, Claude, while `make appsets-reapply` failed its final check
**Affected:** `ubuntu-hostinger` Vault (`secrets/vault-0`), every ExternalSecret on Hostinger

## Symptom

`make appsets-reapply` ended with `Error 1`, listing `ubuntu-hostinger-data-layer` and
`ubuntu-hostinger-shopping-cart-namespace` as `health Degraded` under "Applications on a stale
values branch". Neither is on a stale branch; both are Synced. They are Degraded because their
ExternalSecrets are.

## Evidence (live, read-only, 2026-10-17)

- `vault status` in `secrets/vault-0` on Hostinger: `Sealed true`, `Unseal Progress 0/1`; the pod
  is `0/1 Running` since the 18:10:52Z reboot (`docs/bugs/2026-10-17-hostinger-node-unresponsive-then-rebooted.md`).
- `ClusterSecretStore/vault-backend`: `Ready=False InvalidProviderConfig: unable to create client`.
- 14 of 15 ExternalSecrets in `shopping-cart-apps` / `shopping-cart-data` are `SecretSyncedError`.
  App and data pods still run on the Secrets synced before the reboot.
- The hub has `secrets/vault-unseal-watchdog` (CronJob, `*/5`). Hostinger has **no CronJob at all**,
  although its `secrets/vault-unseal` Secret exists. `vault_install_unseal_watchdog` is only called
  from `deploy_vault` for the cluster it deploys; nothing installs it on an app cluster.

## Impact

Any Hostinger reboot leaves Vault sealed until someone notices. Secrets keep working until a pod
needs a Secret that changed or was deleted, or a new ExternalSecret is added — then that app breaks.
Rotations stop silently.

## Secondary: the reapply check mislabels health as a stale branch

`appsets-reapply` prints Degraded Applications under "Applications on a stale values branch" with
"Fix: reapply the ApplicationSets", which sends the operator to the wrong fix. A Degraded app on the
correct branch should be reported separately.

## Secondary: the watchdog image is read from the wrong cluster

With a context argument, `vault_install_unseal_watchdog` still reads the Vault image from
`_kubectl` (the current context, i.e. the hub), not from the target context.

## Fix direction

1. Install the unseal watchdog on every cluster that runs its own Vault — at least on Hostinger,
   as part of the Hostinger provisioning/refresh path — and read the image from that cluster.
2. Split the reapply check's output: wrong branch vs. right branch but unhealthy.

## Acceptance

```yaml
must:
  - id: M1
    text: After a Hostinger Vault pod restart, Vault is unsealed within 10 minutes with no operator action.
  - id: M2
    text: The Hostinger provisioning/refresh path installs the unseal watchdog CronJob in the Vault namespace on ubuntu-hostinger.
  - id: M3
    text: The watchdog image is taken from the target cluster's Vault StatefulSet when a context is given.
  - id: M4
    text: appsets-reapply reports a Degraded Application on the expected branch under a health heading, not as a stale branch.
must_not:
  - id: N1
    text: The watchdog install never reads the Vault image from a context other than the one it installs into (red on pre-fix).
  - id: N2
    text: The install never prints or logs unseal key material.
  - id: N3
    text: An app on the expected values branch is never listed as "on a stale values branch" (red on pre-fix).
evidence:
  - id: E1
    proves: [M2, M3, N1, N2]
    kind: offline
    text: BATS with a kubectl stub recording --context per call.
  - id: E2
    proves: [M4, N3]
    kind: offline
    text: BATS over the reapply check with a stubbed Application list (one stale, one Degraded on-branch).
  - id: E3
    proves: [M1]
    kind: live
    text: Claude or operator deletes secrets/vault-0 on Hostinger and confirms `Sealed false` within 10 minutes.
interface:
  - scripts/plugins/vault.sh vault_install_unseal_watchdog [ns] [context]
  - make appsets-reapply / the values-branch confirmation it runs
  - CronJob secrets/vault-unseal-watchdog, Secret secrets/vault-unseal
```
