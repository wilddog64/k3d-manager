# repo-sync's launchd job has no PATH, so the hub's appsets-check is always unknown

**Status:** OPEN — found 2026-11-11 by the Fable pre-PR review of v1.43.15; confirmed by Claude on the M4 (launchd PATH) and the M5 (live state)
**Priority:** P2
**Waiting on:** dispatch — since 2026-11-11
**Introduced by:** `f310b4d4` (v1.43.15 checkout-auto-sync)
**Should have been caught by:** live check
**Prior art:** none above threshold — exact-slug glob empty; `find-similar-docs` unavailable (vector store context missing); `grep -lE 'launchd.*PATH|EnvironmentVariables' docs/bugs` found only older PyYAML/port-forward docs, different root cause
**Approval:** operator, 2026-11-11 ("approve two P2s")
**Intent approved:** operator, 2026-11-11

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

## Live corroboration 2026-11-11 (Claude, M5)

After the operator ran `make appsets-reapply`, an interactive `make appsets-check` on the hub printed `All Applications reference values branch deploy/hub` (0 Apps on `k3d-manager-v1.43.15`), yet the launchd-written state.json still read `deploy_unknown: ['appsets-reapply']`. The check passes from a shell with Homebrew on PATH and fails from the job.

## Definition of done (worker)

Before your last message, do all of these and paste the evidence:
1. Run every test suite that covers a file you changed, not only the new tests. For each, give the command, the exit
   code and every error line. An error you can't explain is a failure, not a pass. If the sandbox blocks a test, say
   so and name it; don't skip it silently.
2. For each `must_not` item: break the guard that enforces it (comment out the check, invert the condition), run its
   test, show it red, then restore the guard and show it green. List any `must_not` whose test stayed green with the
   guard broken.
3. Where the spec allows a read-only run against real data (a real file, a real ledger, a real container image), run
   the changed code once that way and paste what it printed. Otherwise say "no read-only real-data run possible" and
   why.
4. List every place where you chose something the spec did not decide (a default, a path, a mode, an edge case).
