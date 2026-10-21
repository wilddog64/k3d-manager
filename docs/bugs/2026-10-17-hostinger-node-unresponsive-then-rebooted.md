# Bug: Hostinger node went unresponsive for ~25 minutes, then rebooted

**Status:** VERIFIED — Hostinger support's control-plane review attributes the shutdown to emergency security-patch maintenance, but the repository's LIVE-VERIFIED gate requires a software fix commit, which this incident investigation does not have. Provider live evidence is recorded below; promotion is pending a supported investigation-only evidence path. Validator mismatch: [issue record](../issues/2026-10-20-live-verification-gate-requires-fix-commit-for-investigation-bugs.md).
**Priority:** P2
**Branch:** `k3d-manager-v1.43.5` (moved from v1.43.4 by the operator, 2026-10-17: "move 3, and 4 to next release")
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

## Live verification — 2026-10-20

The operator supplied Hostinger support's hPanel AI response. Hostinger reported that its
control-plane action history showed no customer-initiated stop/reboot at **2026-10-17 17:46:15
UTC**; the next recorded operation was the scheduled weekly backup at **22:53:39 UTC**. Support
said the shutdown occurred during Hostinger VPS security-patch activity between **October 16,
2026 11:00 UTC** and **October 18, 2026 00:00 UTC**, and attributed it to a platform-initiated
maintenance restart for an emergency security patch. The response did not expose a specific
internal actor or job ID.

This is consistent with the guest journal's `qemu-ga: guest-shutdown called` at 17:46:15 UTC,
followed by an orderly systemd poweroff, and live-verifies the outage-cause classification.
Memory pressure remains an observed condition before the outage, but is not established as its
cause. No claim is made about preventing future provider maintenance restarts.

## Next steps

No further live-verification step is pending for this incident. If Hostinger later provides the
internal maintenance job or actor, append it as additional evidence; the current support response
does not include that detail.

## Dispatch scope — read-only offline review

Review the evidence already recorded in this bug and the repository for related incident records.
Do not SSH to the node, access the Hostinger panel or APIs, query live clusters, or change
infrastructure. Do not claim the cause is confirmed beyond the previous-boot journal evidence.
Produce a bounded report that distinguishes established facts from hypotheses and lists the exact
operator-provided evidence still needed to resolve who initiated the power-off.

## Files

- `docs/issues/2026-10-20-hostinger-node-outage-evidence-review.md`

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

## Observation — 2026-10-17 20:28 PDT (Vault tunnel keepalive timeout)

During the operator's chained sandbox `make up` / `make down`, `com.k3d-manager.ssh-tunnel-vault`
logged `Timeout, server srv1754834.hstgr.cloud not responding.` and exited 255 (runs 3 → 5; new
ssh PID 98519 started 20:28:44). The relaunch first got `remote port forwarding failed for listen
port 8200` (Hostinger still held the old session's port), then reconnected. The main tunnel
(PID 93261) stayed up. `kubectl --context ubuntu-hostinger get nodes` showed the node Ready
afterwards. Not the Step 4 port-kill bug: that one exits 0 or SIGTERM; this is a keepalive timeout.

