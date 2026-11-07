# Bug: Host Disk dashboard labels the new hub's disk as "m4" and shows m2 down after the cutover

**Status:** OPEN — regression under investigation 2026-11-04 (E2E runner); previously LIVE-VERIFIED 2026-10-31 — `1708c97a` (Luna); E3 live on the M5 at `4f409ba6`: probe_success 1 for m5 (822 GiB), m4 (173 GiB), m2 and hostinger
**Fix commit:** 1708c97a
**Live evidence:** 2026-10-31 · run k3dm-disk-metrics-m5-1420z · env m5-air · scenario host-disk-probe-m5-m4-m2-hostinger · commit 4f409ba6 · proves E3
**Priority:** P2
**Waiting on:** investigation — since 2026-11-07
**Approval:** operator, 2026-10-30 ("this does not seems to look right? m4 never has 821G ... why m2 is down? also we should include m5")
**Filed:** 2026-10-30
**Detected by:** the operator (Host Disk dashboard on the M5 hub); root-caused by Claude
**Affected:** `bin/k3dm-disk-metrics` (`DEFAULT_TARGETS`); `bin/k3dm-machine-setup` (copies `.ssh/config.d/operator` without the `Include` that loads it)
**Branch:** `k3d-manager-v1.43.15` (moved 2026-11-07 by Claude, operator: "go ahead to move that four bugs to v1.43.15"; no landed fix to verify in v1.43.14; filed on `k3d-manager-v1.43.12`)
**Related:** `docs/bugs/2026-10-30-hub-cutover-leaves-old-hub-producers-on-old-pushgateway.md`

## Observed failure

After the M4 → M5 hub cutover, the Host Disk dashboard showed `m4` with 821 GiB free and 11.3% used, and
showed `m2` as `down`. The M5 was not shown at all.

- **Wrong label.** `DEFAULT_TARGETS = "m4=local:/System/Volumes/Data m2=m2jump:k3dm-snapshots hostinger=hostinger:/"`.
  The exporter runs inside Hermes, and Hermes moved to the M5 in the cutover. So `local` is now the M5's disk:
  `df -k` on the M5 (2026-10-30) gives 861,171,368 KiB available, which is 821 GiB. The real M4 has
  148,994,960 KiB available (70% used), and nothing measures it any more.
- **m2 down.** The M5 cannot resolve `m2jump`. On the M5, `ssh -o BatchMode=yes m2jump true` exits 255 with
  `ssh: Could not resolve hostname m2jump: nodename nor servname provided, or not known` (captured 2026-10-30).
  The alias lives in `~/.ssh/config.d/operator`. `make machine-setup` copied that fragment to the M5, but the
  M5's `~/.ssh/config` has no `Include ~/.ssh/config.d/operator` line, so ssh never reads it. The M4's config
  has the line as its first line.

## Fix

1. **Label the local disk by this Mac's name.** The `local` target's label comes from
   `scutil --get LocalHostName` with any `-air` suffix removed (`m5-air` gives `m5`). The defaults then cover
   the whole fleet: this Mac via `local`, each of the other fleet Macs (`m2`, `m4`, `m5`, excluding this one)
   over ssh, and `hostinger=hostinger:/`.
   - `m2` stays `m2jump:k3dm-snapshots`.
   - `m4` and `m5` use `<name>-air.local:/System/Volumes/Data`.
   - `K3DM_DISK_TARGETS` still overrides everything.
   - Keep the fleet list in one place: a module-level tuple, or `scripts/etc/machine/` if a fleet list
     already exists there.
2. **Load the operator ssh fragment.** When `bin/k3dm-machine-setup` installs `.ssh/config.d/operator`,
   make sure `~/.ssh/config` loads it:
   - If no line in `~/.ssh/config` is exactly `Include ~/.ssh/config.d/operator`, add it as the first line.
     (An `Include` placed after a `Host` block applies only inside that block, so it must go first.)
   - Back up the old file as `config.pre-machine-setup`, and never overwrite an existing backup.
   - Keep mode 600.
   - Create the file if it is missing.
   - Running it a second time changes nothing.

## Files

- `bin/k3dm-disk-metrics`
- `scripts/tests/bin/test_disk_metrics.py`
- `bin/k3dm-machine-setup`
- `scripts/tests/bin/machine_setup.bats`
- `docs/guides/grafana-dashboards/` (the Host Disk page, if it names the hosts)
- `docs/howto/machine-setup.md` (one sentence on the Include)
- `CHANGELOG.md` `[Unreleased]`

## Acceptance

```yaml
must:
  - id: M1
    text: with K3DM_DISK_TARGETS unset and LocalHostName m5-air, the local target is labelled m5 and the defaults include m4 over ssh (m4-air.local, /System/Volumes/Data), m2 (m2jump, k3dm-snapshots) and hostinger
  - id: M2
    text: with LocalHostName m4-air, the local target is m4 and m5 is probed over ssh
  - id: M3
    text: machine-setup ensures ~/.ssh/config's first line is "Include ~/.ssh/config.d/operator" when it installs that fragment, keeps mode 600, and keeps a one-time backup
must_not:
  - id: N1
    text: the local disk is never labelled m4 unless this Mac's LocalHostName is m4-air
  - id: N2
    text: the default targets never probe this Mac over ssh (no self target besides local)
  - id: N3
    text: a second machine-setup run does not add a second Include line or replace the first backup
  - id: N4
    text: K3DM_DISK_TARGETS, when set, is used verbatim (no fleet defaults added)
evidence:
  - id: E1
    proves: [M1, M2, N1, N2, N4]
    kind: offline
    text: pytest in scripts/tests/bin/test_disk_metrics.py stubbing scutil output; stub output captured from the M5 (`m5-air`, 2026-10-30)
  - id: E2
    proves: [M3, N3]
    kind: offline
    text: BATS in machine_setup.bats with a scratch HOME (fixture asserts HOME is scratch first), run twice
  - id: E3
    proves: [M1]
    kind: live
    text: after a Hermes cycle on the M5, Claude queries k3dm_disk_probe_success on the M5 Prometheus and sees m5, m4, m2 and hostinger all 1
interface:
  - bin/k3dm-disk-metrics (_targets(), publish)
  - env K3DM_DISK_TARGETS
  - bin/k3dm-machine-setup --role hub --from HOST
```

Test controls: N4 is paired with M1 (the same test with the variable unset gets the fleet defaults). N2 is
paired with a check that `local` is present.

## What NOT to do

- Do not read or copy ssh private keys, and do not touch `known_hosts` or `authorized_keys`.
- Do not create a PR, skip hooks, commit to `main`, or modify files outside the list above.

## Manual repair on the M5 (2026-10-30, operator)

The Include line alone was not enough. The M5 also had no `m2-air.local` host key, and the M2 did not
accept the M5's key. The operator fixed this by hand:
- added the Include line;
- ran `ssh-keyscan -t ed25519 m2-air.local` and appended the key after its fingerprint matched the M4's (`SHA256:sz6QWFAYNJmjbckthD8zfXl5OQfXjorVzAVscjrNkjs`);
- ran `ssh-copy-id -i ~/.ssh/id_ed25519.pub m2jump`.

`m2jump` now answers in batch mode. Hostinger needed the same two trust steps during the cutover. Copying
`known_hosts` entries and authorizing the new hub's key on every fleet host stays an operator step, and is
out of scope for this fix (see What NOT to do). Track it as a `hub-new` checklist item.

## Resolution (2026-10-31)

- **Fix:** `1708c97a` (Luna; Claude review). Offline: `test_disk_metrics.py` 9/9, `machine_setup.bats` 61/61 outside the sandbox, shellcheck clean; the four new tests were red on the pre-fix scripts.
- **E3 (live, 2026-10-31 ~14:20Z):** the M5 checkout was fast-forwarded to `4f409ba6`. Running `bin/k3dm-disk-metrics` on the M5 pushed `k3dm_disk_probe_success` = 1 for m5, m4, m2 and hostinger. `m5` reports 822 GiB free (the M5's disk), and `m4` reports 173 GiB (the real M4, measured over ssh). The M5 reaches both `m4-air.local` and `m2jump` with key login.


## Regression evidence — 2026-11-04 (M5 E2E runner)

**Status:** OPEN recurrence investigation. October 31 live verification remains valid historical evidence; the current cause is unconfirmed.

**Operator symptom:** E2E Verification Grafana dashboard status, duration, failure trends and details show No data; failing runs shows 0. Operator suspects M5 migration left M2 runner setup incomplete.

**Cloud-bridge live evidence (read-only; 2026-11-04 16:35–16:37 UTC):**
- E2E runner health request `20261104T163520Z-make-e2e-runner-health`, job `cf42e64f`: `hub_context=k3d-k3d-cluster`, `hub=ok`, `runner=m2jump`, `runner_status=unreachable`, `severity=warning`. Exit code 0 denotes a warning, not healthy runner reachability.
- Hub pods request `20261104T163519Z-diagnose-pods-e2e`, job `e2d3ef86`: vulnerability-inventory-exporter-754b96678b-wqrl9 is Running 1/1 with zero restarts in `platform-ops`.
- Exporter logs request `20261104T163630Z-diagnose-logs-e2e-exporter`, job `0114e526`: completed but returned `(no output returned)`; this does not prove metric ingestion.

**Important contrast:** On 2026-10-31, this bug's E3 live verification showed successful M5-to-M2 SSH disk probing. Do not conclude M2 was never configured. Identify whether the runner-health check has different SSH/configuration requirements or connectivity regressed since then.

**Investigation / acceptance:**
1. Compare the SSH resolution, user, authentication and connection behavior in `e2e_runner_health` to the successful `k3dm-disk-metrics` M2 probe. Separate alias/Include, known_hosts, authorization, network reachability, and runner-specific preflight causes. Never expose secret material.
2. Check that one-command machine setup / hub cutover documents and verifies M5-to-M2 E2E runner connectivity with a read-only acceptance gate, without silently modifying SSH trust.
3. Separately check E2E result ConfigMaps (`k3dm.k3d.io/e2e-result=true`), exported `e2e_*` metrics, and Prometheus ingestion. See related existing 2026-10-16 hub-rebuild-loses-e2e-results bug for lost historical records; absence of runner connectivity alone does not prove lost history.
4. Live acceptance: E2E runner reports reachable, and Grafana status metrics actually return series; keep these as separate requirements.

No cluster changes or recovery actions were performed. This evidence is on branch `k3d-manager-v1.43.14`; P2 priority is retained.

## Recurrence note 2026-11-06: metrics frozen since Oct 31

`HostDiskMetricsStale` has fired since 2026-10-31T15:14Z. On the M5 Pushgateway, `push_time_seconds{job="k3dm-disk"}` is 2026-10-31T14:13:42Z, about six days old, while the `m5`, `m4`, `m2` and `hostinger` `k3dm_disk_probe_success` series still read 1. Those 1s are frozen values, not live probes, so the Oct 31 live verification is the last known good and cannot speak for today. Hermes runs `bin/k3dm-disk-metrics` with `check=False` and captured output (`_publish_disk_metrics`), so a failure leaves no trace in its log. Cause not established.

**Cause found 2026-11-07 (Claude):** `bin/k3dm-disk-metrics` runs bare `scutil`, which this doc's fix added; Hermes's launchd PATH has no `/usr/sbin`, so the script dies with `FileNotFoundError` and Hermes discards the traceback. Fix and acceptance: `docs/bugs/2026-11-07-disk-metrics-crash-under-launchd-scutil-not-on-path.md`.
