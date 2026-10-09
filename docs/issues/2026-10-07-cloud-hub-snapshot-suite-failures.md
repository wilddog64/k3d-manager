# Cloud `make-test-all` reported six hub snapshot failures

## Observed cloud result

Cloud job `5cda3d09` reported exit code 2 and these six failed cases:

```text
198 Observability passes namespace and branch to envsubst
970 Hub snapshot emits restore layout
971 Snapshot tree names satisfy recovery claims
972 Node placement comes from the PV
974 Capture avoids remote free-space probes
981 Staging directory permissions are 0700
```

The returned response did not include complete BATS assertion diagnostics for the hub snapshot
cases, so it does not establish whether these are six independent failures. Cases 970, 971, 972,
974, and 981 all exercise the same snapshot capture setup and may share one cloud-only failure.

## Local reproduction

The focused suite currently passes:

```text
1..14
ok 1 hub snapshot: capture emits the restore layout
ok 2 hub snapshot: tree names satisfy the hub recovery claim tree
ok 3 hub snapshot: node placement comes from the PV
ok 4 hub snapshot: unbound claim fails closed
ok 5 hub snapshot: capture probes no remote free space
ok 6 hub snapshot: checksum mismatch marks incomplete
ok 7 hub snapshot: prune keeps the configured verified snapshots
ok 8 hub snapshot: prune removes incomplete snapshots first
ok 9 hub snapshot: prune refuses zero verified snapshots
ok 10 hub snapshot: unreachable M2 names the host and leaves no remote directory
ok 11 hub snapshot: staging is removed after a mid-capture failure
ok 12 hub snapshot: staging directory is 0700
ok 13 hub snapshot: Loki record is present
ok 14 hub snapshot: remote dir default survives single-quoting on the remote shell
```

The complete local BATS dispatcher also passes all `1,384` cases, including cloud-reported cases
198, 970, 971, 972, 974, and 981. The local run emitted only the expected tripwire notices for
blocked host tools and exited zero.

## Follow-up

Run `bats --formatter tap13 scripts/tests/plugins/hub_snapshot.bats` in the same cloud worker and
preserve the complete output, including the first failing assertion and command output. Do not
change snapshot behavior until the cloud-only failure is reproducible.
