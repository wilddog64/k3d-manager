# node-health-watch never recovers a Ready node whose kubelet tunnel is dead (ArgoCD public 502)

**Filed:** 2026-10-09, Claude (operator received a `PublicEndpointDown` SMS for argocd)
**Branch:** k3d-manager-v1.42.0 (bug docs are exempt from the 5-plan cap)
**Status:** IN PROGRESS — implementation spec below dispatched to Codex 2026-10-09
**Priority:** P1 — a public endpoint stays down until a human restarts the agent
**Severity:** High
**Component:** `bin/k3dm-node-health-watch` (`_healthy`, `_tick`)
**Related:**
- `docs/issues/2026-08-19-agent0-kubelet-proxy-instability.md`: the same failure, which is why the watchdog was built.
- `docs/bugs/2026-08-28-node-health-watch-restart-loop-slow-node.md`: made `_healthy` advisory, which created this gap.
- `docs/bugs/2026-09-13-node-health-watch-restarts-on-host-api-unreachable.md`

## Symptom (2026-10-09)

1. At about 11:05 UTC, `PublicEndpointDown` fired for `https://argocd.3ai-talk.org/`.
   - Probe status 502. The other six public endpoints were at 1.
   - It was sent by SMS.
2. The argocd port-forward supervisor (`argocd-pf.log`) loops: 250+ restarts with this error:
   ```
   error dialing backend: proxy error from 127.0.0.1:6443 while dialing 192.168.97.4:10250, code 502: 502 Bad Gateway
   ```
3. On the hub nodes:
   - `kubectl get --raw /api/v1/nodes/k3d-k3d-cluster-agent-0/proxy/healthz` gives the same fast 502.
   - agent-1, agent-2 and server-0 return `ok`.
   - All four nodes are `Ready`.
   - argocd-server (`2/2 Running`) and 12 other pods are on agent-0.
4. `node-health-watch.log` noticed the failure and did nothing. Every 30s it logged:
   ```
   k3d-k3d-cluster-agent-0 Ready but /healthz slow/unreachable (advisory, no restart)
   ```
   Just before that, it logged "API server unreachable from host" lines up to 04:00 PDT. This is consistent with a host sleep or wake, after which agent-0's k3s tunnel to the server did not come back.

## Root cause

The 2026-08-28 fix correctly stopped the watchdog from restarting a node that is merely **slow**
(a healthz timeout under CPU pressure). It did that by making every `_healthy` failure advisory
while the node is Ready.

That also swallows a different failure:
- In this one, the k3s **agent tunnel** (the egress path the API server uses to reach the
  kubelet) is dead.
- It fails fast, in milliseconds, with `proxy error ... while dialing <node>:10250, code 502`.
- The node stays `Ready`, because the kubelet still heartbeats outward.
- It never heals by itself: there are 30 occurrences in the log since 2026-10-05.
- `kubectl logs`, `exec` and `port-forward` to every pod on that node fail. That is why the
  public endpoint goes down.

`_healthy` discards stderr, so it cannot tell a dead tunnel from a slow node.

## Fix (spec for Codex)

In `bin/k3dm-node-health-watch`:

1. Make `_healthy` classify its result instead of returning only true or false:
   - `ok`: the body is `ok`.
   - `tunnel`: stderr matches `proxy error from .* while dialing .*:10250, code 502`.
   - `slow`: anything else, such as a timeout or a TLS error.
2. In `_tick`, when `_ready` is true:
   - Keep `slow` advisory, unchanged (the 2026-08-28 behaviour).
   - On `tunnel`, increment a separate counter, `tunnel_failures`. Reset it on `ok` or `slow`.
   - When it reaches `K3DM_NODE_TUNNEL_THRESHOLD` (default **6**, which is 3 minutes at the 30s
     tick), call the existing `_recover`.
   - Reuse `_recover` unchanged. It already handles the cooldown, the state file,
     `docker restart`, the readiness and healthz wait, and drift reconciliation.
   - Log `"${node} Ready but kubelet tunnel dead (n/threshold)"`.
3. Keep the existing NotReady path and the API-unreachable path unchanged.

## Tests

Add BATS tests in the existing node-health-watch suite, with `kubectl` and `docker` stubbed:
- A tunnel 502 for 6 ticks leads to exactly one `docker restart`.
- A tunnel 502 for 5 ticks followed by `ok` leads to no restart.
- A `slow` healthz (timeout) for 20 ticks leads to no restart. This is the regression guard for
  2026-08-28.
- A tunnel 502 during the cooldown leads to no second restart.
- **RED:** the 6-tick tunnel test must fail on the current script. Paste the failure.

## Docs

- Add the dead-tunnel case to the watchdog's how-to or guide entry.
- CHANGELOG.

## Immediate recovery (operator, 2026-10-09)

```
docker restart k3d-k3d-cluster-agent-0
```

Then verify (Claude can run these read-only):
- agent-0 `/proxy/healthz` returns `ok`.
- The argocd port-forward log shows healthz reachable.
- `probe_success{instance="https://argocd.3ai-talk.org/"}` is 1, and the alert resolves.
  `sms-critical` has `send_resolved: false`, so no "resolved" text arrives.

## What NOT to do

- Do not make `slow` recoverable again.
- Do not lower the cooldown.
- Do not restart server-0 from this path.

## Implementation spec (Codex, 2026-10-09)

### Before You Start

- Branch: `k3d-manager-v1.42.0`. Run `git pull origin k3d-manager-v1.42.0` first. Never commit to `main`.
- Read in full: `bin/k3dm-node-health-watch`, `scripts/tests/bin/node_health_watch.bats`,
  `docs/howto/launchd-daemons.md`, and this doc.
- Targets (the only files you may change):
  1. `bin/k3dm-node-health-watch`
  2. `scripts/tests/bin/node_health_watch.bats`
  3. `docs/howto/launchd-daemons.md`
  4. `CHANGELOG.md`
  5. this bug doc (Status line only)

### Change 1 — `bin/k3dm-node-health-watch`: classify healthz

Add a config line directly after the `threshold=` line (line 16):

```bash
tunnel_threshold="${K3DM_NODE_TUNNEL_THRESHOLD:-6}"
```

Replace `_healthy` (lines 28–31) with:

```bash
_healthz_state() {
  local out
  if out="$(kubectl --context "$context" get --raw "/api/v1/nodes/${node}/proxy/healthz" \
    --request-timeout="$healthz_timeout" 2>&1)" && [[ "$out" == "ok" ]]; then
    echo ok
  elif grep -Eq 'proxy error from .* while dialing .*:10250, code 502' <<<"$out"; then
    echo tunnel
  else
    echo slow
  fi
}

_healthy() {
  [[ "$(_healthz_state)" == "ok" ]]
}
```

`_healthy` keeps its boolean contract, so `_recover` is unchanged.

### Change 2 — `bin/k3dm-node-health-watch`: tunnel counter in `_tick`

Old (lines 74–79):

```bash
failures=0

_tick() {
  if _ready; then
    failures=0
    _healthy || _log "${node} Ready but /healthz slow/unreachable (advisory, no restart)"
```

New:

```bash
failures=0
tunnel_failures=0

_tick() {
  local hz
  if _ready; then
    failures=0
    hz="$(_healthz_state)"
    case "$hz" in
      ok) tunnel_failures=0 ;;
      tunnel)
        tunnel_failures=$((tunnel_failures + 1))
        _log "${node} Ready but kubelet tunnel dead (${tunnel_failures}/${tunnel_threshold})"
        if (( tunnel_failures >= tunnel_threshold )); then
          _recover || true
          tunnel_failures=0
        fi
        ;;
      *)
        tunnel_failures=0
        _log "${node} Ready but /healthz slow/unreachable (advisory, no restart)"
        ;;
    esac
```

Leave the `elif ! _api_reachable` and `else` (NotReady) branches exactly as they are, and add
`tunnel_failures=0` as the first statement of each of those two branches (a NotReady or
API-unreachable interval breaks the tunnel streak). Update the header comment (lines 2–8) with one
added sentence: a Ready node whose kubelet tunnel fails fast with a 502 for
`K3DM_NODE_TUNNEL_THRESHOLD` consecutive ticks is recovered, because that failure never self-heals.

### Change 3 — `scripts/tests/bin/node_health_watch.bats`

In `setup()`:
- add `export HEALTHZ_FILE="$BATS_TEST_TMPDIR/healthz"` and `printf 'ok\n' >"$HEALTHZ_FILE"`;
- add `unset K3DM_NODE_TUNNEL_THRESHOLD` so the tests exercise the default of 6;
- replace the healthz stub arm `*"/proxy/healthz"*) echo ok ;;` with:

```bash
      *"/proxy/healthz"*)
        case "$(<"$HEALTHZ_FILE")" in
          ok) echo ok ;;
          tunnel) echo 'Error from server: error dialing backend: proxy error from 127.0.0.1:6443 while dialing 192.168.97.4:10250, code 502: 502 Bad Gateway' >&2; return 1 ;;
          *) echo 'Unable to connect to the server: context deadline exceeded' >&2; return 1 ;;
        esac
        ;;
```

- in the `docker` stub's `restart|start` arm, also `printf 'ok\n' >"$HEALTHZ_FILE"`.

Add these tests:
1. `node health watchdog: Ready node with dead kubelet tunnel restarts after 6 ticks` — set
   `tunnel`, `_tick` ×6, assert `$(<"$DOCKER_CALLS")` is exactly `restart agent-x`, the log contains
   `kubelet tunnel dead (6/6)`, and `tunnel_failures` is 0.
2. `node health watchdog: tunnel streak broken by ok does not restart` — `tunnel` ×5 ticks, then
   `ok` ×1, then `tunnel` ×5; assert no docker calls.
3. `node health watchdog: slow healthz on a Ready node never restarts (2026-08-28 guard)` — set
   `slow`, `_tick` ×20, assert no docker calls and `tunnel_failures` is 0.
4. `node health watchdog: tunnel failure during cooldown does not restart again` — set
   `K3DM_NODE_RECOVERY_COOLDOWN=3600` and write `$(date +%s)` into the state file **before**
   sourcing (re-source the script in the test after exporting, or set `cooldown=3600` directly);
   `tunnel` ×6 ticks; assert no docker calls and the log contains `recovery cooldown active`.

**RED gate:** before Change 1/2, run test 1 against the current script (e.g. `git stash` only the
script change, or copy the pre-change script to a temp path and point the test at it) and paste
the failing output in your report. Then show all tests green.

### Change 4 — `docs/howto/launchd-daemons.md`

Add a section `## Node health watchdog (`bin/k3dm-node-health-watch`)` before the PATH section that
states, in prose: NotReady past the failure threshold → restart; Ready but slow `/healthz` →
advisory only (never restart); Ready but dead kubelet tunnel (fast `proxy error ... :10250, code
502`) for `K3DM_NODE_TUNNEL_THRESHOLD` ticks (default 6 = 3 min) → restart via the same cooldown;
API server unreachable → advisory only. List the env knobs `K3DM_NODE_RECOVERY_*` and
`K3DM_NODE_TUNNEL_THRESHOLD`, and the log path. Link this bug doc.

### Change 5 — `CHANGELOG.md`

Under `## [Unreleased]` → `### Fixed`, first bullet: the watchdog now recovers a Ready node whose
kubelet tunnel is dead (API server 502 dialing `:10250`) after `K3DM_NODE_TUNNEL_THRESHOLD`
consecutive ticks (default 6), while a slow `/healthz` stays advisory; link this doc.

### Rules

- `shellcheck bin/k3dm-node-health-watch` — zero new warnings; paste output.
- `bats scripts/tests/bin/node_health_watch.bats` — all green; paste output.
- `bats scripts/tests/bin/launchd_plist_path.bats` — still green.
- Run `git diff --cached --stat` before committing; only the 5 target files.

### Definition of Done

- [ ] Changes 1–5 applied exactly.
- [ ] RED output for test 1 against the old script pasted.
- [ ] shellcheck + both BATS suites green, output pasted.
- [ ] This doc's Status line set to `IMPLEMENTED — <sha>; live verification pending`.
- [ ] One commit, message exactly:
      `fix(node-health-watch): recover a Ready node whose kubelet tunnel is dead`
- [ ] `git push origin k3d-manager-v1.42.0`, then report `git rev-parse origin/k3d-manager-v1.42.0`.

### What NOT to Do

- Do NOT create a PR. Do NOT merge.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside the 5 targets (no memory-bank edits — Claude updates it).
- Do NOT commit to `main`.
- Do NOT make `slow` recoverable, change `_recover`, lower the cooldown, or touch server-0.
- Do NOT run `kubectl` or `docker` against a real cluster; tests are fully stubbed.
