# Bug: a sandbox `make up` mistakes Hostinger's SSH tunnel for its own, so the sandbox never gets a Vault reverse tunnel

**Filed:** 2026-10-18 (Claude, from the operator's `make up CLUSTER_PROVIDER=k3s-aws` at 18:30 PDT 2026-10-17)
**Status:** OPEN
**Priority:** P1 — a sandbox `make up` fails whenever the Hostinger tunnel is up, and the only workaround in `docs/issues/2026-07-07-two-cluster-vault-bridge-css-not-ready-k3s-aws.md` (one remote cluster at a time) means taking down the public Hostinger site
**Severity:** high
**Approval:** pending — filed by Claude; fix not yet approved or dispatched
**Release:** v1.43.4 (bug; exempt from the plan cap)
**Component:** `scripts/plugins/tunnel.sh` (`_tunnel_is_running`, `tunnel_start`, launchd labels), `scripts/lib/providers/k3s-aws.sh`, `scripts/lib/providers/k3s-hostinger.sh` (`TUNNEL_SSH_HOST` override at line 940), `bin/cluster-down`, `bin/cluster-refresh`
**Related:** `docs/issues/2026-07-07-two-cluster-vault-bridge-css-not-ready-k3s-aws.md` (same symptom, RCA never fixed); `docs/bugs/2026-10-05-sandbox-make-up-hijacks-hostinger-launchd-labels.md` (moved the other shared labels to `sandbox.*`, but not the SSH tunnel)

## Symptom

`make up CLUSTER_PROVIDER=k3s-aws` fails at Step 8/12:

    INFO: [shopping_cart] Waiting for ClusterSecretStore vault-backend to be Ready on ubuntu-k3s...
    WARN: [shopping_cart] ClusterSecretStore vault-backend not Ready after 90s (attempt 1/3) — forcing reconcile...
    ...
    ERROR: [shopping_cart] ClusterSecretStore vault-backend never became Ready after 3 attempts (270s total)

Before it, at Step 3/12, the tunnel step does nothing:

    INFO: [acg-up] Step 3/12 — Starting SSH tunnel...
    [tunnel] already running

## Root cause

The sandbox and Hostinger share one pair of tunnel launchd labels: `com.k3d-manager.ssh-tunnel`
(forward `:6443`) and `com.k3d-manager.ssh-tunnel-vault` (reverse `-R 8200:127.0.0.1:18200`).
`k3s-hostinger.sh:940` sets `TUNNEL_SSH_HOST=ubuntu@<hostinger-host>` and calls `tunnel_start`,
which writes both plists for Hostinger. On 2026-10-17 at 17:54 they pointed at
`ubuntu@srv1754834.hstgr.cloud`.

The sandbox calls `tunnel_start` with `TUNNEL_SSH_HOST=ubuntu` (the `~/.ssh/config` alias for the
sandbox server). `tunnel_start` returns early when three checks pass:

- `_tunnel_is_running` runs `pgrep -f "autossh.*ubuntu"`, a substring match. Hostinger's
  `autossh ... -N ubuntu@srv1754834.hstgr.cloud` matches it.
- `_tunnel_plist_has_reverse` is false, because the main plist has no `-R`.
- `_tunnel_vault_launchd_loaded` is true, because Hostinger's reverse agent is loaded.

So the sandbox gets no reverse tunnel. `vault-bridge` on the sandbox server (socat `:8201` →
`localhost:8200`) forwards to a port that nothing listens on, and ESO's `vault-backend` store
cannot reach Vault.

Fixing only the match would not help. With an exact host match, `tunnel_start` would rewrite the
shared plists to `ubuntu`. That takes Hostinger's Vault reverse tunnel away, so Hostinger's ESO
loses Vault, and `make down` (`tunnel_stop`) would later unload Hostinger's agents. The labels
have to be separate.

Confirmed from the code and the launchd state after the run; not reproduced. An earlier sandbox
`make up` on 2026-10-17 succeeded. That was probably because the sandbox wrote the shared plists
after Hostinger's last refresh, which would have taken Hostinger's tunnel at the time. This is not
verified; no log from that run was checked.

## Fix (direction; the dispatch spec gives exact code)

- When the sandbox runs `tunnel_start`/`tunnel_stop` (k3s-aws up, down and refresh), it uses its own
  labels and paths: `com.k3d-manager.sandbox.ssh-tunnel` and
  `com.k3d-manager.sandbox.ssh-tunnel-vault`, set through the existing `TUNNEL_LAUNCHD_LABEL`,
  `TUNNEL_PLIST_PATH`, `TUNNEL_VAULT_LAUNCHD_LABEL`, `TUNNEL_VAULT_PLIST_PATH` and
  `TUNNEL_VAULT_WRAPPER_PATH`. Hostinger keeps the unscoped labels.
- `_tunnel_is_running` matches the ssh destination exactly, as a whole argument, not as a substring.
- A sandbox teardown unloads only the `sandbox.*` tunnel agents.
- The sandbox forward tunnel binds a local port other than Hostinger's `0.0.0.0:6443`, or the
  sandbox keeps reaching the API on the server's public IP, as it does today (`ubuntu-k3s` points
  at `35.163.58.221:6443`). The spec settles which one.

## Acceptance

```yaml
must:
  - id: M1
    text: With Hostinger's tunnel agents loaded and pointing at ubuntu@<hostinger-host>, a k3s-aws tunnel_start installs and loads com.k3d-manager.sandbox.ssh-tunnel and com.k3d-manager.sandbox.ssh-tunnel-vault, whose ssh destination is the sandbox alias (ubuntu) and whose reverse forward is -R 8200:127.0.0.1:18200.
  - id: M2
    text: _tunnel_is_running is true only for an autossh whose destination argument equals TUNNEL_SSH_HOST; ubuntu does not match ubuntu@srv1754834.hstgr.cloud.
  - id: M3
    text: A k3s-aws teardown (bin/cluster-down, keep-hub and delete-hub) unloads and removes the sandbox.* tunnel agents.
  - id: M4
    text: A k3s-hostinger refresh still installs and uses the unscoped com.k3d-manager.ssh-tunnel and ssh-tunnel-vault labels.
must_not:
  - id: N1
    text: A k3s-aws tunnel_start must not print "already running" or return early because a Hostinger autossh is running (red on pre-fix, where pgrep "autossh.*ubuntu" matches it).
  - id: N2
    text: A k3s-aws tunnel_start, tunnel_stop or teardown must not write, unload or remove com.k3d-manager.ssh-tunnel, com.k3d-manager.ssh-tunnel-vault or their plists and wrapper (red on pre-fix once N1 no longer returns early).
  - id: N3
    text: A k3s-hostinger refresh must not touch the sandbox.* tunnel agents.
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2, N3]
    kind: offline
    text: BATS in scripts/tests/plugins/tunnel.bats (and cluster_down where teardown is covered) with launchctl, pgrep, ssh and autossh stubbed, recording every launchctl, plist write and rm; a stubbed pgrep process list that holds Hostinger's autossh command line; N1 red on pre-fix.
  - id: E2
    proves: [M1, N1, N2]
    kind: live
    text: Claude, after the operator's next make up CLUSTER_PROVIDER=k3s-aws with Hostinger up — Step 8 passes (vault-backend Ready on ubuntu-k3s), launchctl shows both sandbox.* tunnel agents, and com.k3d-manager.ssh-tunnel-vault still runs ssh to the Hostinger host.
  - id: E3
    proves: [M3, N2]
    kind: live
    text: Claude, after the following make down CLUSTER_PROVIDER=k3s-aws KEEP_LOCAL=1 — no sandbox.* tunnel agent is loaded, and Hostinger's two tunnel agents are still loaded with the same PIDs as before.
interface:
  - scripts/plugins/tunnel.sh tunnel_start, tunnel_stop, _tunnel_is_running and the TUNNEL_* label and path variables
  - bin/cluster-up Step 3 (k3s-aws), bin/cluster-down --confirm [--keep-hub|--delete-hub], bin/cluster-refresh (k3s-aws, k3s-hostinger)
  - launchd labels com.k3d-manager.ssh-tunnel, com.k3d-manager.ssh-tunnel-vault, com.k3d-manager.sandbox.ssh-tunnel, com.k3d-manager.sandbox.ssh-tunnel-vault
```
