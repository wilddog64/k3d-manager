# Bug: M5 hub internet downloads stall after about 128 KB; Hermes argocd, values_branch and ci go unknown

**Status:** OPEN — captured 2026-11-14 by Claude
**Priority:** P2
**Waiting on:** operator decision — since 2026-11-14 (root capture or network reset on the M5; no code fix identified)
**Introduced by:** unknown
**Should have been caught by:** live check
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store needs the hub context, unreachable from the M4); read `docs/bugs/2026-11-13-hermes-ci-unknown-page-names-no-repo-or-cause.md` (different root cause: it is the evidence gap that hid this one)
**Approval:** none yet (capture only)

## Symptom

Hermes on the M5 (`~/Library/Logs/k3dm-hermes.log`, read 2026-11-14 16:31Z) went from healthy to:

    argocd         unknown  ArgoCD status source unavailable
    values_branch  unknown  ArgoCD status source unavailable
    ci             unknown  CI status source unavailable

Last healthy cycle 15:44:46Z (`argocd` 30 applications healthy; `ci` 15:45:23Z). First unknown 15:51:59Z. The cycle also slowed: `argocd` to `ci` went from 35 s to about 3 min, and stderr shows `pr checks fetch failed for wilddog64/lib-foundation: The read operation timed out`. `reachability` stays healthy.

## Evidence (Claude, read-only probes from m5-air.local over SSH, 2026-11-14 16:30Z-16:50Z)

| Probe from the M5 | Result |
|---|---|
| `api.github.com/.../actions/runs?per_page=1` (12 KB) | 200 in 0.39 s |
| same, `per_page=5` (62 KB) | 200 in 0.61 s |
| same, unpaginated (373 KB, what `ci()` requests) | stalls at 135-143 KB, timeout; same on all four API IPs pinned with `--resolve` |
| Hermes' python3.14 urllib, same URL, 95 s timeout | `TimeoutError` at 96 s (twice), lib-foundation pulls too |
| `raw.githubusercontent.com` CHANGELOG.md (114 KB) | stalls at 113,716 B |
| `speed.cloudflare.com/__down?bytes=2000000` | stalls at 155,908 B |
| LAN, 5 MB over SSH M4 to M5 and M5 to M4 | 1-2 s both ways |

The same unpaginated request from m4-air.local (same LAN, same AP, channel 40) returns 372,992 B in 0.27-0.81 s. githubstatus.com: all systems operational. M5 disk 16% used, load 1.3, 51% memory free, default route en0, no VPN or proxy, `net.inet.tcp.recvspace` 131072 on both hosts (identical TCP sysctls). The Keychain tokens are unchanged (`mdat` 2026-11-06 and 2026-10-30) and the hub checkout last moved 14:40Z.

Every inbound internet transfer from the M5 stops at about its first receive window (128 KB). Small responses (healthz, `rate_limit`, an `Unauthenticated` gRPC reply) fit inside it, which is why reachability checks pass. `argocd app list` for 30 applications exceeds it and hits the 20 s timeout in `_argocd_run`; GitHub calls hit the 90 s `_http_json` timeout.

## Impact

Hermes is blind to ArgoCD and CI. Anything on the M5 that downloads more than about 128 KB from the internet hangs: a `brew upgrade -y` started there at 16:27:51Z; ArgoCD repo-server fetches from GitHub probably (not yet proven); hub-data export prune push (see `2026-11-14-hub-data-export-prune-timeout-marks-export-failed.md`, earlier, cause not proven the same).

## Not yet known

Why the window never advances. Needs root on the M5: `sudo tcpdump -i en0 -w` during one stalled curl (look for window updates, SACK, or dropped ACKs), then toggle Wi-Fi or renew DHCP and repeat the 2 MB Cloudflare probe. Per-client router state is possible because the M4 behind the same router is fine.

## Fix direction

Operator: capture, then reset the M5 network path, and re-run the probe table. Code-side gaps, for triage: `reachability` measures no throughput, and `argocd()` and `ci()` discard the exception (the ci half is `2026-11-13-hermes-ci-unknown-page-names-no-repo-or-cause.md`); `ci()` fetches 30 runs to read `runs[0]` (`per_page=1` would have stayed under the window).
