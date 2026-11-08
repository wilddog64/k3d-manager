# Bug: host disk metrics crash under launchd because scutil is not on Hermes's PATH

**Filed:** 2026-11-07
**Branch:** `k3d-manager-v1.43.14`
**Status:** LANDED 2026-11-07 — `d70047d5`; live M1 met 2026-11-08 (push age 42.6 s, flat across many Hermes cycles since ~15:30 on 2026-11-07; operator screenshot, below); `HostDiskMetricsStale` resolution not yet seen; independent verifier pending
**Fix commit:** d70047d5
**Priority:** P2 — every host's disk gauges are frozen, so the critical disk-space alert cannot fire; running the script by hand is a workaround
**Waiting on:** dispatch — since 2026-11-08 (independent verifier)
**Approval:** explicit 2026-11-07 "can you investigate this issue, file bug if necessary and dispatch to Luna" (operator)
**Severity:** high
**Related:** `docs/bugs/2026-10-30-host-disk-labels-the-new-hub-as-m4-and-cannot-reach-m2.md` (its 2026-11-06 recurrence note; this doc is that recurrence's root cause)

## Symptom

`HostDiskMetricsStale` has fired without a break since 2026-10-31T15:14Z (Alertmanager delivery dashboard, Noisiest alerts: 72 firing series-hours, 0 trips). On the M5 Pushgateway on 2026-11-07, `push_time_seconds{job="k3dm-disk"}` was 1793456022 (2026-10-31T14:13Z), while `k3dm-hub-checkout` and `k3dm-orbstack`, pushed by the same Hermes cycle to the same Pushgateway, were minutes old. The four `k3dm_disk_probe_success` series read 1, but those are frozen values.

## Root cause

Claude, on the M5, 2026-11-07:

- `bin/k3dm-disk-metrics --dry-run` from an SSH shell: rc 0 in 2 s, all four hosts probe 1. A real run from that shell pushed and refreshed `push_time_seconds`.
- The same dry run under Hermes's launchd environment (`env -i HOME USER K3DM_REPO_ROOT PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`, the PATH in `com.k3d-manager.hermes.plist`) fails at once: `FileNotFoundError: [Errno 2] No such file or directory: 'scutil'` from `_targets()` (`bin/k3dm-disk-metrics:30`). `scutil` is `/usr/sbin/scutil`, and `/usr/sbin` is not on that PATH.
- `_publish_disk_metrics` (`bin/k3dm-hermes:803`) runs the script with `capture_output=True, check=False` and never reads the result, so the traceback is discarded and the Hermes log has no trace.

The `scutil` call came in with the 2026-10-31 hub-label fix (`1708c97a`, released in `bd68d6ff`). Its live check ran from an interactive shell, which has `/usr/sbin`. `scripts/tests/bin/test_disk_metrics.py:111` asserts the bare `["scutil", "--get", "LocalHostName"]` call, so the test shares the wrong assumption.

## Fix

1. `bin/k3dm-disk-metrics`: call `/usr/sbin/scutil` by absolute path. Nothing else in `_targets()` changes.
2. `bin/k3dm-hermes`, `_publish_disk_metrics`: keep `check=False` and the 120 s timeout. When the script exits nonzero, print one line to stderr: `disk metrics publish failed: rc=<rc>: <last non-empty stderr line, at most 300 characters>`. The exit code of Hermes does not change.
3. `scripts/tests/bin/test_disk_metrics.py`: update the line 111 assertion to the absolute path, and add the tests in the Acceptance block.
4. `CHANGELOG.md`: one bullet at the end of `[Unreleased]`.

## Files

- `bin/k3dm-disk-metrics`
- `bin/k3dm-hermes`
- `scripts/tests/bin/test_disk_metrics.py`
- `CHANGELOG.md`

## Gates

`pytest scripts/tests/bin/test_disk_metrics.py scripts/tests/bin/test_hermes_checkout_lag.py` with `PATH` including a Python that has PyYAML. Paste the output, including failures.

## What NOT to Do

- Do NOT add `/usr/sbin` to the Hermes plist or change any launchd file; the script must work under the PATH it is given.
- Do NOT change `FLEET`, the probe, the metric names or the push URL.
- Do NOT make Hermes exit nonzero or stop its cycle when the disk script fails.
- Do NOT commit, push or create a PR. Claude reviews and commits.
- Do NOT touch `memory-bank/` or any file outside the Files list.

## Acceptance

```yaml
interface:
  - "bin/k3dm-disk-metrics --dry-run, run as a subprocess with a chosen environment"
  - "bin/k3dm-hermes: _publish_disk_metrics()"
must:
  - id: M1
    text: "With K3DM_DISK_TARGETS unset, PATH=/usr/bin:/bin (no /usr/sbin) and ssh stubbed, bin/k3dm-disk-metrics --dry-run exits 0 and prints a k3dm_disk_probe_success line for the local host named from LocalHostName. Paired control: the same run on the pre-fix code exits nonzero with FileNotFoundError for scutil."
  - id: M2
    text: "_publish_disk_metrics prints one stderr line starting 'disk metrics publish failed: rc=' with the script's last stderr line when the script exits nonzero. Paired control: it prints nothing when the script exits 0."
must_not:
  - id: N1
    text: "No bare 'scutil' command: the script never runs a command whose first element is 'scutil' without a path."
  - id: N2
    text: "_publish_disk_metrics never raises and never prints more than 300 characters of the script's stderr."
evidence:
  - id: E1
    proves: [M1, M2, N1, N2]
    kind: offline
    what: "Independent verifier, tests from this block only; M1's pre-fix control and N1 shown red against the pre-fix code."
  - id: E2
    proves: [M1]
    kind: live
    what: "Claude: after the M5 checkout has the fix, push_time_seconds{job=\"k3dm-disk\"} is under 600 s old for two Hermes cycles, and HostDiskMetricsStale resolves."
```

## Live check — 2026-11-08 (operator screenshot, Host Disk dashboard on the M5 hub, ~04:10 PT)

- Probe status: hostinger, m2, m4, m5 all `up`. Used %: hostinger 19.8, m2 69.7, m4 69.1, m5 14.9. Free: 155, 281, 142, 789 GiB (m5 matches the M5 disk, 822 GiB free on 2026-10-31; m4 is no longer the M5's disk).
- Last push age 42.6 s, and the push-age sparkline stays flat from about 15:30 on 2026-11-07, so the launchd-scheduled Hermes runs push every cycle again. Used % over time has no data from about 07:00 to 15:30 on 2026-11-07, the window before the M5 checkout had `d70047d5`.
- Not shown: `HostDiskMetricsStale` resolved. The hub was not reachable from Claude's M4 session, so the Prometheus query was not run by Claude.
