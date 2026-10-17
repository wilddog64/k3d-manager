# Bug: Hostinger node went unresponsive for ~25 minutes, then rebooted

**Status:** OPEN — previous-boot journal read 2026-10-17: the outage was a hypervisor-initiated power-off, not a hang; who triggered it is unconfirmed
**Priority:** P2
**Approval:** pending
**Found:** 2026-10-17, operator paged by `PublicEndpointDown` for `https://frontend.3ai-talk.org/`
**Affected:** `ubuntu-hostinger` (single node `srv1754834`, 7.9 GiB RAM, no swap) — every app on it

## Symptom

The operator was paged for the frontend, checked it, and found it up. The page was real: the hub
blackbox probe got HTTP 502 from 17:46 to 18:11 UTC (alert firing 17:53–18:13). Every other public
endpoint (argocd, grafana, keycloak, prometheus, alertmanager, webhook) answered normally the whole
time, so the Cloudflare tunnel was up and only the Hostinger origin was gone.

## Evidence

- `node_boot_time_seconds` on the Hostinger node: **2026-10-17T18:10:52Z** — the machine rebooted.
- Every pod on the node restarted between 18:11:20 and 18:12:26 (one restart each), including
  coredns, istio, vault, all databases and all apps.
- The Hostinger Prometheus has no samples between ~17:46 and 18:14, so the node stopped
  responding about 25 minutes before it booted again.
- In the 30 minutes before, `MemAvailable` swung between 740 MiB and 1.48 GiB, with
  `node_vmstat_pgmajfault` bursts of 150–560/s (17:26, 17:34, 17:38, 17:46). With no swap,
  major faults at that rate are page-cache thrash under memory pressure — a plausible route to
  a hang, but not proven.
- The kubelet's `Ready` condition still dates from 2026-07-22; it never recorded NotReady.
- SSH to read the previous boot's journal failed with `Host key verification failed` (not
  bypassed — the operator should confirm the host key first).

## Secondary: the frontend crashes once on cold start

After the reboot the frontend's nginx exited with
`host not found in upstream "order-service.shopping-cart-apps.svc.cluster.local"` and came up on the
next restart (about 30 s later). nginx resolves upstream names once at startup, so it fails whenever
it starts before DNS or the upstream Service is ready. Same class as the 2026-05-26 minio upstream
failure in `docs/issues/2026-05-26-acg-sandbox-expiry-remote-cluster-rebuild-shopping-cart-bootstrap-gap.md`.
It added about a minute here; it did not cause the outage.

## Next steps

1. Operator: confirm the Hostinger host key, then read the end of the previous boot:
   `sudo journalctl -b -1 -k` and `sudo journalctl -b -1 -n 200` — look for OOM kills, hung-task
   warnings, or a clean shutdown (which would point to a Hostinger-side restart).
2. Check the Hostinger panel for a maintenance or auto-recovery event at 17:45–18:11 UTC.
3. If memory pressure is confirmed: compare summed memory limits against 7.9 GiB, and decide
   between swap, lower limits, or moving workloads.

## Previous-boot journal — 2026-10-17 (Claude, read via SSH; host key matched `known_hosts`)

- The host key was **not** the problem: ED25519, ECDSA and RSA keys served now all match
  `~/.ssh/known_hosts`, and SSH as `ubuntu` works. The earlier `Host key verification failed`
  is unexplained.
- 17:46:15 UTC `qemu-ga: guest-shutdown called`, then `systemd-logind: System is powering down
  (hypervisor initiated shutdown)` and an orderly `poweroff.target`. Nothing in the guest asked for
  it: no kernel OOM, hung-task or soft-lockup lines.
- The VM was then off until boot at 18:10:52 (journal resumes 18:12:02). The ~25 min gap is the
  machine being powered off, not unresponsive.
- Open question for the operator: was it stopped/restarted from hPanel, or did Hostinger do it
  (maintenance)? hPanel's VPS activity log shows which.
- Unrelated finding during this read: pod IP pool exhausted for days — filed as
  `docs/bugs/2026-10-17-hostinger-pod-ip-pool-exhausted-leaked-cni-reservations.md`.
