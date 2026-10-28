# OrbStack non-interactive fixture and macOS cleanup follow-up

## Full M4 runs and actual failure scope

Observed run1793213637 and later terminal run1793216188 both recorded
2535BATS cases/two failures: main1913cases passes(1893pass/20skip), bin622
cases fails413cleanup inode lookup and567OrbStack nonTTYdiagnostic. Python
stage did not run. No actualOrbStack installation/upgrade is established by
that failure. Operator explicitly requested automatedtests usefakes/nohuman
confirmation; updatedP2commit46a02628 preserved unchanged except additive
scope/results updates. That commit changes only the P2doc.

Complete actual stage outputs are retained verbatim in text assets:

- [Full actual M4 log 1793213637](../assets/2026-10-28-test-all-1793213637.txt)
- [Full actual M4 log 1793216188](../assets/2026-10-28-test-all-1793216188.txt)

Latest actual terminal final summary:

```text
make[1]: *** [test-bin] Error 1
[k3dm-test-metrics] 2535 cases, 2 failed
[k3dm-test-metrics] metrics pushed: test-all/local
[test-all] metrics log: /tmp/k3dm-test-all-1793216188.log
make: *** [test-all] Error 2
```

Published result after that run (actual response):

```json
{
  "data": {
    "result": [
      {
        "metric": {
          "__name__": "k3dm_test_cases_failed",
          "instance": "test-all-local",
          "job": "k3dm-tests",
          "target": "test-all"
        },
        "value": [
          1793222331.958,
          "2"
        ]
      },
      {
        "metric": {
          "__name__": "k3dm_test_last_step_reached",
          "instance": "test-all-local",
          "job": "k3dm-tests",
          "step": "test",
          "target": "test-all"
        },
        "value": [
          1793222331.958,
          "1"
        ]
      },
      {
        "metric": {
          "__name__": "k3dm_test_last_timestamp_seconds",
          "instance": "test-all-local",
          "job": "k3dm-tests"
        },
        "value": [
          1793222331.958,
          "1793217882"
        ]
      },
      {
        "metric": {
          "__name__": "k3dm_test_run_complete",
          "instance": "test-all-local",
          "job": "k3dm-tests",
          "target": "test-all"
        },
        "value": [
          1793222331.958,
          "0"
        ]
      }
    ],
    "resultType": "vector"
  },
  "status": "success"
}
```

This is the old failing acceptance result, not a post-repair green run.

## Controlled reproduction: inherited stdin TTY

The existing harness already replaces orbctl, docker, kubectl, security,
launchctl, curl, manager, hostnet and make with fake commands. Its PATH starts
with the per-testfakeHOME/bin and contains only systemdirs afterward, keeping
realHomebrewOrbStack out. Production's typedyes guard is required and unchanged.

Temporary diagnostic copy of the suite points at actual repoROOT, adds status/
output/upgrade-spy reporting to the failing case, and runs inside a synthetic
BSDscript PTY with only no input, outer30s timeout. No human terminal is used.
Baseline actual output (exit1); CRLF/backspace terminal controls normalized:

```text
^Dno
1..1
OrbStack update will restart the hub. Type yes to continue: not ok 1 orbstack upgrade: refuses a real run without a TTY
# (in test file /private/tmp/k3dm-orbstack-tty-repro/diagnostic.bats, line 240)
#   `[[ "$output" == *'interactive TTY required'* ]]' failed
# observed_status=2
# observed_output=[orbstack-upgrade] preflight: passed
# [orbstack-upgrade] preflight: refused: confirmation was not yes
# upgrade_spy_called=false
# Last output:
# [orbstack-upgrade] preflight: passed
# [orbstack-upgrade] preflight: refused: confirmation was not yes

reproduction_exit=1
```

Status2 already passed in the original test. Its output said confirmationwasnotyes,
because stdin was aTTY and the production script correctly reached the real-run
confirmation. The supposed nonTTYcase was not explicitly nonTTY. The upgrade
spy was false. This reproduces a prompt only in the syntheticterminal, not proof
of any real update or a particular human prompt during the original run.

## Test-only repair

A shared per-suite bounded runner launches the fixture command with DEVNULL
stdin and a new session, captures output and enforces30s timeout. It kills only
the owned childprocessgroup on timeout and uses bounded cleanup waits. The
nonTTYcase now checks expectedstatus/message, no confirmation text and no
upgrade-spy call. SimulatedTTYyes/no cases use the same outer bound around
their fakePTYpipeline; all host actions remainstubs. A new one-second stalled
fakecommand test proves timeout124 rather than indefinite waiting.

Linuxscript uses -e to return childstatus, as documented by the
[util-linux manual](https://man7.org/linux/man-pages/man1/script.1.html).
Actual Linuxexecution is not performed on this Darwinhost; that platform
remains a CI check, not a claimed pass. No CI reruns or new dependencies.

Same isolated syntheticTTY after repair (exit0, expectedrefusal, no prompt,
spyfalse); terminal controls normalized as above:

```text
^Dno
1..1
ok 1 orbstack upgrade: refuses a real run without a TTY
# observed_status=2
# observed_output=[orbstack-upgrade] preflight: passed
# [orbstack-upgrade] preflight: refused: interactive TTY required; no update was started
# upgrade_spy_called=false

reproduction_exit=0
```

Case413's exact original failure is stat illegaloption-c onDarwin, before
cleanup. Replace only the test's inode observation with Pythonos.stat; keep
asserting the actual fileinode is unchanged after truncation/rotation. No
productioncleanup behavior changed and no inode identity assertion removed.

## Final focused gates

Command: scripts/tests/tripwire.sh bats --print-output-on-failure
scripts/tests/bin/orbstack_upgrade.bats scripts/tests/bin/k3dm_cleanup.bats.
Full actual output (exit0,30passed/no skips; previously29tests,+1timeoutcase):

```text
1..30
ok 1 orbstack upgrade: fresh compact last-success timestamp passes preflight
ok 2 orbstack upgrade: refuses a compact last-success timestamp older than 24 hours
ok 3 orbstack upgrade: refuses a missing or malformed last-success marker
ok 4 orbstack upgrade: FORCE overrides only no-update status
ok 5 orbstack upgrade: refuses active dispatch and lifecycle work
ok 6 orbstack upgrade: refuses wrong context or absent DR copy
ok 7 orbstack upgrade: refuses a real run without a TTY
ok 8 orbstack upgrade: bounded fixture runner stops a stalled fake command
ok 9 orbstack upgrade: typed no refuses without running orbctl update
ok 10 orbstack upgrade: watchdog unseals when Vault stays sealed and skips DR when it unseals
ok 11 orbstack upgrade: repoints only after UID change and an invalid SecretStore
ok 12 orbstack upgrade: repairs drift, republishes metrics, and kicks only dead port-forwards once
ok 13 orbstack upgrade: a hub that is ready when the deadline passes is not a failed upgrade
ok 14 orbstack upgrade: forecast probe drains large metrics producer to completion
ok 15 orbstack upgrade: reports empty regressions for equal counts and names a count drop
ok 16 orbstack upgrade: failed unseal does not stop later recovery and verification
ok 17 orbstack upgrade: never deletes Kubernetes objects or reads Keychain values
ok 18 orbstack upgrade: destructive and credential guard assertions are effective
ok 19 k3dm-cleanup prunes old finished jobs but keeps stale running jobs
ok 20 k3dm-cleanup enforces the finished-job count cap oldest first
ok 21 k3dm-cleanup rotates oversized launchd logs in place
ok 22 k3dm-cleanup prunes old repo-owned tmp leftovers and keeps recent ones
ok 23 k3dm-cleanup prunes old repo-owned run-dir leftovers and keeps recent ones
ok 24 k3dm-cleanup prunes only placeholder TemporaryDirectory folders
ok 25 k3dm-cleanup keeps the five newest screenshots
ok 26 k3dm-cleanup removes old Packer artifacts and port markers only
ok 27 k3dm-cleanup removes old orphaned volumes and keeps everything else
ok 28 k3dm-cleanup can disable Docker volume pruning
ok 29 k3dm-cleanup prunes weekly caches on the prune day
ok 30 k3dm-cleanup skips weekly caches off the prune day
```

Raw shellcheck -x -S warning on both touchedBATS files exited0/no output.
BATS validates its ownDSLsyntax; no plain bash-n applied to BATS. gitdiffcheck
clean. Production bin/k3dm-orbstack-upgrade and bin/k3dm-cleanup unchanged.
No realOrbStack upgrade/install, hostrestart/Keychainlookup/metricspush/full
publishedrerun by coordinator. Required lint/audit/checkpoint hooks before
commit; P2remainsOPEN pending freshcomplete3-stage acceptance.
