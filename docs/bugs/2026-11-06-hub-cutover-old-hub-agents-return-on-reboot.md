# Bug: hub cut-over only boots out the old hub's agents, so a reboot restarts them and takes the public routes down

**Status:** OPEN — live outage ended by hand 2026-11-06; all 15 singletons disabled on the M4 by hand; `bin/hub-cutover` not fixed
**Priority:** P1
**Approval:** M4 disable: operator 2026-11-06 ("go ahead to disable 14 old hub singletons"). Fix: operator 2026-11-06 ("might start after /clear so make sure you make a good handoff").
**Filed:** 2026-11-06
**Detected by:** Claude (M4 reboot check for D3 Part B) and the operator (Grafana 502)
**Affected:** `bin/hub-cutover` (cut-over and rollback); `scripts/etc/machine/hub-singletons.list`
**Branch:** `k3d-manager-v1.43.14`
**Related:** `docs/bugs/2026-11-05-launchdaemon-d3-part-b-user-listeners.md` (the reboot that exposed it); `docs/bugs/2026-07-26-hostinger-cloudflared-stray-connector-split-brain.md` (same tunnel symptom, different cause)

## Observed failure

The M4 was rebooted on 2026-11-06 for the Part B live check. The M5 has been the hub since 2026-10-31.

1. `com.k3d-manager.cloudflare-tunnel` started on the M4 at 03:50:52Z and registered connector `6dbff704` on tunnel `bb7ece59`, beside the existing `f5faed02`.
2. The M4 cluster is stopped, so that connector had no origins. Cloudflare sent traffic to it: frontend, Keycloak, Grafana and ArgoCD each returned 502, on every probe. The operator's Grafana screenshot is stamped 03:58:30 UTC.
3. `com.k3d-manager.vault-failover` started on the M4 and, at 03:56:01Z, failed its probes of the stopped local Vault and ran a real failover from `laptop` to `hostinger`.

The operator ended the outage with `launchctl bootout` and `launchctl disable` on the M4 agent. One connector then remained, and frontend 200, Keycloak 302, Grafana 302 and ArgoCD 200 held for three probes.

## Root cause

`bin/hub-cutover` stops the old hub's singletons with `launchctl bootout` only (`bin/hub-cutover:368`). There is no `launchctl disable` anywhere in the file, and the plists stay in `~/Library/LaunchAgents`, so launchd loads them all again at the next login. Rollback has no matching step because nothing was disabled.

## What the M4 failover did

Read from `~/Library/Logs/k3dm-vault-failover.log` and `scripts/plugins/vault.sh:1153`:

- **Hostinger Vault was not written.** `vault_seed_hub_into_context` stopped at `could not read source vault-root token from k3d-k3d-cluster/secrets`, which comes before any port-forward or write.
- **The ClusterSecretStore was not repointed.** The log says `_hostinger_reconcile_vault_cluster_store not loaded`. `vault-backend` still points at `vault-bridge` and is Valid.
- **Hostinger is healthy.** Vault is unsealed and all 20 ExternalSecrets report Ready True.
- **One M4 state change remains.** `~/.local/share/k3d-manager/hub-vault-profile` now says `hostinger`; it was `laptop` before. Reset to `laptop` 2026-11-06 on the operator's instruction.

The seed aborted only because the M4 cluster was stopped. This path should not be reachable from a machine that is no longer the hub.

## State of the M4

- **Disabled and stopped 2026-11-06, each confirmed not loaded and disabled:** `cloudflare-tunnel` (by the operator), then by Claude with the operator's go: `vault-failover`, `ssh-tunnel-vault`, `ssh-tunnel`, `cleanup`, `node-health-watch`, `sandbox-reaper`, `acg-watch`, `prometheus-credential-rotator`, `hub-snapshot`, `hub-data-export`, `test-metrics`, `cloud-bridge`, `webhook`, `hermes`. Afterwards: one tunnel connector, frontend 200, Keycloak 302, Grafana 302, ArgoCD 200.
- **Undo:** `launchctl enable gui/$(id -u)/com.k3d-manager.<label>`, then `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.k3d-manager.<label>.plist`. A `make hub-cutover-rollback` to the M4 today would not enable them, so this step is needed first.
- **Reset later:** the M4 `hub-vault-profile` was left at `hostinger` here, because the go covered the agents only. It was reset to `laptop` on 2026-11-06.
- **Also disabled and stopped 2026-11-06 with the operator's go, not in the list:** `webhook-token-rotate`, `argocd-port-forward`, `grafana-port-forward`, `keycloak-port-forward`, `frontend-port-forward`, `vault-port-forward`, `prometheus-port-forward`, `alertmanager-port-forward`, `prometheus-auth-proxy`, `alertmanager-auth-proxy`, `sandbox.prometheus-port-forward`, `sandbox.pushgateway-port-forward`. Each confirmed; the public routes still answered.
- **Kept loaded:** `chrome-cdp`, `pushgateway-port-forward` (serves `127.0.0.1:9091`, healthy 200; which cluster it reaches is not checked), `hub-pushgateway-port-forward` and `hub-loki-port-forward` (both last exit 255, not running; cause not checked).

These 12 are outside `hub-singletons.list`, so the `bin/hub-cutover` fix does not cover them. Disabled agents cannot be bootstrapped, so a later cluster on the M4 needs `launchctl enable` first.

## Fix direction

- Cut-over runs `launchctl disable` for each singleton it stops on the old hub, and records it.
- Rollback runs `launchctl enable` for those labels before bootstrapping them.
- The M4's `hub-vault-profile` was reset to `laptop` on 2026-11-06, on the operator's instruction.

## Acceptance

```yaml
must:
  - id: M1
    text: After a cut-over, every singleton stopped on the old host is both not loaded and marked disabled there.
  - id: M2
    text: A rollback leaves every recorded singleton enabled and loaded on the old host again.
  - id: M3
    text: A singleton that fails to disable stops the cut-over with a non-zero exit, before the new hub's agents load.
must_not:
  - id: N1
    text: A cut-over must not leave a stopped singleton in a state where launchd would load it at the next login.
  - id: N2
    text: A rollback must not leave a recorded singleton disabled.
evidence:
  - id: E1
    proves: [M1, M3, N1]
    kind: offline
    text: Tests with a stub launchctl and ssh record the disable for each label, and the abort when a disable fails.
  - id: E2
    proves: [M2, N2]
    kind: offline
    text: Tests with the same stubs record enable before bootstrap for each recorded label.
  - id: E3
    proves: [M1, N1]
    kind: live
    text: Operator or Claude reboots the old hub after a cut-over or drill. One tunnel connector remains, no singleton is loaded, and the public routes keep answering.
interface:
  - bin/hub-cutover
  - make hub-cutover-rollback
  - scripts/etc/machine/hub-singletons.list
```
