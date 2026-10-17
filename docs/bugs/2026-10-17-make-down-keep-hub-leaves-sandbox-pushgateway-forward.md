# Bug: `make down` that keeps the hub leaves the sandbox's Pushgateway port-forward crash-looping

**Status:** OPEN — dispatched to Codex 2026-10-17
**Priority:** P3
**Severity:** low
**Approval:** approved — operator, 2026-10-17: "go ahead to dispatch that P3 bug to codex"
**Found:** 2026-10-17, Claude, checking the operator's `make down CLUSTER_PROVIDER=k3s-aws KEEP_LOCAL=1`
**Affected:** `bin/cluster-down` (sandbox launchd cleanup), macOS laptop launchd state

## Symptom

After a successful sandbox teardown (stack deleted, context `ubuntu-k3s` removed, hub registration
and generated Applications gone, `cloud teardown: verified`), the LaunchAgent
`com.k3d-manager.sandbox.pushgateway-port-forward` is still loaded. Its program is
`kubectl port-forward svc/prometheus-pushgateway --namespace monitoring --context ubuntu-k3s 9092:9091`.
The context no longer exists, so kubectl exits 1 and launchd (`KeepAlive`) restarts it:
`launchctl print` showed `runs = 5`, `last exit code = 1` within minutes. Nothing listens on 9092.

The teardown log never printed `Stopping Pushgateway port-forward launchd agent...`.

The sandbox LaunchDaemon `/Library/LaunchDaemons/com.k3d-manager.sandbox.frontend-browser-http.plist`
(and `com.k3d-manager.sandbox.loopback-alias.plist`) also remain on disk; their loaded state was
not read (needs sudo).

## Cause

In `bin/cluster-down`, the block that stops the sandbox-scoped agents — Cloudflare tunnel, the
sandbox frontend browser daemon, and the sandbox Pushgateway port-forward (line ~333) — sits
inside `if [[ "${_keep_hub}" -eq 0 ]] && _is_mac; then` (line 240). That branch only runs when the
hub is being deleted. Since keep-hub became the default (2026-10-03,
`docs/bugs/2026-10-03-make-down-deletes-hub-by-default.md`), the ordinary sandbox teardown skips it.

`make down ... CLEANUP_STALE=1` hides this: `bin/cleanup-stale-sandbox` removes the same agent.

## Fix direction

Move the stop/remove of `com.k3d-manager.sandbox.*` agents (and other agents whose program targets
the `ubuntu-k3s` context or the k3s-aws state dir) out of the `_keep_hub -eq 0` branch so they run
on every k3s-aws teardown. Hub-scoped agents (unscoped labels, `hub-*`, Hostinger's
`com.k3d-manager.pushgateway-port-forward`) stay where they are. Keep the scoping rule from
`docs/bugs/2026-10-05-sandbox-make-up-hijacks-hostinger-launchd-labels.md`: never touch an agent that
does not belong to the sandbox.

## Acceptance

```yaml
must:
  - id: M1
    text: A k3s-aws cluster-down with keep-hub (the default) unloads and removes com.k3d-manager.sandbox.pushgateway-port-forward.
  - id: M2
    text: The same teardown unloads/removes the sandbox frontend-browser-http LaunchDaemon (sudo available or TTY), or warns that it was skipped when headless without sudo.
  - id: M3
    text: With --delete-hub the sandbox agents are still removed exactly once (no regression).
must_not:
  - id: N1
    text: Keep-hub teardown never leaves com.k3d-manager.sandbox.pushgateway-port-forward loaded or its plist on disk (red against pre-fix bin/cluster-down).
  - id: N2
    text: Keep-hub teardown never unloads or removes hub/Hostinger agents (com.k3d-manager.pushgateway-port-forward, hub-pushgateway-port-forward, alertmanager-*, keycloak-port-forward, argocd-browser-https, cloudflare-tunnel when it belongs to Hostinger).
evidence:
  - id: E1
    proves: [M1, M3, N1, N2]
    kind: offline
    text: BATS in scripts/tests with launchctl, kubectl, aws and sudo stubbed, recording every launchctl/rm call; keep-hub and delete-hub cases; N1 red on pre-fix.
  - id: E2
    proves: [M2]
    kind: offline
    text: BATS headless-no-sudo case asserts the warning and no sudo call.
  - id: E3
    proves: [M1, N2]
    kind: live
    text: Claude, after the operator's next make down CLUSTER_PROVIDER=k3s-aws KEEP_LOCAL=1 — launchctl list shows no com.k3d-manager.sandbox.* agent and the hub/Hostinger agents still loaded.
interface:
  - bin/cluster-down --confirm [--keep-hub|--delete-hub] (CLUSTER_PROVIDER=k3s-aws)
  - make down CLUSTER_PROVIDER=k3s-aws KEEP_LOCAL=1
  - launchd labels com.k3d-manager.sandbox.pushgateway-port-forward, com.k3d-manager.sandbox.frontend-browser-http
```

## Operator cleanup for now

launchctl bootout gui/$(id -u)/com.k3d-manager.sandbox.pushgateway-port-forward
rm -f ~/Library/LaunchAgents/com.k3d-manager.sandbox.pushgateway-port-forward.plist

(or `make cleanup-stale-sandbox CLUSTER_PROVIDER=k3s-aws CONFIRM=1`, which also removes the stale
local sandbox state). The next sandbox `make up` reinstalls the agent either way.
