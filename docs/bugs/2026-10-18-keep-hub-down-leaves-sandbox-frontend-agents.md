# Bug: a keep-hub sandbox `make down` leaves the sandbox frontend port-forward crash-looping and its browser listener daemon running

**Filed:** 2026-10-18 (Claude, while checking E3 of `docs/bugs/2026-10-17-make-down-keep-hub-leaves-sandbox-pushgateway-forward.md`)
**Status:** LIVE-VERIFIED — 2026-10-18: Part B of `17c7cda5`; independent verifier PASSED (frontend 7/7 post-fix, pre-fix must_not reds confirmed); E2 live after the operator's `make down CLUSTER_PROVIDER=k3s-aws KEEP_LOCAL=1` at 19:32 PDT 2026-10-17: `Frontend port-forward LaunchAgent unloaded`, no `com.k3d-manager.frontend-port-forward` in `launchctl list`, `sandbox.frontend-browser-http` unloaded with its plist gone (no warning needed), and the hub and Hostinger agents still loaded
**Fix commit:** 17c7cda5
**Live evidence:** 2026-10-18 · run sandbox-down-keep-local-1932-pdt · env acg/ubuntu-k3s+hostinger · scenario cluster-down/keep-hub-frontend-agents · commit f35353cd · proves E2
**Priority:** P3 — leftover laptop processes; the hub and Hostinger are not affected
**Severity:** low
**Approval:** approved — operator, 2026-10-18: "1. go ahead 2. yes" (fixed in the same Codex run as Part B of `2026-10-18-sandbox-tunnel-start-mistakes-hostinger-tunnel-for-its-own.md`, which holds the exact code)
**Release:** v1.43.4 (bug; exempt from the plan cap)
**Component:** `bin/cluster-down` (frontend port-forward and frontend browser listener cleanup), `bin/cluster-up` Step 10g.10
**Related:** `docs/bugs/2026-10-17-make-down-keep-hub-leaves-sandbox-pushgateway-forward.md`. Its Fix says that agents whose program targets `ubuntu-k3s` are cleaned up too, but its Acceptance only tested `sandbox.pushgateway-port-forward`.

## Symptom

After `make down CLUSTER_PROVIDER=k3s-aws KEEP_LOCAL=1` (2026-10-17 18:39 PDT, which reported "Done. Remote cluster deleted; local Hub preserved."):

- The LaunchAgent `com.k3d-manager.frontend-port-forward` is still loaded. Its program is
  `kubectl port-forward svc/frontend --namespace shopping-cart-apps --context ubuntu-k3s 3000:80`.
  The context is gone, so it exits 1 and launchd restarts it: `runs = 642`. Its log
  `~/.local/share/k3d-manager/k3s-aws/logs/frontend-pf.log` keeps growing with
  `dial tcp 35.163.58.221:6443: connect: operation timed out`.
- The LaunchDaemon `com.k3d-manager.sandbox.frontend-browser-http` is still `state = running`, and
  its plist is still in `/Library/LaunchDaemons/`. Its wrapper script was deleted. The down log
  `frontend-browser-http-launchctl.log` reads `Boot-out failed: 1: Operation not permitted`.

## Root cause

- **Frontend port-forward.** `cluster-up` installs it as a KeepAlive LaunchAgent with an unscoped
  label (Step 10g.10). `cluster-down` "Stopping frontend port-forward" only kills the PID in
  `run/frontend-pf.pid`; it never boots out the agent or removes its plist.
  `bin/cleanup-stale-sandbox` lists the label, so only that path removes it.
- **Browser listener daemon.** The run was in a TTY, so the headless guard did not skip.
  `_run_command --prefer-sudo --soft -- launchctl bootout system …` ran without sudo, because no
  sudo credential was cached, and failed. The `rm -f` of the plist ran the same way and failed
  silently. The step reports nothing, so the teardown looks clean.

## Fix (direction)

- `cluster-down` (k3s-aws, keep-hub and delete-hub) boots out and removes
  `com.k3d-manager.frontend-port-forward`, but only when its plist targets `--context ubuntu-k3s`.
  It follows the same scoping rule as the legacy pushgateway plist check at `bin/cluster-down:369`.
- When the daemon bootout fails, `cluster-down` warns, naming the label and the operator command
  to run, and does not report the daemon as stopped.

## Acceptance

```yaml
must:
  - id: M1
    text: A k3s-aws cluster-down (keep-hub and delete-hub) boots out and removes com.k3d-manager.frontend-port-forward when its plist contains --context ubuntu-k3s.
  - id: M2
    text: When com.k3d-manager.sandbox.frontend-browser-http's plist is still installed after cluster-down's bootout and removal (for example the bootout fails with Operation not permitted), cluster-down prints a warning naming the label and the sudo commands that remove it.
must_not:
  - id: N1
    text: A keep-hub teardown must not leave com.k3d-manager.frontend-port-forward loaded when it targets ubuntu-k3s (red on pre-fix bin/cluster-down).
  - id: N2
    text: cluster-down must not boot out or remove com.k3d-manager.frontend-port-forward when its plist targets a context other than ubuntu-k3s.
  - id: N3
    text: A daemon left installed after a failed bootout must not be silent (red on pre-fix, which prints no warning).
evidence:
  - id: E1
    proves: [M1, M2, N1, N2, N3]
    kind: offline
    text: BATS for bin/cluster-down with launchctl, sudo and kubectl stubbed, recording every launchctl and rm call; a bootout stub that fails with "Operation not permitted"; N1 and N3 red on pre-fix.
  - id: E2
    proves: [M1, N1]
    kind: live
    text: Claude, after the operator's next make down CLUSTER_PROVIDER=k3s-aws KEEP_LOCAL=1 — launchctl list has no com.k3d-manager.frontend-port-forward, and the hub/Hostinger agents are still loaded.
interface:
  - bin/cluster-down --confirm [--keep-hub|--delete-hub] (CLUSTER_PROVIDER=k3s-aws)
  - launchd labels com.k3d-manager.frontend-port-forward (gui), com.k3d-manager.sandbox.frontend-browser-http (system)
```
