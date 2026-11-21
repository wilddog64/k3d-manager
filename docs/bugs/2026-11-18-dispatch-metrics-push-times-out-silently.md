# dispatch-metrics: pushes to the hub time out silently and the dispatch dashboards go stale

**Status:** VERIFIED — 795e101e, 2026-11-18 (fix `docs/plans/dispatch-metrics-reliable-push-and-stale-alert.md`, whose E5 and E6 passed live 2026-11-18; live evidence is recorded in the plan)
**Priority:** P2 (operator, 2026-11-18: "reliablity is a higer bug (maybe P2)") — the Agent Dispatch and cost dashboards stop updating with no alert; workaround is a manual `make dispatch-metrics` on the M4
**Introduced by:** unknown
**Should have been caught by:** unknown
**Introducing change reviewed:** unknown
**Prior art:** `docs/bugs/2026-10-05-nightly-test-metrics-push-failure-is-silent.md` (exact-slug review) — read, same class (silent push failure, fixed there with a staleness alert), different producer; `docs/bugs/2026-11-06-hub-forward-tunnels-lose-auth-after-old-hub-reboot.md` — read, different root cause (tunnel auth; this tunnel has been up since 2026-11-15). `make find-similar-docs` not run (vector store unreachable, 2026-11-18).
**Filed:** 2026-11-18
**Approval:** operator, 2026-11-18: "should we either push metrics automtically from m4 to m5 ..." then the P2 call above

## Symptom

On 2026-11-18 the hub's dispatch metrics did not show the day's runs (Astra review, Astra metrics land/verify).
`~/.local/share/k3d-manager/worktrees/metrics.log` on the M4 holds 38 `dispatch metrics push failed: timed out` lines and
nothing else records the failure. A manual `make dispatch-metrics` at 76d92773 pushed fine and the data appeared.

## Facts (Claude, read-only, M4, 2026-11-18)

- Push: `bin/k3dm-dispatch-metrics` PUTs the whole state to `$K3DM_DISPATCH_PUSHGATEWAY_URL` (default
  `http://localhost:19094`) `/metrics/job/k3dm-dispatch` with `urlopen(..., timeout=5)`; on failure it logs one line and exits.
- Payload: 18,353 lines, 3,324,002 bytes (dry-run at 76d92773). Computing it takes about 45 s CPU.
- Path: launchd `com.k3d-manager.hub-pushgateway-port-forward` ssh tunnel, `127.0.0.1:19094` -> `m5-air.local`, up since
  2026-11-15 05:56 (pid 32709); `/-/ready` answers 200 in 0.02 s. So the tunnel was not down.
- Hub side: `push_failure_time_seconds{job="k3dm-dispatch"} 0` — failed pushes never reached the Pushgateway as a failed
  push, consistent with a client-side timeout during the 3.3 MB upload/parse.
- Spawning: the bash path (`bin/k3dm-codex-dispatch:105-124`) runs the exporter single-flight with a lock and a pending
  flag; the Python ledger writer (`bin/k3dm-codex-dispatch:486`, `subprocess.Popen`) starts it directly, bypassing that
  lock. A burst of ledger events can therefore run several 45 s exporters and several 3.3 MB PUTs at once. Hypothesis for
  the timeouts, not yet proven.
- Freshness is already exported: `push_time_seconds{job="k3dm-dispatch"}` exists on the Pushgateway; no new metric is needed
  for a staleness alert. No alert rule reads it today (`grep -rn push_time_seconds scripts/etc` finds only dashboard
  "Last push age" panels for host-disk and CNI IPAM).

## Proposed fix (for the spec)

1. **Push reliably:** route the Python spawn path through the same single-flight lock; raise the push timeout (about 30 s)
   with a bounded retry and backoff; log the HTTP status or exception with a timestamp. Consider gzip if the deployed
   Pushgateway accepts `Content-Encoding: gzip` (prove on the hub's version first), or trim series cardinality.
2. **Self-heal:** a launchd job on the M4 runs `make dispatch-metrics` every 15 minutes. Each push replaces the whole group,
   so any later success repairs a missed one.
3. **Alert:** `DispatchMetricsStale` in the platform-ops PrometheusRule, `time() - push_time_seconds{job="k3dm-dispatch"} > 3600`
   (same shape as `HubDataExportStale`), with a positive control test.

## Open question (operator)

The operator asked for Hermes to examine a stale-metrics alert and send an approval request for the fix. Two constraints:
- Hermes posts a card only with two or more degraded sensors; one stale sensor alone posts nothing.
- `docs/plans/v1.45.0-dispatch-stall-recovery.md` (plan 5) already designs detect -> headless Claude diagnosis -> Slack
  Approve/Deny -> act. Reusing it for stale metrics avoids a sixth v1.45.0 plan.

Options: (a) ship 1-3 as the P2 fix now, and add "stale dispatch metrics" as a second trigger in plan 5's spec; (b) one
larger change covering both (would need to displace a plan). Claude recommends (a).

## Decision and measurement (2026-11-18)

- Operator chose (a): parts 1-3 here, spec `docs/plans/dispatch-metrics-reliable-push-and-stale-alert.md`; the Hermes flow is
  part 5 of `docs/plans/v1.45.0-dispatch-stall-recovery.md`.
- Measured (Claude, M4 -> hub tunnel, 13:28 UTC): render 45.3 s; three uncontended PUTs of the 3,316,618-byte body took
  1.21 / 1.18 / 1.29 s. The 5 s timeouts are therefore contention, not body size, which supports the lock-bypass
  hypothesis.
- Deferred to grooming (pre-existing, found in spec review by Astra): two callers can race to take over the same dead
  `metrics.lock`, and release (`rmdir`) is not owner-specific, so a former owner can remove its successor's lock. P3.
