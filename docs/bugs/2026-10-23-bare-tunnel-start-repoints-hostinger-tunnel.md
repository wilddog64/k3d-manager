# Bug: a bare `tunnel_start` repoints the Hostinger tunnels at the `ubuntu` sandbox alias, and Hostinger loses Vault

**Status:** LIVE-VERIFIED 2026-10-24 (E2) — after the 2026-10-23 19:28 PDT Hostinger refresh, both unscoped agents (`ssh-tunnel`, `ssh-tunnel-vault`) run and target the Hostinger host; Hostinger `vault-backend` ClusterSecretStore Valid/Ready=True; 20/20 ExternalSecrets SecretSynced. Was FIXED — LANDED `8ca5668f` 2026-10-23 — E1 green (tunnel.bats 23; 115 across the suites that load k3s-hostinger.sh); tests 1 and 3 red on the pre-fix plugin, test 5 red without the F3 reconcile line. Landed with `--allow-out-of-scope` because the task's base spec predates the F3 amendment. E2 PASSED 2026-10-23 18:58 PDT: after `make refresh CLUSTER_PROVIDER=k3s-hostinger`, both unscoped wrappers target `ubuntu@srv1754834.hstgr.cloud`, the autossh/ssh processes stayed up, `vault-backend` Ready=True, 20/20 ExternalSecrets SecretSynced (`kyverno/cosign-public-key` needed one force-sync: its 1h interval had last failed during the refresh).
**Priority:** P2
**Fix commit:** `8ca5668f`
**Live evidence:** 2026-10-24 · run claude-launchd-and-kubectl-read · env laptop+ubuntu-hostinger · scenario unscoped-tunnels-target-hostinger-after-refresh · commit f35d3199 · proves E2
**Severity:** high — every Hostinger ExternalSecret stops syncing; running pods keep the last synced Secrets
**Release:** v1.43.5 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-23, by Claude, from the operator's 18:15 PDT Slack cluster status (Hostinger: 4 fail)
**Approval:** explicit 2026-10-23. The operator said: "go ahead to dispatch P2 and P3 to Codex".
**Related:** `docs/bugs/2026-10-23-hostinger-tunnel-logs-unusable-and-reconnect-slow.md` (its E2 caused this),
`docs/bugs/2026-10-18-sandbox-tunnel-start-mistakes-hostinger-tunnel-for-its-own.md`,
`docs/issues/2026-04-28-vault-bridge-same-port-reverse-tunnel-reset.md`

**Component:** `scripts/plugins/tunnel.sh` (`tunnel_start`, `TUNNEL_SSH_HOST` default)

## Problem

The unscoped launchd agents `com.k3d-manager.ssh-tunnel` and `com.k3d-manager.ssh-tunnel-vault`
belong to Hostinger. `_hostinger_reconcile_vault_cluster_store` writes them with
`TUNNEL_SCOPE=""` and `TUNNEL_SSH_HOST=ubuntu@<hostinger host>`. Sandboxes use
`TUNNEL_SCOPE=sandbox` and their own `com.k3d-manager.sandbox.*` agents.

`tunnel.sh` defaults `TUNNEL_SSH_HOST` to `ubuntu`, the ACG sandbox SSH alias. A bare
`./scripts/k3d-manager tunnel_start` therefore rewrites the Hostinger agents to target the sandbox.

That happened at 07:58 PDT on 2026-10-23. The E2 step of the tunnel-logs bug asked the operator to
"rerun `tunnel_start` for the hub", and Claude's instruction did not say how. Both agents were
rewritten to `ubuntu`, which `~/.ssh/config` resolves to 44.247.81.210, a sandbox that no longer
exists. From then on:

- `ssh -R 8200:127.0.0.1:18200 ubuntu` never reaches Hostinger, so Hostinger's socat on 8201 has
  nothing behind it.
- 07:59 PDT: ESO's `vault-backend` ClusterSecretStore goes `Ready=False`
  (`lookup-self ... EOF`), and all 20 Hostinger ExternalSecrets show `SecretSyncedError`.
- The agents restart in a loop. The forward agent `-L 6443` also targets the sandbox.

The tunnel-logs E2 passed anyway: it checked `kubectl --context ubuntu-hostinger get --raw /readyz`,
but that context talks to `https://2.25.146.252:6443` directly, not through the tunnel. The check did
not prove what it claimed.

## Fix

### F1. No default host for the unscoped agents

When `TUNNEL_SCOPE` is not `sandbox`, `tunnel_start` refuses to run unless `TUNNEL_SSH_HOST` was set
explicitly by the caller. The message names `make refresh CLUSTER_PROVIDER=k3s-hostinger` as the way
to restart the Hostinger tunnels. The sandbox scope keeps the `ubuntu` default.

### F2. Refuse a rewrite to a different host

When the unscoped agents already exist and target a different host than `TUNNEL_SSH_HOST`,
`tunnel_start` refuses unless `TUNNEL_FORCE_HOST=1` is set, and prints both hosts.

### F3. The Hostinger reconcile path is authoritative

`tunnel_stop` unloads the agents but leaves the wrapper scripts, so after a bad repoint the
reconcile path finds the wrong host in them. `_hostinger_reconcile_vault_cluster_store` must
be able to repoint: it sets `local TUNNEL_FORCE_HOST=1` alongside its `local TUNNEL_SCOPE=""`
before calling `tunnel_start`. (Amended 2026-10-23 at review: without this, F2 blocks
`make refresh CLUSTER_PROVIDER=k3s-hostinger`, the recovery path.)

## Tests

`scripts/tests/plugins/tunnel.bats` (stub `launchctl`, temp `HOME`):

1. Bare `tunnel_start` with no `TUNNEL_SSH_HOST` and no scope fails, writes no plist, and names the
   refresh command.
2. `TUNNEL_SCOPE=sandbox tunnel_start` with no host still writes the sandbox agents for `ubuntu`.
3. Existing unscoped agents for `ubuntu@hostinger.example` and `TUNNEL_SSH_HOST=ubuntu` refuse; with
   `TUNNEL_FORCE_HOST=1` they are rewritten.
4. The Hostinger reconcile path (explicit host, matching existing agents) still writes the agents.
5. Existing unscoped wrappers for `ubuntu`, then the Hostinger reconcile path with
   `ubuntu@hostinger.example`: the agents are rewritten to the Hostinger host (stub `kubectl`,
   `launchctl` and `ssh`; or call the reconcile's tunnel block with the provider's own helpers stubbed).

Show tests 1 and 3 red against the pre-fix plugin.

## Files

- `scripts/plugins/tunnel.sh`
- `scripts/lib/providers/k3s-hostinger.sh` (F3 only)
- `scripts/tests/plugins/tunnel.bats`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: tunnel_start without TUNNEL_SCOPE=sandbox refuses unless the caller set TUNNEL_SSH_HOST, and names make refresh CLUSTER_PROVIDER=k3s-hostinger.
  - id: M2
    text: tunnel_start refuses to repoint existing unscoped agents at a different host unless TUNNEL_FORCE_HOST=1.
  - id: M3
    text: The Hostinger reconcile path and the sandbox scope keep working, and the reconcile path can repoint agents left at a wrong host.
must_not:
  - id: N1
    text: A bare tunnel_start must not write or reload the unscoped launchd agents.
  - id: N2
    text: Tests must not call the real launchctl or ssh, or write under the real ~/Library/LaunchAgents.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, N1, N2]
    text: bats scripts/tests/plugins/tunnel.bats green; tests 1 and 3 red on the pre-fix plugin.
  - id: E2
    kind: live
    proves: [M3]
    text: After make refresh CLUSTER_PROVIDER=k3s-hostinger, Claude confirms both unscoped agents target the Hostinger host, the Hostinger vault-backend store is Ready=True, and the ExternalSecrets sync.
interface:
  - scripts/k3d-manager tunnel_start / tunnel_stop (env TUNNEL_SCOPE, TUNNEL_SSH_HOST, TUNNEL_FORCE_HOST)
  - ~/Library/LaunchAgents/com.k3d-manager.ssh-tunnel{,-vault}.{plist,sh}
```

## Definition of Done

- [ ] F1–F3 and a CHANGELOG `[Unreleased]` `### Fixed` entry; only the Files above change.
- [ ] `bats scripts/tests/plugins/tunnel.bats` green; `shellcheck -S warning scripts/plugins/tunnel.sh` clean.
- [ ] Tests 1 and 3 shown red on a temp copy of the pre-fix plugin.
- [ ] Commit: `fix(tunnel): refuse to repoint the Hostinger tunnels at a default host`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT run the real `tunnel_start`, `launchctl` or `ssh` from tests.
- Do NOT change the sandbox scope's labels, ports or default host.
- Do NOT modify files outside the Files list.
