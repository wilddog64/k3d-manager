# Bug: node-health-watch restarts a healthy agent when the host cannot reach the API

**Branch:** `k3d-manager-v1.33.0`
**Filed:** 2026-09-13
**Status:** FIXED `2eb9c7cf` + comment placement `c7ee484e` (Codex; Claude verified) — operator kickstart pending
**Files:** `bin/k3dm-node-health-watch`, `scripts/tests/bin/node_health_watch.bats`, `CHANGELOG.md`
**Parent incident:** `2026-09-13-hub-orbstack-restart-serverlb-empty-config.md` (Defect 2)
**Related:** `2026-08-28-node-health-watch-restart-loop-slow-node.md`

## Problem

`_ready` runs `kubectl --context k3d-k3d-cluster get node <agent>` from the Mac. Any failure counts as `NotReady`, including the host never reaching the API server. On 2026-09-13 the k3d serverlb had no upstreams, so every host `kubectl` call got `EOF`. The watchdog counted 5 "NotReady" results and ran `docker restart k3d-k3d-cluster-agent-0`. It logged `did not recover within 100s` and repeated about every 6 minutes. Inside the cluster, agent-0 was Ready the whole time. Each restart evicted agent-0's pods and broke ambient redirection for no benefit.

The 2026-08-28 fix already made a slow `/healthz` advisory-only. "API unreachable" is the remaining false positive.

## Fix

Before a NotReady result counts toward the threshold, confirm the API server answers `/readyz` from the host.

- API unreachable → the node's state is unknown. Log an advisory, reset the failure counter, and never restart.
- API reachable and node Ready != True → counts toward the threshold, exactly as today.

Also move the loop body into `_tick` and run the loop only when the script is executed, not sourced. BATS can then drive `_tick` with stubbed `kubectl`/`docker`. Replace the two existing whole-line `grep -F` tests with behavioral tests.

### S1 — `bin/k3dm-node-health-watch`

Old (lines 61–75, from `failures=0` to the end of the file):

```bash
failures=0
while :; do
  if _ready; then
    failures=0
    _healthy || _log "${node} Ready but /healthz slow/unreachable (advisory, no restart)"
  else
    failures=$((failures + 1))
    _log "${node} NotReady (${failures}/${threshold})"
    if (( failures >= threshold )); then
      _recover || true
      failures=0
    fi
  fi
  sleep "$interval"
done
```

New:

```bash
_api_reachable() {
  kubectl --context "$context" get --raw /readyz \
    --request-timeout=5s 2>/dev/null | grep -qx 'ok'
}

failures=0

_tick() {
  if _ready; then
    failures=0
    _healthy || _log "${node} Ready but /healthz slow/unreachable (advisory, no restart)"
  elif ! _api_reachable; then
    failures=0
    _log "API server unreachable from host via ${context}; ${node} state unknown (advisory, no restart)"
  else
    failures=$((failures + 1))
    _log "${node} NotReady (${failures}/${threshold})"
    if (( failures >= threshold )); then
      _recover || true
      failures=0
    fi
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  while :; do
    _tick
    sleep "$interval"
  done
fi
```

In the header comment block (lines 2–7), after the sentence ending `adds load).`, add this sentence on its own comment line:

```bash
# An unreachable API server (e.g. a broken k3d serverlb) is also advisory only: the node's state is unknown, so no restart.
```

Change nothing else. `_healthy`, `_ready`, `_recover`, the variables and the `mkdir -p` stay as they are.

## Tests — `scripts/tests/bin/node_health_watch.bats`

Replace the whole file. Do not keep the two `grep -F` tests.

In `setup()`, use `BATS_TEST_TMPDIR`:
- Export `K3DM_NODE_RECOVERY_LOG`, `K3DM_NODE_RECOVERY_STATE`, `K3DM_NODE_RECOVERY_ENABLED=1`, `K3DM_NODE_RECOVERY_FAILURE_THRESHOLD=2`, `K3DM_NODE_RECOVERY_COOLDOWN=0`, `K3DM_NODE_RECOVERY_NODE=agent-x` and `K3DM_NODE_RECOVERY_CONTEXT=ctx-x`.
- Set up stub state files:
  - `READY_FILE`: content `True` or `False`.
  - `READYZ_FILE`: content `ok` or empty.
  - `CONTAINER_STATE_FILE`: content `running`.
  - `DOCKER_CALLS`: empty.
- Define shell functions:
  - `kubectl`:
    - `*"get --raw /readyz"*` → `cat "$READYZ_FILE"`, returning 1 when the file is empty.
    - `*"get node"*` → `cat "$READY_FILE"`.
    - `*"/proxy/healthz"*` → `echo ok`.
  - `docker`:
    - `inspect` → `cat "$CONTAINER_STATE_FILE"`.
    - `restart|start` → append `"$1 $2"` to `DOCKER_CALLS` and write `True` to `READY_FILE`.
  - `sleep() { :; }`
- Then `source "${BATS_TEST_DIRNAME}/../../../bin/k3dm-node-health-watch"`.

Sourcing must not enter the loop. Test 6 proves it.

Tests. Call `_tick` directly, not through `run`, so `failures` persists between calls:

1. `node health watchdog: Ready node resets failures and never restarts`
   - READY=True; `_tick` ×3.
   - `failures` is 0 and `DOCKER_CALLS` is empty.
2. `node health watchdog: NotReady with reachable API restarts after threshold`
   - READY=False, READYZ=ok; `_tick` ×2.
   - `DOCKER_CALLS` contains exactly `restart agent-x`; the log contains `NotReady (2/2)`.
3. `node health watchdog: unreachable API never restarts the agent`
   - READY=False, READYZ empty; `_tick` ×5.
   - `DOCKER_CALLS` is empty, `failures` is 0, and the log contains `API server unreachable from host via ctx-x`.
4. `node health watchdog: an unreachable API interval resets the NotReady streak`
   - READY=False: `_tick` with READYZ=ok, then with READYZ empty, then with READYZ=ok.
   - `DOCKER_CALLS` is empty and `failures` is 1.
5. `node health watchdog: starts an exited agent instead of restarting it`
   - CONTAINER_STATE=exited, READY=False, READYZ=ok; `_tick` ×2.
   - `DOCKER_CALLS` contains `start agent-x`.
6. `node health watchdog: sourcing does not enter the loop and keeps bounded defaults`
   - `run bash -c` with `HOME="$BATS_TEST_TMPDIR"`, and with `K3DM_NODE_RECOVERY_FAILURE_THRESHOLD`, `K3DM_NODE_RECOVERY_COOLDOWN` and `K3DM_NODE_RECOVERY_INTERVAL` unset.
   - The command sources the script, then prints `"$threshold $cooldown"`.
   - Wrap it in `timeout 10` if available, otherwise run it plainly.
   - Assert status 0 and output `5 300`.

Keep assertions on meaningful tokens, never on whole source lines.

## CHANGELOG

Under `## [Unreleased]` → `### Fixed`, add as the first bullet:

```
- `bin/k3dm-node-health-watch` no longer restarts a healthy agent when the host cannot reach the API server (e.g. a broken k3d serverlb): a NotReady result only counts toward the restart threshold when `/readyz` answers, otherwise it logs an advisory and resets the streak
```

## Definition of Done

- [ ] S1 applied exactly; no other lines in `bin/k3dm-node-health-watch` changed.
- [ ] `shellcheck bin/k3dm-node-health-watch`: no new warnings versus the pre-change file (paste both counts).
- [ ] `bats scripts/tests/bin/node_health_watch.bats`: all 6 pass (paste summary).
- [ ] CHANGELOG bullet added.
- [ ] Commit message, verbatim: `fix(node-health-watch): never restart an agent when the host cannot reach the API server`
- [ ] Pushed; `git rev-parse origin/k3d-manager-v1.33.0` equals the commit SHA.

## Operator step after merge to the branch (NOT for Codex)

The launchd agent runs the script from the repo path, so it only picks up the change on restart. The user runs `launchctl kickstart -k "gui/$(id -u)/com.k3d-manager.node-health-watch"`, then checks that the log is quiet.

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`.
- Do NOT run the watchdog, `kubectl`, `docker`, or any `launchctl` command against the live system. Tests use stubs only.
- Do NOT modify files outside the three listed targets. Do NOT edit `scripts/lib/foundation/`, `scripts/lib/acg/`, `scripts/lib/system.sh`, or memory-bank.
- Do NOT change the threshold, cooldown, interval defaults, or the slow-`/healthz` advisory behavior.
- Do NOT use `grep -F` on source lines in BATS.
