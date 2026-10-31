# Bug: hub-cutover leaves producers on the old hub pushing to the old hub's Pushgateway and Loki

**Status:** FIXED
**Priority:** P2
**Approval:** operator, 2026-10-30 ("can you dispatch code fix hub-cutover should move metrics forwarding on its own and fix the make platform-ops outdate message?")
**Filed:** 2026-10-30
**Detected by:** Claude, during the M4 → M5 cutover Grafana audit (389 panel queries compared on both hubs)
**Affected:** `bin/hub-cutover`; `Makefile` (`hub-cutover`, `hub-cutover-rollback`); `scripts/plugins/argocd.sh` (`deploy_argocd_platform_ops` closing message)
**Branch:** `k3d-manager-v1.43.12`
**Related:** `docs/plans/v1.43.12-hub-cutover-hostinger-handoff.md`

## Observed failure

After `make hub-cutover` passed on the M5, these Grafana dashboards were empty on the new hub: Agent
Dispatch (51 panels), Agent Cost (22), Agent Activity (19) and Agent Run Log (1). The M4 Pushgateway held 8,985
`k3dm-dispatch` series; the M5 held none.

Producers that still run on the old hub (`bin/k3dm-codex-dispatch`, `bin/k3dm-dispatch-metrics`,
`bin/k3dm-dispatch-logs`, the test metrics, `scripts/lib/deployment_metrics.sh`) write to
`http://localhost:19094` (Pushgateway) and `http://localhost:19100` (Loki). On the old hub those ports are
the LaunchAgents `com.k3d-manager.hub-pushgateway-port-forward` and `com.k3d-manager.hub-loki-port-forward`,
which run `kubectl port-forward ... --context k3d-k3d-cluster` against the old hub's **own** cluster
(captured from the M4 plist, 2026-10-30). The cutover moves the singletons but never touches these
forwards, so every push from the old hub keeps landing on a hub nobody reads, and stops entirely once the
old cluster is stopped.

The new hub's own forwards listen on loopback only (`127.0.0.1:19094` and `127.0.0.1:19100` on the M5,
captured with `lsof` 2026-10-30), so the old hub cannot reach them directly.

A second, smaller defect: `deploy_argocd_platform_ops` ends with
`platform-ops deployed — CVE scan: 1st+15th, expiry check: every 30m`. The CronJobs actually run daily:
`app-cve-scan` at `0 1 * * *` and `argocd-cve-scan` at `30 1 * * *` (America/Los_Angeles), as set in
`scripts/etc/argocd/platform-ops/`. The next line asks the operator to create `oci-kubeconfig` by hand,
but OCI was dropped from the project, so that instruction is stale as well.

## Fix

1. **Re-point the old hub's push forwards.** After `verify_with_retries` passes, `bin/hub-cutover`
   replaces the old hub's `com.k3d-manager.hub-pushgateway-port-forward` (port 19094) and
   `com.k3d-manager.hub-loki-port-forward` (port 19100) with SSH local forwards to the same loopback ports on
   the new hub. Keep the label names, so producers need no change.
   - The ports come from a new list, `scripts/etc/machine/hub-push-forwards.list`, in the format
     `label|port|note`.
   - The new host is `HUB_NEW_HOST`, which defaults to `$(scutil --get LocalHostName).local`.
   - Run each tunnel as `/usr/bin/ssh -N -o BatchMode=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -L 127.0.0.1:<port>:127.0.0.1:<port> <new-host>`, with `KeepAlive` true and the same log path as the plist it replaces.
   - **Before** changing anything, check from the old host that `ssh -o BatchMode=yes -o ConnectTimeout=10 <new-host> true` succeeds. If it fails, change nothing, print how to set up key login from the old host to the new one, append report row `forwards-skipped` and exit 1. The cutover itself has already passed at this point.
   - Back up each original old-host plist as `<label>.plist.pre-cutover` (never overwrite an existing backup), write the tunnel plist, then `bootout` and `bootstrap` it.
   - Check on the old host that `curl -s -m 10 http://127.0.0.1:19094/-/ready` returns `OK` and `curl -s -m 10 http://127.0.0.1:19100/` returns `OK`. Both bodies were captured from the M5 hub on 2026-10-30 through the service proxy. If they pass, append `forwards-pass`. If not, append `forwards-failed`, say the cutover itself passed, and exit 1.
2. **Standalone mode.** Add `bin/hub-cutover --forwards` and `make hub-cutover-forwards`. They run step 1 alone, for a cutover that has already happened (today's M4 → M5). They refuse unless the last row of `hub-cutover-report.json` has `verify` = `pass`, `forwards-failed` or `forwards-skipped`, and ask for the confirmation word `forwards`.
3. **Rollback restores the forwards.** `--rollback` puts back every `<label>.plist.pre-cutover` on the old host (move it back over the tunnel plist, then `bootout` and `bootstrap`), before it reloads the singletons. If there is no backup, the forwards were never re-pointed and rollback leaves them alone.
4. **Message.** Replace the closing line with `platform-ops deployed — app CVE scan daily 01:00, ArgoCD CVE scan daily 01:30 (America/Los_Angeles), expiry check every 30m, remediation verify every 15m`, and remove the two `oci-kubeconfig` lines.

## Files

- `bin/hub-cutover`
- `scripts/etc/machine/hub-push-forwards.list` (new)
- `Makefile` (`hub-cutover-forwards` target, `.PHONY`, help line)
- `scripts/plugins/argocd.sh` (the closing message lines only)
- `scripts/tests/bin/hub_cutover.bats`
- `scripts/tests/plugins/argocd_platform_ops_message.bats` (new; no existing test asserts the message)
- `docs/howto/machine-setup.md` (new section "After the cutover: old-hub forwards"): document the forward re-point, `make hub-cutover-forwards`, and the rollback behaviour
- `CHANGELOG.md` `[Unreleased]`

## Acceptance

```yaml
must:
  - id: M1
    text: after a passing cutover, the old host's hub-pushgateway-port-forward and hub-loki-port-forward plists run /usr/bin/ssh -N with -L 127.0.0.1:19094:127.0.0.1:19094 and -L 127.0.0.1:19100:127.0.0.1:19100 to HUB_NEW_HOST, with BatchMode=yes and ExitOnForwardFailure=yes
  - id: M2
    text: each original old-host plist is kept as <label>.plist.pre-cutover before it is replaced, and an existing backup is never overwritten
  - id: M3
    text: the report gets forwards-pass only when both old-host ready probes return OK; otherwise forwards-failed and exit 1
  - id: M4
    text: bin/hub-cutover --forwards (make hub-cutover-forwards) performs only the re-point, after the confirmation word "forwards", and refuses unless the last report row's verify is pass, forwards-failed or forwards-skipped
  - id: M5
    text: --rollback restores every .pre-cutover plist on the old host (bootout then bootstrap) before reloading singletons
  - id: M6
    text: deploy_argocd_platform_ops prints "app CVE scan daily 01:00" and "ArgoCD CVE scan daily 01:30"
must_not:
  - id: N1
    text: when the old host cannot ssh to the new host in batch mode, no old-host plist is written, moved, booted out or bootstrapped; report row forwards-skipped
  - id: N2
    text: a failed forward re-point never runs rollback, never touches the ArgoCD controllers, and never unloads the new hub's singletons
  - id: N3
    text: deploy_argocd_platform_ops no longer prints "1st+15th" or "oci-kubeconfig"
  - id: N4
    text: --forwards refuses (exit 1, nothing on the old host changed) when the last report row is verify-failed or when no report exists
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    text: BATS in scripts/tests/bin/hub_cutover.bats with ssh/scp/launchctl/curl stubs, scratch HOME and state dirs; the fixture first asserts HOME and the state dir are scratch paths
  - id: E2
    proves: [M4, N4, M5]
    kind: offline
    text: BATS for --forwards gating and rollback restore order
  - id: E3
    proves: [M6, N3]
    kind: offline
    text: BATS asserting on the platform-ops closing message tokens
  - id: E4
    proves: [M1, M3]
    kind: live
    text: operator runs make hub-cutover-forwards on the M5; Claude confirms a k3dm-dispatch push from the M4 appears in the M5 Prometheus
interface:
  - bin/hub-cutover (default mode, --forwards, --rollback)
  - make hub-cutover-forwards
  - env HUB_OLD_HOST, HUB_NEW_HOST, HUB_CUTOVER_STATE_DIR, HUB_NEW_STATE_DIR, HUB_CUTOVER_TTY
  - scripts/etc/machine/hub-push-forwards.list
  - deploy_argocd_platform_ops stdout
```

Test controls: N1 is paired with M1 (the same fixture with the batch ssh probe succeeding writes the
plists). Pair each refusal test with a passing positive control. Stub `ssh`/`curl` output comes from the
captures named above: `OK` from Pushgateway `/-/ready`, `OK` from loki-gateway `/`.

## What NOT to do

- Do not make the new hub's forwards listen beyond loopback, and do not expose the Pushgateway or Loki on the LAN.
- Do not change producer URLs (`localhost:19094`, `localhost:19100`).
- Do not create a PR, skip hooks, commit to `main`, or modify files outside the list above.

## Resolution (2026-10-31)

- **Fix:** `8765c128` (re-point old-hub push forwards to the new hub; Luna, with Claude's `forwards_ready` readiness retry), followed by the reload-race fix in `2d68e533` (`docs/bugs/2026-10-31-hub-port-forward-reload-race-and-hub-migrate-entrypoint.md`).
- **E1–E3 (offline):** `scripts/tests/bin/hub_cutover.bats` 31/31 green at landing, shellcheck clean; the readiness and reload tests were red on the earlier script.
- **E4 (live, 2026-10-31):** after the operator ran `make hub-cutover-forwards`, the M5 Pushgateway held 112 `k3dm-dispatch` series naming a task slug that only exists on the M4. A fresh M4 push at 12:11:45Z landed on the M5 while the M4 Pushgateway stayed at 11:39:30Z. The only listener on M4 :19094 is the tunnel ssh to `m5-air.local`.
