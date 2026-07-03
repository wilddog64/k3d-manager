# tmp leftovers cleanup coverage gap

## What was tested

- `/private/tmp` inventory on the macOS host
- Existing `bin/k3dm-cleanup`
- Existing `make clean-tmp`

## Actual output

Representative `/private/tmp` contents included:

```text
TemporaryDirectory.4fVva6
TemporaryDirectory.6DiIiP
TemporaryDirectory.9CXJXv
bats-run-5tmr8K
k3d-manager-acg-watch.err
k3d-manager-acg-watch.out
k3dm-ask-4_raloi2.out
k3dm-gcp-creds.qtLwyM
playwright-artifacts-0wbZ47
playwright-artifacts-3bJU2P
```

Sample `TemporaryDirectory.*` inspection showed they were stale placeholders:

```text
/private/tmp/TemporaryDirectory.GMV7m3
/private/tmp/TemporaryDirectory.GMV7m3/.keep-directory
```

The cleanup script only handled:

- archived failure PNGs under `~/.local/share/k3d-manager`
- `/tmp/k3dm-acg-screenshot-*.png` (keep newest 5)
- `/tmp/playwright-artifacts-*` older than one day

## Root cause

`bin/k3dm-cleanup` was too narrow for the current temp-file footprint. It did not prune:

- stale `bats-run-*` directories,
- stale `k3dm-ask-*.out` transcripts,
- stale `k3d-manager-*.out|err` logs,
- stale `k3dm-gcp-creds.*`, `argocd-*.sock`, `k3d-config-tmp-*.yaml`, `k3d-hostsfile-*`, or `k3s-etcd-*.db`,
- placeholder `TemporaryDirectory.*` directories that contain only `.keep-directory`.

## Fix

- Expanded `bin/k3dm-cleanup` to prune stale repo-owned temp files by age from `${K3DM_TMP_ROOT:-/tmp}`.
- Added guarded cleanup for `TemporaryDirectory.*` only when the directory is older than the retention window and contains exactly one file: `.keep-directory`.
- Added regression coverage in `scripts/tests/bin/k3dm_cleanup.bats`.
- Updated `docs/howto/launchd-daemons.md` to describe the real cleanup-agent behavior.

## Recommended follow-up

- Keep generic temp cleanup narrowly scoped to known-safe patterns.
- Do not add broad `rm -rf /tmp/TemporaryDirectory.*` behavior without verifying contents first.
