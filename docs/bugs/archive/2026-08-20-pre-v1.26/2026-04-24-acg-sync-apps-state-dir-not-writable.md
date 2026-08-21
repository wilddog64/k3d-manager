# Bug: `bin/acg-sync-apps` default state directory is not writable in restricted environments

**Date:** 2026-04-24
**Status:** COMPLETE (`890ba2a6`)
**Branch:** `k3d-manager-v1.1.0`

## Problem

`bin/acg-sync-apps` persists its managed port-forward metadata and log file under a default
state directory. In this environment, the home-directory path was not writable, so the script
failed immediately while trying to create:

```text
~/.local/share/k3d-manager/acg-sync-apps-argocd-pf.log
~/.local/share/k3d-manager/acg-sync-apps-argocd-pf.env
```

## Root Cause

The script defaulted to a home-directory state path instead of a temp-backed location. That
works on a normal workstation, but it is brittle in restricted shells and sandboxed runs.

## Fix

`bin/acg-sync-apps` now defaults its state directory to `${TMPDIR:-/tmp}/k3d-manager` and
creates it before the port-forward starts, so the managed log/state files can be written in
restricted environments.

## Validation

`shellcheck -x bin/acg-sync-apps` passes, and `make sync-apps` now gets past the state-file
write path. In this sandbox the remaining failure is the cluster connection itself, which is
tracked separately in `docs/issues/2026-04-24-acg-sync-apps-live-port-forward-connect-operation-not-permitted.md`.

## Impact

Medium. This blocks `make sync-apps` entirely when the default state directory is not writable.
