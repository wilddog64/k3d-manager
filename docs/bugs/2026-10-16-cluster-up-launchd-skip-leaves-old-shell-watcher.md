# Bug: cluster-up leaves an older in-shell ACG watcher running when launchd owns the watcher

**Status:** OPEN — not started
**Priority:** P3
**Filed:** 2026-10-16
**Detected by:** Claude, live check of `docs/bugs/2026-10-16-cluster-up-shell-acg-watcher-writes-to-terminal.md`
**Affected:** `scripts/lib/providers/k3s-aws.sh` `_k3s_aws_start_watcher`
**Branch:** `k3d-manager-v1.43.4`
**Approval:** pending — operator to confirm placement

## Problem

When `com.k3d-manager.acg-watch` is loaded, `_k3s_aws_start_watcher` returns before it reads
`acg-watch.pid`. If an earlier run left an in-shell watcher alive, two watchers run: launchd's
and the old shell one, and the old one keeps writing `[acg]` lines into the terminal that ran it.

Seen 2026-10-16: PID 89270 (`bash bin/cluster-up`, started 06:01 local by a `make up` before
`ca6b59ce`) was still alive after two post-fix `make up` runs. Each run logged "skipping
in-shell watcher". The operator stopped it by hand with `kill 89270`.

This recurs whenever launchd's watcher is reloaded while a shell watcher is alive (the operator
ran `launchctl unload` earlier the same day), so it is not only a one-time migration.

## Fix

In the launchd branch, before `return 0`: if `acg-watch.pid` names a live process, stop it
(`kill`, then confirm it exited) and remove the file; log one line that says so. If the PID is
dead, just remove the file.

## Proof

BATS: launchd loaded + a live PID-file process → the process is gone and the file removed;
launchd loaded + a dead PID → file removed, nothing killed. Each test fails on the current code.
Live: the next `make up` with a stale shell watcher present logs the stop, leaves only launchd's
watcher, and the PID file is gone.
