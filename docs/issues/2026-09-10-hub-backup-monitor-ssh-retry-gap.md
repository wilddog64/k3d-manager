# Hub backup monitor did not retry an M2 SSH interruption

## What was attempted

The controlled hub recovery copied the independently captured K3s datastore and
seven durable local-path claim trees from M4 to M2. The initial temporary tmux
monitor treated any terminated `rsync` session without its final summary as a
hard failure.

## Actual output

```text
ssh: connect to host 192.168.39.164 port 22: Operation timed out
COPY_FAILED_OR_INTERRUPTED
```

The destination had reached 15.6 GiB before the interruption. A subsequent
interactive `ssh m2-air.local` succeeded. Resuming with `rsync --partial`
completed without recopying the already transferred bytes:

```text
2026-09-10T22:29:46Z COPY_TRANSFER_COMPLETE
COPY_COMPLETE_CHECKSUM_VERIFYING
COPY_CHECKSUM_VERIFIED
```

## Root cause

The monitor had no bounded retry behavior for a transient MeshHome SSH outage.
It exited before the operator checked its state, and the interruption was not
reported proactively.

## Fix and follow-up

The temporary recovery monitor now uses a bounded retry loop (120 attempts,
60-second interval) around the resumable `rsync --partial` transfer. It runs
the checksum comparison only after a transfer-complete marker. The source and
M2 copies remain retained; no cluster or Docker volume was deleted.

The durable project command is being implemented separately in
`scripts/plugins/hub_recovery.sh`; its source mapping is validated by logical
claim, never raw PVC UID or a wildcard path.
