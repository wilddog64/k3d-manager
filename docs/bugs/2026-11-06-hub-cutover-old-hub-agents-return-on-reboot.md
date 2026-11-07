# Bug: hub cut-over only boots out the old hub's agents, so a reboot restarts them and takes the public routes down

**Status:** VERIFIED — restated 2026-11-07 by Claude, verification already recorded below; was: LANDED 2026-11-06 (`76f34498`), independent verify PASS (offline E1, E2, E4, E5). Live E3 still open. The M4 singletons were disabled by hand before this fix, so a rollback to the M4 still needs the undo steps below.
**Priority:** P1
**Approval:** M4 disable: operator 2026-11-06 ("go ahead to disable 14 old hub singletons"). Fix: operator 2026-11-06 ("might start after /clear so make sure you make a good handoff"). Dispatch: operator 2026-11-06 ("go ahead to dispath P1 pub-cutover to Luna now").
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
- **Removed 2026-11-06 with the operator's go:** `chrome-cdp`, through `make chrome-cdp-stop`. `make chrome-cdp` installs it again; `make acg-recover` does so too.
- **Kept loaded:** `pushgateway-port-forward` (serves `127.0.0.1:9091`, healthy 200; which cluster it reaches is not checked), `hub-pushgateway-port-forward` and `hub-loki-port-forward` (both last exit 255, not running; cause not checked).

These 12 are outside `hub-singletons.list`, so the `bin/hub-cutover` fix does not cover them. Disabled agents cannot be bootstrapped, so a later cluster on the M4 needs `launchctl enable` first.

## Fix direction

- Cut-over runs `launchctl disable` for each singleton it stops on the old hub, and records it.
- Rollback runs `launchctl enable` for those labels before bootstrapping them.
- The M4's `hub-vault-profile` was reset to `laptop` on 2026-11-06, on the operator's instruction.

Added on Claude's read of `bin/hub-cutover` before dispatch, the same defect in two more paths:

- **A listed singleton that is not loaded at cut-over.** `bin/hub-cutover:366` handles only loaded labels, so an unloaded label with a plist is neither stopped nor disabled, and it starts at the next login. Disable every label in the list on the old host. Record in `$STATE_DIR/disabled-on-old` each label this cut-over disabled, writing the record before the disable, so a partial run can be rolled back. A label already disabled before the cut-over is not recorded, so rollback leaves it as it was. Read the current state with `launchctl print-disabled`.
- **Rollback and the new hub.** `bin/hub-cutover:313` only boots out the new hub's agents, so a reboot of the new hub restarts them beside the restored old hub. Rollback disables the labels it stops there. Cut-over runs `launchctl enable` for each label on the new hub before its bootstrap at `:382`, because a disabled agent cannot be bootstrapped.

Rollback on the old host enables every label in `disabled-on-old`, then bootstraps only the labels in `stopped-on-old`.

## Correction 1 (Claude review of Luna's first attempt, 2026-11-06)

Read from the diff; none of these was shown by the first attempt's tests.

1. **A re-run forgets a partial cut-over.** A cut-over that aborts after disabling some labels, then runs again, truncates `disabled-on-old` and `stopped-on-old`. The labels from the first run now read as already disabled, so they are not recorded and a rollback leaves them disabled and stopped. Keep both records when the recorded `old-host` equals `OLD_HOST`, compared before that file is rewritten; truncate them when it differs or is absent. Do not record a label twice. At the end of a successful rollback, empty both files without removing them.
2. **A label both disabled and loaded is never stopped.** The `continue` skips the bootout, so the cut-over aborts at the "remains loaded" check, and a re-run after a failed bootout hits the same stop. Check loaded state for every label. Skip only the record and the disable for a label already disabled. Boot out any loaded label. Add it to `stopped-on-old` only if it is in `disabled-on-old`. Otherwise print a warning naming the label: it was disabled before the cut-over, so a rollback does not restore it.
3. **Rollback can leave an enabled agent on the new hub.** A cut-over that fails at a bootstrap has already enabled that label, and rollback disables only loaded labels, so that agent starts at the new hub's next login beside the restored old hub. Rollback disables every listed label on the new hub and boots out those that are loaded. Remove `stopped-on-new`, which nothing reads, and the `mkdir -p` added for it.
4. **The plan understates the change.** `print_plan`, which the operator reads before confirming, says only that loaded agents stop. It must also say that listed agents are disabled on the old host.

## Verification (2026-11-06)

Independent verifier's 13 tests, written from the Acceptance block, on the landed commit: rc 0, 13 pass. On pre-fix `22c2be80`: rc 1, 11 fail (M1, N1, N2, M3 to M10). M2 and N3 pass there because that code never disables anything; N3's paired control M4 is red.

The first attempt was never committed, so E5's "red on Luna's first attempt" is shown by undoing one behaviour at a time in copies of the fix: re-run record kept (M6), disabled-and-loaded stop (M7), rollback disabling every label (M8), plan text (M9), truncate on a new host (M10), duplicate guard (M6). Each failed exactly the named test. The duplicate guard passed at first because M6 counted bootstraps only; Claude added the per-label enable count, which the Acceptance text requires, and reran every copy.

Gates on the final tree: `hub_cutover.bats` and `makefile_hub_port_forward.bats` 44 of 44, shellcheck rc 0. `make test` rc 2 on one test, the ESO smoke wiring test, which also fails on the clean tree at `d2b005f7`. `make test-pytest` rc 2 with 4 failed and 1777 passed, the same four names and counts on that clean tree; all four neither name `hub-cutover` nor reach it.

## Files

- `bin/hub-cutover`
- `scripts/tests/bin/hub_cutover.bats`

## Notes for the fixer

- `scripts/etc/machine/hub-singletons.list` needs no change.
- Output of `launchctl print-disabled gui/501`, captured on `m4-air.local`, 2026-11-06, for the stub:

  ```
  		"com.k3d-manager.cloud-bridge" => disabled
  		"com.k3d-manager.argocd-port-forward" => disabled
  ```

  A label absent from the output is not disabled. Match the whole quoted label.
- A rollback to a host disabled by hand before this fix, the M4 today, has no `disabled-on-old` record. Leave that case to the undo steps above.

## Acceptance

```yaml
must:
  - id: M1
    text: After a cut-over, every singleton stopped on the old host is both not loaded and marked disabled there.
  - id: M2
    text: A rollback leaves every recorded singleton enabled and loaded on the old host again.
  - id: M3
    text: A singleton that fails to disable stops the cut-over with a non-zero exit, before the new hub's agents load.
  - id: M4
    text: A listed singleton that was not loaded and not disabled at cut-over is disabled on the old host; a rollback enables it again and does not load it.
  - id: M5
    text: After a rollback every label it stopped on the new hub is not loaded and disabled there, and a later cut-over enables each label before its bootstrap on the new hub.
  - id: M6
    text: After a cut-over that aborts partway and is run again against the same old host, a rollback enables every label either run disabled and bootstraps every label either run stopped, each once.
  - id: M7
    text: A listed singleton that was disabled and loaded before the cut-over is stopped, the cut-over succeeds, and a warning names it. A rollback neither enables nor bootstraps it.
  - id: M8
    text: After a rollback every listed label is disabled on the new hub, including a label that was enabled but not loaded when the rollback started.
  - id: M9
    text: The plan printed before the confirmation states that listed agents are disabled on the old host.
  - id: M10
    text: A cut-over against a different old host from the recorded one starts with empty records (paired positive control for M6).
must_not:
  - id: N1
    text: A cut-over must not leave a stopped singleton in a state where launchd would load it at the next login.
  - id: N2
    text: A rollback must not leave a recorded singleton disabled.
  - id: N3
    text: A rollback must not enable a label that was already disabled on the old host before the cut-over (paired positive control is M4).
evidence:
  - id: E5
    proves: [M6, M7, M8, M9, M10]
    kind: offline
    text: Tests with the same stubs, including stubs that fail a disable, a bootout or a bootstrap on one label. M6, M7 and M8 shown red on Luna's first attempt.
  - id: E4
    proves: [M4, M5, N3]
    kind: offline
    text: Tests with stubs whose print-disabled output follows a real capture, red on the pre-fix commit for M4, M5 and N3 where the pre-fix code can show it.
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
