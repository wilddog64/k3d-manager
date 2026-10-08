# Bug: `cleanup-stale-sandbox` stops Hostinger's Pushgateway port-forward — `TargetDown` flaps on the hub

**Filed:** 2026-10-08, Claude
**Branch:** `k3d-manager-v1.42.0`
**Status:** OPEN — fix dispatched to Codex
**Severity:** medium. Every confirmed `/cleanup-stale-sandbox` silently takes down the hub's
`k3dm-test-pushgateway` target until the next Hostinger refresh, so `k3dm_test_*` metrics go stale,
`TargetDown` fires, and the `OfflineSuite*` rules on ubuntu-hostinger can fire on stale data.
**Related:** `docs/bugs/2026-10-07-slack-stale-sandbox-cleanup-misleading-reporting.md` (same
command, different defect — its reporting), `docs/bugs/2026-10-06-k3dm-tests-dashboard-no-data.md`
(introduced the `host.internal:9091` scrape).

## Observed (2026-10-07 → 2026-10-08)

Hub `up{job="k3dm-test-pushgateway"}` (target `host.internal:9091`), against the webhook audit log
(`~/.local/share/k3d-manager/audit/remote-operator.jsonl`, action `cleanup-stale-sandbox`):

| `/cleanup-stale-sandbox` | target down | target back |
|---|---|---|
| 2026-10-07 17:13Z (confirmed in-thread) | 17:44Z | 22:50Z (next Hostinger refresh) |
| 2026-10-08 01:03:08Z | 01:04Z | 03:12Z (next Hostinger refresh) |
| 2026-10-08 15:31:01Z | 15:32Z | still down at 22:47Z |

At 22:47Z nothing listened on `:9091`; `launchctl print gui/501/com.k3d-manager.pushgateway-port-forward`
→ `Could not find service`; `~/Library/LaunchAgents/com.k3d-manager.pushgateway-port-forward.plist`
was gone while its `.sh` wrapper remained. The wrapper log
(`~/.local/share/k3d-manager/logs/pushgateway-pf.log`) has no "health check failed" line before any
gap — the whole wrapper was killed, not just the inner `kubectl`.

## Root cause

`bin/cleanup-stale-sandbox:19` boots out and deletes
`com.k3d-manager.pushgateway-port-forward`. That unscoped label is now **Hostinger's** forwarder
(`scripts/lib/providers/k3s-hostinger.sh:618`, `9091 → ubuntu-hostinger svc/prometheus-pushgateway`).
The sandbox's own forwarder was renamed to `com.k3d-manager.sandbox.pushgateway-port-forward`
(`bin/cluster-up:1984`, `9092:9091`), and `bin/cluster-down:331` already leaves the unscoped label in
place as "belongs to another provider". `cleanup-stale-sandbox` was never updated.

`com.k3d-manager.frontend-port-forward` in the same list is correct — it is the sandbox's
(`bin/cluster-up:1773`).

## Fix

### 1. `bin/cleanup-stale-sandbox` line 19

Old:

```bash
agents=(com.k3d-manager.frontend-port-forward com.k3d-manager.pushgateway-port-forward)
```

New:

```bash
agents=(com.k3d-manager.frontend-port-forward com.k3d-manager.sandbox.pushgateway-port-forward)
```

### 2. `scripts/tests/bin/cleanup_stale_sandbox.bats`

- Make the fake `launchctl` append its arguments to `"${BATS_TEST_TMPDIR}/launchctl.log"` before its
  existing exit logic.
- Add a test `cleanup-stale-sandbox never touches the Hostinger pushgateway agent`: create both
  `com.k3d-manager.pushgateway-port-forward.plist` and
  `com.k3d-manager.sandbox.pushgateway-port-forward.plist` under the fake `LaunchAgents`, run
  `--apply`, then assert:
  - status 0;
  - the unscoped `com.k3d-manager.pushgateway-port-forward.plist` still exists;
  - the sandbox plist is removed;
  - `launchctl.log` contains `bootout gui/` + `com.k3d-manager.sandbox.pushgateway-port-forward`;
  - `launchctl.log` does **not** contain the exact token `/com.k3d-manager.pushgateway-port-forward`
    (use `run grep -F ...` then `[ "$status" -ne 0 ]` — never a bare `! grep`).
- RED check: run the new test against `git show HEAD:bin/cleanup-stale-sandbox` in a temp copy; it
  must fail.

### 3. `scripts/tests/bin/ask_bash_scope.bats` — false-green OS-sandbox test (from `b2c45ae3`)

`Darwin OS sandbox denies an allowed-looking HOME read` sets `K3DM_REPO_ROOT="$TEST_HOME"`, so the
profile's repo allow-rule covers the entire fake HOME and the canary is readable (rc 0) on a normal
Mac. It only passed inside Codex's own sandbox, where the nested `sandbox-exec` fails. Rewrite it so
Layer A passes and only Layer B can deny:

- keep `K3DM_REPO_ROOT="$TEST_REPO"` (outside `TEST_HOME`);
- write `"$TEST_REPO/reader.sh"` containing `#!/bin/bash` and `cat "$TEST_OUTSIDE/canary"`;
- `K3DM_ASK_OS_SANDBOX=1 ask_bash -c "bash $TEST_REPO/reader.sh"` → `assert_denied_without_canary`;
- add the control: the same call with `K3DM_ASK_OS_SANDBOX=0` → status 0 and output contains
  `HARMLESS_CANARY` (proves the denial is the OS sandbox, not Layer A).

Verified manually 2026-10-08: sandbox=1 → `cat: …: Operation not permitted`, rc 1; sandbox=0 →
canary printed, rc 0.

## Operator recovery (until merged)

`make refresh-edge CLUSTER_PROVIDER=k3s-hostinger` rewrites and reloads the Hostinger agents
(cloudflared restarts too — a few seconds of tunnel blip). Run it after any confirmed
`/cleanup-stale-sandbox` until this fix is deployed.
