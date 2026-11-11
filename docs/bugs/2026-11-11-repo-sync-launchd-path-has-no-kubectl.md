# repo-sync's launchd job has no PATH, so the hub's appsets-check is always unknown

**Status:** OPEN — found 2026-11-11 by the Fable pre-PR review of v1.43.15; confirmed by Claude on the M4 (launchd PATH) and the M5 (live state)
**Priority:** P2
**Waiting on:** operator decision — since 2026-11-11 (intent approval, then dispatch in v1.43.15 with the fetch bug, same file)
**Introduced by:** `f310b4d4` (v1.43.15 checkout-auto-sync)
**Should have been caught by:** live check
**Prior art:** none above threshold — exact-slug glob empty; `find-similar-docs` unavailable (vector store context missing); `grep -lE 'launchd.*PATH|EnvironmentVariables' docs/bugs` found only older PyYAML/port-forward docs, different root cause
**Approval:** pending

## Symptom

On the M5, `~/.local/share/k3d-manager/repo-sync/state.json` reads `deploy_unknown: ['appsets-reapply']`,
`deploy_pending: []` (read over ssh by Claude, 2026-11-11). `K3dmDeployPending{step="appsets-reapply"}` therefore can
never fire from the timer.

## Root cause

`scripts/etc/launchd/com.k3d-manager.repo-sync.plist.tmpl` sets no `EnvironmentVariables`, so the job runs with
launchd's default `PATH => /usr/bin:/bin:/usr/sbin:/sbin` (`launchctl print gui/501/com.k3d-manager.repo-sync` on
the M4, 2026-11-11). Under that PATH, `command -v kubectl gh` finds neither. `/usr/bin/python3` and `/bin/bash` 3.2
resolve (the dispatcher re-execs Homebrew bash itself). `make appsets-check` reaches `_kubectl`
(`scripts/lib/foundation/scripts/lib/system.sh:1107`), which calls `_install_kubernetes_cli` when kubectl is missing.
The 15 s timeout or the failure lands as unknown (`bin/k3dm-repo-sync:301-307`). The M5 has no `~/.local/bin/kubectl`.
Not yet shown: which of timeout or failure it is on the M5.

## Impact

The deploy-pending report for ApplicationSets is blind on the hub, and launchd may attempt a kubectl install every five
minutes. v1.44.0 `deploy-hub-behind-alert` would hit the same wall for `gh`. Workaround: `make appsets-check` by hand
from the operator's shell.

## Fix direction

Add `EnvironmentVariables` with `PATH` (Homebrew first: `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`)
to the plist template, so `make install-repo-sync` renders it. Do not install tools from the job.

## Contract readers

The template's only reader is `Makefile:63` (`install-repo-sync`, `sed` render to `~/Library/LaunchAgents`); it is
unchanged, since the new key has no placeholder. No test reads the template today
(`grep -rln 'repo-sync.plist\|com.k3d-manager.repo-sync' bin scripts Makefile`, 2026-11-11), so E1 adds the first.
The job's environment is read by `bin/k3dm-repo-sync` and everything it runs (`make appsets-check`, `git`); they now
resolve Homebrew tools first.

## Acceptance

```yaml
must:
  - M1: the rendered repo-sync plist sets PATH with /opt/homebrew/bin ahead of /usr/bin
must_not:
  - N1: the job, run with only the rendered plist's environment, invokes an installer for kubectl or gh
evidence:
  - E1: {proves: [M1], offline: true, intent: "the timer job can find kubectl and gh the same way your shell does"}
  - E2: {proves: [N1], offline: true, intent: "the timer never tries to install tools on its own"}
  - E3: {proves: [M1], live: true, intent: "on the M5 after install-repo-sync, state.json no longer lists appsets-reapply as unknown"}
interface:
  - scripts/etc/launchd/com.k3d-manager.repo-sync.plist.tmpl (rendered by make install-repo-sync with stubbed launchctl)
  - bin/k3dm-repo-sync
```

## Files

- `scripts/etc/launchd/com.k3d-manager.repo-sync.plist.tmpl`
- `scripts/tests/bin/repo_sync_launchd_env.bats` (new)
