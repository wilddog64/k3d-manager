# Issue: v1.11.0 P4 assisted failover live verification gap

## What was tested / attempted

Implemented the Tier 3 P4 assisted-failover watchdog and validated the pure logic in BATS plus the
full repo suite locally.

## Actual output

```text
The probe -> flip -> re-seed -> reconcile path and the LaunchAgent install were not exercised live in this session.
```

## Root cause if known

This path depends on the control-plane laptop launchd environment, both kube-contexts, and a
provisioned in-cluster Vault on Hostinger. The branch still carries the documented P3 live gap:
`ubuntu-hostinger` is reachable, but the P2b in-cluster Vault objects are not present there yet.

## Recommended follow-up

Live-verify all of the following after the Hostinger in-cluster Vault is actually provisioned:

- `vault_failover_hub_into_context <app-ctx> --probe-only`
- sustained-failure flip `laptop -> hostinger`
- persisted state-file behavior across a reconcile / refresh
- `vault_seed_hub_into_context` invocation during failover to `hostinger`
- `_hostinger_reconcile_vault_cluster_store` repointing the CSS after the flip
- `vault_install_failover_watchdog` LaunchAgent bootstrap and periodic execution
