# Bug: Hostinger pod IP pool is exhausted by leaked CNI reservations; new pods cannot start

**Filed:** 2026-10-17 (Claude, read-only investigation of the Hostinger node)
**Status:** FIXED — 2026-10-17: Codex `cf7b2882` + Claude `1707318b` (tests) + `93d6bfbf` (collector ran the state file instead of `cat`ting it — caught live, probe_success 0); offline E1–E3 green, N1/N2 red on pre-fix. Live E4 green (timer installed by `make refresh CLUSTER_PROVIDER=k3s-hostinger`; first sweep 23:51:17Z Result=success, 45/254 kept, 0 stale). Live E5: series in hub Prometheus (probe_success 1), `host.cni-ipam` group loaded with 3 rules; rule health `unknown` pending first evaluation
**Fix commit:** 93d6bfbf
**Live evidence:** 2026-10-17 · run hostinger-refresh-cni-ipam-timer · env hostinger/srv1754834 · scenario cni-ipam/sweep-timer · commit 11392935 · proves E4
**Live evidence:** 2026-10-17 · run hub-prometheus-cni-ipam-query · env hub/k3d-k3d-cluster · scenario cni-ipam/metrics-and-rules · commit a4675cb4 · proves E5
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

**Implementation:** cleanup done; prevention specified below, not dispatched.

## Fix — prevention

Three parts: a sweep that runs on the node on a timer, a collector that publishes what the sweep
saw to the hub Pushgateway (the route `bin/k3dm-disk-metrics` already uses for Hostinger disk), and
alert rules on those series. The pod CIDR stays `/24`; a larger range only delays the leak.

Safety model of the sweep (all must hold before a file is removed):
- the file name is an IPv4 address (never `lock`, `last_reserved_ip.*` or anything else);
- its container ID is not a sandbox `crictl pods -q --no-trunc` lists;
- no pod in the API reports that IP;
- the file is older than 10 minutes (a sandbox being created right now is never raced);
- it holds the host-local `lock` with `flock` for the whole pass;
- an empty sandbox list or an empty pod-IP list aborts the whole run (exit 1, nothing removed) — a
  containerd or API outage must never look like "everything is stale".

### 1. New `scripts/etc/hostinger/k3dm-cni-ipam-sweep.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

ipam_dir="${CNI_IPAM_DIR:-/var/lib/cni/networks/cbr0}"
state_file="${K3DM_CNI_IPAM_STATE:-/var/lib/k3dm/cni-ipam-sweep.state}"
subnet_env="${FLANNEL_SUBNET_ENV:-/run/flannel/subnet.env}"
min_age_min="${K3DM_CNI_IPAM_MIN_AGE_MINUTES:-10}"
mode="${1:---dry-run}"

case "${mode}" in
  --dry-run|--apply) ;;
  *)
    printf 'Usage: k3dm-cni-ipam-sweep [--dry-run|--apply]\n' >&2
    exit 2
    ;;
esac

if [[ ! -d "${ipam_dir}" ]]; then
  printf 'k3dm-cni-ipam-sweep: no IPAM directory %s\n' "${ipam_dir}" >&2
  exit 1
fi

exec 9>>"${ipam_dir}/lock"
flock 9

live="$(k3s crictl pods -q --no-trunc)"
if [[ -z "${live}" ]]; then
  printf 'k3dm-cni-ipam-sweep: refusing — crictl lists no pod sandboxes\n' >&2
  exit 1
fi
running_ips="$(k3s kubectl get pods -A -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' | sort -u)"
if [[ -z "${running_ips//[[:space:]]/}" ]]; then
  printf 'k3dm-cni-ipam-sweep: refusing — the API reports no pod IPs\n' >&2
  exit 1
fi

kept=0
stale=0
young=0
for f in "${ipam_dir}"/*; do
  name="$(basename "${f}")"
  [[ "${name}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
  id="$(head -n1 "${f}" | tr -d '\r')"
  if printf '%s\n' "${live}" | grep -qxF -- "${id}"; then
    kept=$((kept + 1))
    continue
  fi
  if printf '%s\n' "${running_ips}" | grep -qxF -- "${name}"; then
    printf 'SKIP %s: no sandbox but a pod reports this IP\n' "${name}"
    kept=$((kept + 1))
    continue
  fi
  if [[ -n "$(find "${f}" -mmin "-${min_age_min}")" ]]; then
    young=$((young + 1))
    continue
  fi
  if [[ "${mode}" == "--apply" ]]; then
    rm -f -- "${f}"
  fi
  stale=$((stale + 1))
done

reservations=0
for f in "${ipam_dir}"/*; do
  if [[ "$(basename "${f}")" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    reservations=$((reservations + 1))
  fi
done

range_size=0
prefix=""
if [[ -r "${subnet_env}" ]]; then
  prefix="$(sed -n 's#^FLANNEL_SUBNET=.*/\([0-9][0-9]*\)$#\1#p' "${subnet_env}")"
fi
if [[ -n "${prefix}" ]]; then
  range_size=$(( (1 << (32 - prefix)) - 2 ))
fi

alloc_errors="$(journalctl -u k3s --since '-1h' --no-pager -o cat 2>/dev/null | grep -c 'no IP addresses available' || true)"
alloc_errors="${alloc_errors:-0}"

mkdir -p "$(dirname "${state_file}")"
tmp="${state_file}.tmp"
printf 'last_run=%s\nmode=%s\nkept=%s\nstale=%s\nyoung=%s\nreservations=%s\nrange_size=%s\nalloc_errors_1h=%s\n' \
  "$(date +%s)" "${mode#--}" "${kept}" "${stale}" "${young}" "${reservations}" "${range_size}" "${alloc_errors}" \
  > "${tmp}"
chmod 0644 "${tmp}"
mv -f -- "${tmp}" "${state_file}"

printf 'mode=%s kept=%s stale=%s young=%s reservations=%s range_size=%s alloc_errors_1h=%s\n' \
  "${mode#--}" "${kept}" "${stale}" "${young}" "${reservations}" "${range_size}" "${alloc_errors}"
```

In `--dry-run`, `stale` counts what `--apply` would remove and `reservations` is the count before
removal.

### 2. New systemd units

`scripts/etc/hostinger/k3dm-cni-ipam-sweep.service`:

```ini
[Unit]
Description=k3d-manager: remove leaked flannel host-local IP reservations
After=k3s.service

[Service]
Type=oneshot
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/usr/local/sbin/k3dm-cni-ipam-sweep --apply
```

`scripts/etc/hostinger/k3dm-cni-ipam-sweep.timer`:

```ini
[Unit]
Description=Run k3dm-cni-ipam-sweep every 15 minutes

[Timer]
OnBootSec=10min
OnUnitActiveSec=15min

[Install]
WantedBy=timers.target
```

### 3. `scripts/lib/providers/k3s-hostinger.sh` — install and enable it

Add after `_hostinger_ensure_vault_unseal_watchdog()`:

```bash
function _hostinger_ensure_cni_ipam_sweep() {
  local host ssh_user ssh_key src_dir remote_dir
  host="$(_hostinger_require_host)" || return 1
  ssh_user="${_HOSTINGER_SSH_USER}"
  ssh_key="${_HOSTINGER_SSH_KEY}"
  src_dir="${SCRIPT_DIR}/etc/hostinger"
  local -a ssh_opts=(-i "${ssh_key}" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
  if _dry_run_active; then
    _info "DRY_RUN: would install the k3dm-cni-ipam-sweep timer on ${ssh_user}@${host}"
    return 0
  fi
  _info "[k3s-hostinger] Ensuring CNI IP reservation sweep timer on ${host}..."
  remote_dir="$(_run_command -- ssh "${ssh_opts[@]}" "${ssh_user}@${host}" 'mktemp -d /tmp/k3dm-cni-ipam.XXXXXX')" || return 1
  if [[ ! "${remote_dir}" =~ ^/tmp/k3dm-cni-ipam\.[A-Za-z0-9]+$ ]]; then
    printf 'ERROR: %s\n' "[k3s-hostinger] unexpected staging directory from ${host}: ${remote_dir}" >&2
    return 1
  fi
  _run_command -- scp "${ssh_opts[@]}" \
    "${src_dir}/k3dm-cni-ipam-sweep.sh" \
    "${src_dir}/k3dm-cni-ipam-sweep.service" \
    "${src_dir}/k3dm-cni-ipam-sweep.timer" \
    "${ssh_user}@${host}:${remote_dir}/" || return 1
  if ! _run_command -- ssh "${ssh_opts[@]}" "${ssh_user}@${host}" \
      "sudo -n install -m 0755 ${remote_dir}/k3dm-cni-ipam-sweep.sh /usr/local/sbin/k3dm-cni-ipam-sweep && sudo -n install -m 0644 ${remote_dir}/k3dm-cni-ipam-sweep.service ${remote_dir}/k3dm-cni-ipam-sweep.timer /etc/systemd/system/ && rm -rf -- ${remote_dir} && sudo -n systemctl daemon-reload && sudo -n systemctl enable --now k3dm-cni-ipam-sweep.timer"; then
    printf 'ERROR: %s\n' "[k3s-hostinger] CNI IP reservation sweep install failed on ${host} — leaked reservations will refill the pod IP pool" >&2
    return 1
  fi
  _info "[k3s-hostinger] CNI IP reservation sweep timer enabled on ${host}"
}
```

`remote_dir` is validated against the `mktemp` pattern before it is interpolated into the remote
command, so the remote string never carries anything but that path.

Call sites:
- `_provider_k3s_hostinger_refresh_cluster`: add `  _hostinger_ensure_cni_ipam_sweep || return 1` on the
  line after `  _hostinger_ensure_vault_unseal_watchdog || return 1`.
- `_provider_k3s_hostinger_deploy_cluster`: add `  _hostinger_ensure_cni_ipam_sweep || return 1` on the
  line after `  _dry_guard "record Hostinger active provider" _acg_record_provider "k3s-hostinger"`
  (the function handles DRY_RUN itself).

### 4. New `bin/k3dm-cni-ipam-metrics` (modelled on `bin/k3dm-disk-metrics`)

- Reads the state file over SSH: `ssh -o BatchMode=yes -o ConnectTimeout=10 -i <key> -o IdentitiesOnly=yes -- <user>@<host> cat /var/lib/k3dm/cni-ipam-sweep.state`,
  with `HOSTINGER_SSH_USER` (default `ubuntu`), `HOSTINGER_HOST` (default `srv1754834.hstgr.cloud`),
  `HOSTINGER_SSH_KEY` (default `~/.ssh/hostinger`) — reuse `_ssh_destination` from the disk collector
  by copying it, not importing it. `subprocess.run(..., timeout=30, check=False)`.
- Parses `key=value` lines; every value must be a non-negative integer except `mode`.
- On success emits, with label `host="hostinger"`:
  `k3dm_cni_ipam_reservations`, `k3dm_cni_ipam_range_size`, `k3dm_cni_ipam_stale_last_run`,
  `k3dm_cni_ipam_alloc_errors_1h`, `k3dm_cni_ipam_sweep_last_run_timestamp_seconds` (from
  `last_run`) and `k3dm_cni_ipam_probe_success 1`.
- On any SSH failure, missing key or non-integer value emits only `k3dm_cni_ipam_probe_success{host="hostinger"} 0`.
- Pushes with `PUT` to `${K3DM_CNI_IPAM_PUSHGATEWAY_URL:-http://localhost:19094}/metrics/job/k3dm-cni-ipam`,
  3 attempts, non-fatal; `--dry-run` prints the body and pushes nothing; always exits 0.

`bin/k3dm-hermes`: add `_publish_cni_ipam_metrics()` beside `_publish_disk_metrics()` (same shape,
runs `bin/k3dm-cni-ipam-metrics`), and call it on the line after `    _publish_disk_metrics()` in the
poll.

### 5. New `scripts/etc/prometheus/rules/host-cni-ipam.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: host-cni-ipam
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: host.cni-ipam
      interval: 60s
      rules:
        - alert: HostPodIPPoolHigh
          expr: k3dm_cni_ipam_reservations / k3dm_cni_ipam_range_size > 0.80 and k3dm_cni_ipam_range_size > 0
          for: 15m
          labels:
            severity: warning
            cluster: hub
          annotations:
            summary: "Pod IP pool is over 80% reserved on {{ $labels.host }}"
            description: "{{ $labels.host }} has {{ $value | humanizePercentage }} of its pod IPs reserved; the sweep may be failing or failing to keep up. ssh in; sudo /usr/local/sbin/k3dm-cni-ipam-sweep --dry-run; systemctl status k3dm-cni-ipam-sweep.timer"
        - alert: HostPodIPAllocationFailing
          expr: k3dm_cni_ipam_alloc_errors_1h > 0
          for: 5m
          labels:
            severity: critical
            cluster: hub
          annotations:
            summary: "New pods cannot get an IP on {{ $labels.host }}"
            description: "k3s logged 'no IP addresses available' {{ $value }} times in the last hour on {{ $labels.host }}; new pods (Vault unseal watchdog, Jobs, rollouts) are failing to start. See docs/bugs/2026-10-17-hostinger-pod-ip-pool-exhausted-leaked-cni-reservations.md."
        - alert: HostCniIpamSweepStale
          expr: k3dm_cni_ipam_probe_success == 0 or (time() - k3dm_cni_ipam_sweep_last_run_timestamp_seconds > 3600) or absent(k3dm_cni_ipam_range_size)
          for: 30m
          labels:
            severity: warning
            cluster: hub
          annotations:
            summary: "CNI IP reservation sweep has not reported"
            description: "The sweep state for {{ $labels.host }} is missing or older than 1h; check the k3dm-cni-ipam-sweep timer on the node, Hermes and the hub Pushgateway port-forward."
```

`make prometheus-rules` and `deploy_observability` pick it up through the existing
`scripts/etc/prometheus/rules/*.yaml` glob; no code change for that.

### 6. Tests

- New `scripts/tests/lib/hostinger_cni_ipam_sweep.bats` runs the sweep script with `CNI_IPAM_DIR`,
  `K3DM_CNI_IPAM_STATE` and `FLANNEL_SUBNET_ENV` in `BATS_TEST_TMPDIR`, and stubs `k3s` (answers
  `crictl pods -q --no-trunc` and `kubectl get pods …` from env-provided files), `flock` (exit 0) and
  `journalctl` on `PATH`. Backdate reservation files with `touch -t`. Cases:
  - stale file (unknown ID, IP not reported, old) is removed by `--apply` and only counted by `--dry-run`;
  - live-ID file kept; file whose IP a pod reports kept with a `SKIP` line; young file kept;
  - `lock` and `last_reserved_ip.0` never removed;
  - empty `crictl` output → exit 1, no file removed; empty pod-IP output → exit 1, no file removed;
    `crictl` stub exiting non-zero → non-zero exit, no file removed;
  - state file has all eight keys; `range_size=254` for `FLANNEL_SUBNET=10.42.0.1/24`;
    `alloc_errors_1h` equals the stubbed journal's matching line count;
  - bad argument → exit 2.
- `scripts/tests/lib/hostinger_cni_ipam_sweep_install.bats`: source the provider with stubbed `ssh`,
  `scp` and `_run_command` passthrough (follow `hostinger_vault_unseal_watchdog.bats`); assert the
  install command contains `systemctl enable --now k3dm-cni-ipam-sweep.timer`, a staging directory
  not matching `^/tmp/k3dm-cni-ipam\.` returns 1 with no install command sent, DRY_RUN=1 sends no
  `ssh`/`scp`, and both call sites exist (`refresh_cluster` after the watchdog; `deploy_cluster`).
- New `scripts/tests/bin/test_cni_ipam_metrics.py` (pattern of `test_disk_metrics.py`, set
  `K3DM_CNI_IPAM_PUSHGATEWAY_URL=http://127.0.0.1:9` in every test): valid state → all six series;
  SSH failure, non-integer value or missing key → only `probe_success 0`; push failure non-fatal;
  `--dry-run` pushes nothing.
- `make validate-manifests` passes (its default list globs `scripts/etc/prometheus/rules/*.yaml`);
  if `promtool` is available, `promtool check rules` on the extracted `spec`.

## Acceptance

```yaml
must:
  - id: M1
    text: The sweep with --apply removes every reservation file whose name is an IPv4 address, whose container ID is not a listed sandbox, whose IP no pod reports, and which is older than the minimum age; it keeps every other file.
  - id: M2
    text: The sweep with --dry-run (the default) removes nothing and reports the count --apply would remove.
  - id: M3
    text: Each run writes the state file with last_run, mode, kept, stale, young, reservations, range_size and alloc_errors_1h; range_size is derived from FLANNEL_SUBNET (254 for a /24).
  - id: M4
    text: refresh_cluster and deploy_cluster for k3s-hostinger install the script, the service and the timer on the node and enable the timer; DRY_RUN=1 installs nothing.
  - id: M5
    text: bin/k3dm-cni-ipam-metrics publishes reservations, range_size, stale_last_run, alloc_errors_1h, sweep_last_run_timestamp_seconds and probe_success=1 for a valid state file, and probe_success=0 alone otherwise; it always exits 0.
  - id: M6
    text: Hermes runs the collector each poll.
  - id: M7
    text: The rules file defines HostPodIPPoolHigh (>80% for 15m), HostPodIPAllocationFailing (any error in 1h, critical) and HostCniIpamSweepStale, and passes manifest validation.
must_not:
  - id: N1
    text: The sweep never removes a file when crictl lists no sandboxes, when the API reports no pod IPs, or when crictl or kubectl fails (red on the pre-fix sweep in the appendix, which has no empty-list guard).
  - id: N2
    text: The sweep never removes a file younger than the minimum age (red on the pre-fix sweep in the appendix, which has no age check).
  - id: N3
    text: The sweep never removes lock, last_reserved_ip.* or any non-IPv4 file name.
  - id: N4
    text: The installer never sends a remote command containing a staging path that does not match ^/tmp/k3dm-cni-ipam\.[A-Za-z0-9]+$.
  - id: N5
    text: No test pushes to a real Pushgateway or reaches a real host over SSH.
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3]
    kind: offline
    text: BATS against the sweep with stubbed k3s/flock/journalctl and a temp IPAM directory; N1 and N2 shown red against the pre-fix sweep in the appendix, saved as a test fixture.
  - id: E2
    proves: [M4, N4]
    kind: offline
    text: BATS for _hostinger_ensure_cni_ipam_sweep with stubbed ssh/scp.
  - id: E3
    proves: [M5, M6, N5]
    kind: offline
    text: pytest for the collector with Pushgateway URL 127.0.0.1:9 and stubbed subprocess.
  - id: E4
    proves: [M4, M1]
    kind: live
    text: Operator runs the Hostinger refresh; Claude then checks over SSH (read-only) that systemctl list-timers shows k3dm-cni-ipam-sweep.timer, the state file exists with mode=apply, and reservations equals the live sandbox count.
  - id: E5
    proves: [M5, M7]
    kind: live
    text: Claude queries hub Prometheus for k3dm_cni_ipam_reservations{host="hostinger"} and k3dm_cni_ipam_probe_success == 1, and confirms the three rules are loaded.
interface:
  - scripts/etc/hostinger/k3dm-cni-ipam-sweep.sh [--dry-run|--apply]; env CNI_IPAM_DIR, K3DM_CNI_IPAM_STATE, FLANNEL_SUBNET_ENV, K3DM_CNI_IPAM_MIN_AGE_MINUTES; calls k3s crictl, k3s kubectl, flock, journalctl
  - state file key=value lines (last_run, mode, kept, stale, young, reservations, range_size, alloc_errors_1h)
  - _hostinger_ensure_cni_ipam_sweep in scripts/lib/providers/k3s-hostinger.sh; DRY_RUN
  - bin/k3dm-cni-ipam-metrics [--dry-run]; env HOSTINGER_HOST, HOSTINGER_SSH_USER, HOSTINGER_SSH_KEY, K3DM_CNI_IPAM_PUSHGATEWAY_URL
  - Pushgateway job k3dm-cni-ipam; series k3dm_cni_ipam_* with label host
  - scripts/etc/prometheus/rules/host-cni-ipam.yaml alert names
```

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
- `git pull origin k3d-manager-v1.43.4`; work on that branch only.
- Read `scripts/lib/providers/k3s-hostinger.sh` (`_hostinger_ensure_vault_unseal_watchdog`,
  `_provider_k3s_hostinger_deploy_cluster`, `_provider_k3s_hostinger_refresh_cluster`),
  `bin/k3dm-disk-metrics`, `scripts/tests/bin/test_disk_metrics.py`,
  `scripts/tests/lib/hostinger_vault_unseal_watchdog.bats`, `scripts/etc/prometheus/rules/host-disk.yaml`
  and `bin/k3dm-hermes` around `_publish_disk_metrics`.

## Definition of Done

- [ ] §1–§5 files added/changed exactly; §6 tests added.
- [ ] `shellcheck scripts/etc/hostinger/k3dm-cni-ipam-sweep.sh scripts/lib/providers/k3s-hostinger.sh` — no new warnings.
- [ ] `bats scripts/tests/lib/hostinger_cni_ipam_sweep.bats scripts/tests/lib/hostinger_cni_ipam_sweep_install.bats scripts/tests/lib/hostinger_vault_unseal_watchdog.bats` green; paste the output.
- [ ] `pytest scripts/tests/bin/test_cni_ipam_metrics.py scripts/tests/bin/test_disk_metrics.py` green; paste the output.
- [ ] N1 and N2 shown red against the pre-fix sweep: save the appendix script as `scripts/tests/fixtures/cni-ipam/pre-fix-sweep.sh` and run the same cases with the subject swapped (e.g. `SWEEP=` env in the BATS file); paste the failures.
- [ ] `docs/guides/alerting.md`: add the three alerts and what to do for each; `docs/guides/grafana-dashboards.md` triage table: a row for "pod IP pool" pointing at `k3dm_cni_ipam_reservations`.
- [ ] Commit message, verbatim: `fix(hostinger): sweep leaked CNI IP reservations on a timer and alert on pool exhaustion`
- [ ] `git push origin k3d-manager-v1.43.4`; confirm with `git rev-parse origin/k3d-manager-v1.43.4`.
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with the SHA; report the SHA.

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside the listed targets (§1–§6 files, the pre-fix fixture, the two guides, memory-bank).
- Do NOT commit to `main`.
- Do NOT SSH to the Hostinger node, run the sweep there, or run `make refresh`/`make up` — stubs only; live install is the operator's.
- Do NOT change the pod CIDR or flannel configuration.
- Do NOT modify `scripts/lib/foundation/`.
- Do NOT push to any real Pushgateway from tests.

## Appendix — pre-fix sweep (run by the operator 2026-10-17, Step 2)

The one-off script used for the cleanup. It is the pre-fix subject for N1/N2: it has no empty-list
guard and no age check.

```bash
#!/usr/bin/env bash
set -euo pipefail

d=/var/lib/cni/networks/cbr0
mode="${1:-dry-run}"

exec 9>"${d}/lock"
flock 9

live="$(k3s crictl pods -q --no-trunc)"
running_ips="$(k3s kubectl get pods -A -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' | sort -u)"

removed=0
kept=0
for f in "${d}"/10.42.0.*; do
  ip="$(basename "${f}")"
  id="$(head -n1 "${f}" | tr -d '\r')"
  if printf '%s\n' "${live}" | grep -qxF -- "${id}"; then
    kept=$((kept + 1))
    continue
  fi
  if printf '%s\n' "${running_ips}" | grep -qxF -- "${ip}"; then
    echo "SKIP ${ip}: no sandbox but a pod reports this IP"
    kept=$((kept + 1))
    continue
  fi
  if [[ "${mode}" == "--apply" ]]; then
    rm -f -- "${f}"
  fi
  removed=$((removed + 1))
done

echo "mode=${mode} kept=${kept} stale=${removed}"
echo "reservations now: $(ls "${d}" | grep -c '^10\.42\.')"
```
