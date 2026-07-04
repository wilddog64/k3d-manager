# Run-dir migration for repo-owned debug artifacts

## What was tested

- Producer search for:
  - `k3dm-ask-*.out`
  - `k3d-manager-acg-watch.out`
  - `k3d-manager-acg-watch.err`
  - the listed `alertmanager-*.html`, `alertproxy-*.log`, and `k3d-status*.out` names
- Cleanup coverage for `~/.local/share/k3d-manager/run`
- Local wrapper behavior around the generated ACG watch launchd plist

## Actual output

Checked-in producers were found for:

- `k3dm-ask-*.out` in `bin/k3dm-webhook`
- `k3d-manager-acg-watch.out|err` in the generated ACG watcher plist path (via the local `scripts/plugins/acg.sh` wrapper around the absorbed foundation helper)

The following listed names were **not** found as checked-in output paths:

- `alertmanager-host.html`
- `alertmanager-local.html`
- `alertmanager-localhost.html`
- `alertmanager-root.html`
- `alertproxy-bats.log`
- `alertproxy-second.log`
- `k3d-am-status.out`
- `k3d-status-trace.out`
- `k3d-status.out`

Those names are consistent with manual local redirects or one-off debug captures, not with committed producers in the repo.

## Root cause

The repo had no dedicated run-artifact directory contract for these transient debug files. Some script-owned artifacts still wrote to `/tmp`, while other filenames in the inventory were never repo-owned to begin with and therefore could not be relocated by changing checked-in code alone.

## Fix

- `bin/k3dm-webhook` now writes `/ask` subprocess captures into `~/.local/share/k3d-manager/run`.
- `scripts/plugins/acg.sh` now rewrites the generated ACG watch launchd plist so the watcher logs go to `~/.local/share/k3d-manager/run/k3d-manager-acg-watch.out|err` without editing the vendored foundation subtree.
- `bin/k3dm-cleanup` now prunes old run-dir artifacts, including:
  - `alertmanager-*.html`
  - `alertproxy-*.log`
  - `k3d-*.out`
  - `k3dm-ask-*.out`
  - `k3d-manager-acg-watch.out|err`
  - `k3dm_smoke*.out`
  - `k3dm-worker-smoke.*`
  - `k3dm-products.json`
- `docs/howto/launchd-daemons.md` now documents the ACG watch log location under the run dir.

## Notes

- Manual commands like `make status > /tmp/k3d-status.out` can still create `/tmp` files outside repo control. The cleanup script can prune them if they are written under `~/.local/share/k3d-manager/run`, but the repo cannot prevent ad hoc shell redirection to arbitrary paths.
