# Hub "CPU starvation" was memory pressure surfacing as load

## What was believed

The hub's sustained load average of 16-17 on a 10-core M4 Air was treated as CPU
saturation, and the standing note
`reference_one_second_probes_cpu_starvation_kill_loop` frames the failure mode as
CPU starvation. `make monitoring-pause` was the documented lever.

## What was measured

Pausing the hub observability stack barely moved the load, and pausing the Argo CD
application controller cut revision churn almost in half without reviving stalled
Kine compaction. Neither behaved like CPU relief.

The machine was in severe memory distress:

```text
swap:       19,456M total, 18,190M used, 1,265M free   (93.5%)
pages free: 3,376 (~55 MB)
```

A background measurement task was killed by the OS for low memory, which is what
exposed it.

Freeing browser memory - quitting a 69-day-old Safari instance whose single
`WebKit.WebContent` child held ~2.2 GB, then the Playwright `Chrome for Testing`
browser - produced the decisive result:

| Metric | Before | After |
| --- | --- | --- |
| Load average | 16.79 / 15.35 / 15.03 | 3.72 / 4.11 / 7.98 |
| Swap file | 19,456M | 12,288M |
| Memory free | 36% | 68-73% |

## Root cause

macOS load average counts processes blocked on I/O, not only runnable ones. The
machine was thrashing against a nearly full swap file, and that swap wait was
being counted as load. Roughly 3.7 GB of browser memory was enough to keep
OrbStack's working set resident, after which the run queue drained to ~4 on a
10-core host.

The CPU was never saturated. The two framings - "CPU is the gate" and "memory is
the gate" - were never separate problems; memory pressure was presenting as
apparent CPU load.

This also revises the compaction incident recorded in
`docs/issues/2026-09-11-hub-post-rebuild-verification-gaps.md`. Compaction stalled
while load sat at 16-17, attributed there to CPU starvation. The likelier
mechanism is swap-induced I/O latency pushing Kine's compaction transaction past
its window, which is consistent with the observed
`Compact failed: ... transaction has already been committed or rolled back`.

## Correction to standing notes

`reference_one_second_probes_cpu_starvation_kill_loop` should be read as a
*memory* pressure pattern that manifests as CPU-looking load. When hub load is
high, check `sysctl vm.swapusage` and `vm_stat` **before** reaching for
`make monitoring-pause`: if swap is near full, reclaiming host memory is the
faster and larger lever.

The hardware gate for the Mac Mini M5 upgrade is likewise a memory argument, not
a core-count one. 24 GB with a ~6.5 GiB cluster, a browser for ACG and an agent
leaves no slack.

## Actions taken

- Quit the stale Safari instance (~2.7 GB) and the Playwright Chrome for Testing
  browser (~1.5 GB). The Playwright profile at
  `~/.local/share/k3d-manager/pw-profile` is persistent, so the ACG login survives;
  `scripts/lib/acg/cdp.sh` reclaims and relaunches `:9222` automatically, so no
  manual kill or re-login is required.
- Unloaded `com.k3d-manager.acg-watch`, which fired every 12,600s to extend a
  sandbox that no longer exists and would have relaunched Chrome. The plist
  remains on disk; re-bootstrap it when running a long sandbox session.
- Resumed observability at Layer 1 (Grafana + Prometheus). Measured cost was
  313m CPU and ~1.5 GiB; the startup load spike settled back to baseline.
