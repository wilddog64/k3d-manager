# Bug: sandbox `make up` Step 4 kills Hostinger's Vault reverse tunnel while freeing port 18200

**Filed:** 2026-10-18 (Claude, during live E2 of `2026-10-18-sandbox-tunnel-start-mistakes-hostinger-tunnel-for-its-own.md`)
**Status:** OPEN
**Priority:** P3 — Hostinger's Vault path drops for under a second and launchd restarts it; no workaround needed
**Severity:** low
**Approval:** pending — not yet put to the operator
**Release:** v1.43.4 (bug; exempt from the plan cap)
**Component:** `bin/cluster-up` Step 4 (stale Vault port-forward cleanup)
**Related:** `docs/bugs/v1.6.5-bugfix-acg-up-vault-pf-stale-port.md` (introduced the `lsof -ti` kill to clear a stale kubectl; did not consider other sockets on the port)

## Symptom

`make up CLUSTER_PROVIDER=k3s-aws` at 19:20 PDT 2026-10-17, with Hostinger up. At 19:26:40.042 launchd logged
two exits in the same millisecond:

- `gui/501/com.k3d-manager.ssh-tunnel-vault [98277]: exited due to exit(0), ran for 3377785ms`
- `gui/501/com.k3d-manager.vault-port-forward [98474]: exited due to SIGTERM`

`ssh-tunnel-vault` is Hostinger's `ssh -N … -R 8200:127.0.0.1:18200 ubuntu@srv1754834.hstgr.cloud`.
KeepAlive relaunched it at once (PID 31129, `runs = 3`); its wrapper first runs `sudo fuser -k -n tcp 8200`
on Hostinger, then reconnects. Its plist and wrapper were not rewritten (mtime 17:54), so this is not the
tunnel-scope bug.

## Root cause

Step 4 (`bin/cluster-up`, the block after "Starting Vault port-forward") frees the local Vault port with:

    _stale_vault_pf=$(lsof -ti:"${_vault_local_port}" 2>/dev/null || true)
    echo "${_stale_vault_pf}" | xargs kill 2>/dev/null || true

`lsof -ti:18200` lists every process with a socket on port 18200, not only the listener. Hostinger's
reverse-tunnel ssh holds a client connection to `127.0.0.1:18200` whenever a forwarded channel is open
(Hostinger's ESO talking to Vault), so it is killed along with the stale kubectl. Whether it is hit
depends on whether a channel is open at that moment.

## Fix (direction)

Kill only processes listening on the port: `lsof -ti:"${_vault_local_port}" -sTCP:LISTEN`.

## Acceptance

```yaml
must:
  - id: M1
    text: cluster-up's Vault port cleanup kills a process listening on TUNNEL_VAULT_LOCAL_PORT (default 18200).
must_not:
  - id: N1
    text: The cleanup must not kill a process that only holds a client connection to TUNNEL_VAULT_LOCAL_PORT, such as an ssh -R reverse tunnel with an open channel (red on pre-fix, where lsof -ti matches it).
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    text: A test that starts a real listener on a free port and a separate process connected to it, runs the cleanup with TUNNEL_VAULT_LOCAL_PORT set to that port, and shows the listener gone and the client alive; N1 red on pre-fix bin/cluster-up.
  - id: E2
    proves: [N1]
    kind: live
    text: Claude, after the operator's next make up CLUSTER_PROVIDER=k3s-aws with Hostinger up — com.k3d-manager.ssh-tunnel-vault has the same PID before and after Step 4, and launchd logs no exit for it.
interface:
  - bin/cluster-up Step 4 Vault port cleanup, with TUNNEL_VAULT_LOCAL_PORT
  - launchd label com.k3d-manager.ssh-tunnel-vault (gui)
```
