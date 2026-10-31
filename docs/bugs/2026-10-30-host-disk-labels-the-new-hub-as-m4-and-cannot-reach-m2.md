# Bug: Host Disk dashboard labels the new hub's disk as "m4" and shows m2 down after the cutover

**Status:** OPEN
**Priority:** P2
**Approval:** operator, 2026-10-30 ("this does not seems to look right? m4 never has 821G ... why m2 is down? also we should include m5")
**Filed:** 2026-10-30
**Detected by:** the operator (Host Disk dashboard on the M5 hub); root-caused by Claude
**Affected:** `bin/k3dm-disk-metrics` (`DEFAULT_TARGETS`); `bin/k3dm-machine-setup` (copies `.ssh/config.d/operator` without the `Include` that loads it)
**Branch:** `k3d-manager-v1.43.12`
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
