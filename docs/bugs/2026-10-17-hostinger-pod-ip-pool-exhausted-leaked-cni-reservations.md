# Bug: Hostinger pod IP pool is exhausted by leaked CNI reservations; new pods cannot start

**Filed:** 2026-10-17 (Claude, read-only investigation of the Hostinger node)
**Status:** OPEN — cleanup done 2026-10-17T23:14:58Z (operator ran the sweep; Claude confirmed); prevention not yet specified
**Priority:** P1 — every new pod on the node fails intermittently, including the Vault unseal watchdog CronJob that `docs/bugs/2026-10-17-hostinger-vault-sealed-after-reboot-no-unseal-watchdog.md` depends on, so that fix cannot work while this is open
**Severity:** high
**Approval:** approved — operator, 2026-10-17: "go ahead"
**Affected:** `ubuntu-hostinger` (single node `srv1754834`, flannel host-local IPAM, pod CIDR `10.42.0.0/24`)

## Evidence (2026-10-17 ~23:10 UTC)

- kubelet/k3s logs `failed to setup network for sandbox … plugin type="flannel" failed (add):
  failed to allocate for range 0: no IP addresses available in range set: 10.42.0.1-10.42.0.254`.
  - previous boot (2026-10-11 03:38 → 2026-10-17 17:46): **30,124** occurrences, first at
    2026-10-11 08:02 UTC;
  - current boot (since 18:12 UTC): **192** occurrences in ~5 hours, last at 22:27 UTC — a reboot
    did not clear it, because host-local reservations live on disk.
- `/var/lib/cni/networks/cbr0` holds **254** reservation files — the whole range.
- Live: 48 pods hold a `10.42.0.x` IP; `crictl pods` lists 89 sandboxes. Roughly 165+ reservations
  belong to no live sandbox.
- Pods hit in the current boot: `shopping-cart-data/minio-0` (45 retries before it got an IP),
  three `trivy-system/scan-vulnerabilityreport-*` jobs. All current pods are Running; the damage
  is to anything that must start a **new** pod — CronJobs, Jobs, rollouts, restarts.

## Why it matters

- The Vault unseal watchdog (`secrets/vault-unseal-watchdog`, every 5 min) starts a new pod each
  run. With the pool full, a run only gets an IP if one happens to be free, so a sealed Vault can
  stay sealed.
- Trivy scans, e2e Jobs and any rollout get the same random delay or failure.

## Likely cause (not proven)

host-local IPAM frees a reservation only on CNI `DEL`. Sandboxes torn down without `DEL` (hard
power-offs, k3s/containerd restarts, kills under memory pressure — see
`docs/bugs/2026-10-17-hostinger-node-unresponsive-then-rebooted.md`) leave the file behind.

## Investigation / fix direction

1. Read-only: list reservation files whose container ID is not in `crictl pods -q` (no deletion).
2. Recovery (operator-run, cluster-mutating): remove only those stale files; confirm the error count
   stops growing and a test pod gets an IP.
3. Prevention options to evaluate: a periodic stale-reservation sweep on the node (compare against
   `crictl pods`), an alert on `no IP addresses available` / reservation count near 254, and a
   larger node pod CIDR is NOT the fix (it only delays the leak).

## Step 1 result — 2026-10-17 (read-only)

- 252 reservation files: 45 belong to a live sandbox, **207 to no sandbox at all**.
- Running pods: 47, of which 2 are hostNetwork, so 45 use pod IPs — matching the 45 live
  reservations exactly. No running pod's IP is among the 207.
- Sweep script (dry-run by default, `--apply` deletes): takes the host-local `lock` with `flock`,
  re-checks each file against `crictl pods` **and** every pod's reported IP at deletion time. Dry
  run on the node: `kept=45 stale=207`.

## Step 2 result — 2026-10-17 (operator ran, Claude verified)

- Sweep `--apply` at 23:14:58Z: `kept=45 stale=207`, `reservations now: 45`.
- `journalctl -u k3s` "no IP addresses available": 184 from 18:12Z to the sweep, **0** after.
- The next watchdog run (`vault-unseal-watchdog-29871315`) got `10.42.0.65` and completed; Vault
  reports `sealed: false`.
- Count only `-u k3s` lines: the node's own sudo log records each command line, so a plain grep of
  the journal counts the investigator's own commands.

**Implementation:** cleanup done; prevention not started.
