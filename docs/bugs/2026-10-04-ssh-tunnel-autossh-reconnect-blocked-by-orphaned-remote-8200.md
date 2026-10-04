# Bug: the hub-to-sandbox SSH tunnel cannot reconnect while an orphaned sandbox sshd holds port 8200

**Filed:** 2026-10-04, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** OPEN. Recovery is manual; no fix spec yet.
**Severity:** high while it lasts. The hub ArgoCD loses `ubuntu-k3s` (`host.k3d.internal:6443`), so
no sandbox app can sync, and nothing heals by itself.

## Observed (about 02:40 UTC)

- The LaunchAgent `com.k3d-manager.ssh-tunnel` runs
  `autossh -M 0 ... -o ExitOnForwardFailure=yes -L 0.0.0.0:6443:localhost:6443 -R 8200:127.0.0.1:18200 -N ubuntu`.
- `/tmp/k3d-manager-tunnel.err` shows `client_loop: send disconnect: Broken pipe` at about 19:38 PDT,
  which is when k3s on the sandbox was restarted. After that it shows repeated
  `Error: remote port forwarding failed for listen port 8200`.
- autossh (PID 35898) is alive but has no ssh child, and nothing on the Mac listens on 6443.
- On the sandbox, `127.0.0.1:8200` and `[::1]:8200` are still LISTEN. The old session from
  02:23:53Z (sshd PID 51046, the autossh start time) is still attached to the client's previous
  public IP, with a send queue of 273 KB that is never drained. The client side is gone, but sshd
  has not noticed, so it keeps the remote forward bound.
- Hub ArgoCD `acg-kube-prometheus-stack`: `read: connection reset by peer` on
  `host.k3d.internal:6443`. `make fix-sync` failed with every resource `Unknown/Missing`.

## Root cause

`ExitOnForwardFailure=yes` combined with a remote forward. When the client drops without a clean
close, the server sshd keeps the session, and so `-R 8200`, until TCP gives up. sshd has no
`ClientAliveInterval`, so that takes hours. Every autossh retry then fails on 8200, and the `-L 6443`
forward that ArgoCD depends on never comes back.

## Manual recovery

The operator kills the orphaned sandbox sshd, then kickstarts the agent:
`ssh ubuntu kill 51046 && launchctl kickstart -k gui/$(id -u)/com.k3d-manager.ssh-tunnel`

## Fix options (to decide)

1. Add `-o ClientAliveInterval=30 -o ClientAliveCountMax=3` on the sandbox sshd (cloud-init or
   `cluster-up`), so the server drops dead sessions in about 90 s.
2. Before (re)starting the tunnel, kill any sandbox sshd that holds 8200
   (`fuser -k 8200/tcp` as ubuntu).
3. Split the `-R 8200` forward into its own autossh agent, so a stuck remote forward can no
   longer take down the `-L 6443` ArgoCD path.
