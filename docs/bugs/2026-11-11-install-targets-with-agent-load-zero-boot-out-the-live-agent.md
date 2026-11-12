# Bug: `install-*` with `K3DM_AGENT_LOAD=0` boots out the live agent it promises not to load

**Status:** VERIFIED 2026-11-11 — `bc09f24f` (Flash 3.8 worker, reviewed and landed by Claude). E1 red on pre-fix `5360d714`, green after (43/43 with hub_new.bats); live E3 on m4-air with the real launchctl: repo-sync stayed loaded, runs 8 → 8, no bootout in the launchd log.
**Priority:** P2
**Severity:** Low. A warning alert. The agent stays unloaded until someone reloads it.
**Introduced by:** bd68d6ff (v1.43.12, `K3DM_AGENT_LOAD=0` guard added beside an existing unconditional bootout)
**Should have been caught by:** offline test
**Prior art:** `make find-similar-docs` unavailable (vector store context `k3d-k3d-cluster` missing); exact-slug glob: none. Related, different root cause: `docs/bugs/2026-11-11-cluster-up-vault-port-forward-reload-race-fails-and-unloads-hub-agent.md`.
**Approval:** operator, 2026-11-11: "probably should file a P2 bug and dispatch to Flash 3.8" (raised from P3; Claude agreed: it paged once and the only workaround is a manual reload). Same message approves intents E1–E3.
**Intent approved:** operator, 2026-11-11

## What happened

On 2026-11-11 at 04:13:18 PST, Claude tested a Makefile change on the M4 with
`make -s install-repo-sync HOME=<scratch> K3DM_AGENT_LOAD=0` and no launchctl stub. The run unloaded
the real `com.k3d-manager.repo-sync` agent. launchd's log names the caller:

    04:13:18.164 launchd: [gui/501/com.k3d-manager.repo-sync:] bootout initiated by:
      launchctl[27551]<-bash[27548]<-make[27533]<-zsh[27441]<-2.1.321[7067]<-...
    04:13:18.164 launchd: removing service: com.k3d-manager.repo-sync

The last sync ran at 04:13:06. One hour later `K3dmRepoSyncStale` (instance `m4-air`, result `stale`)
fired and emailed the operator. Reloading with `launchctl bootstrap` fixed it at 08:13: a fresh run, k3d-manager `current`.

## Root cause

Each singleton installer runs an unconditional, label-scoped bootout before its `K3DM_AGENT_LOAD` guard:

    launchctl bootout "gui/$$(id -u)/com.k3d-manager.<label>" 2>/dev/null || true
    if [ "$(K3DM_AGENT_LOAD)" != 0 ]; then launchctl bootstrap ...; fi

`K3DM_AGENT_LOAD=0` means "write the plist, do not load" (the hub-new staging mode). In that mode
the agent still gets unloaded, and nothing loads it again. Because the bootout targets the label, not the
plist path, overriding `HOME` does not isolate it: a run with a scratch HOME still hits the operator's
real agent.

Affected targets (Makefile, 2026-11-11): `install-repo-sync` (:64), `install-cleanup` (~:101),
`install-node-health-watch` (~:671), `install-sandbox-reaper` (~:685), cloud-bridge (~:821). Others among
the 17 `launchctl bootout` lines may share the pattern; the fix spec lists each one.

`hub_new.bats` M5 does not catch this, because it stubs `launchctl` and asserts only that nothing is
bootstrapped, loaded or kickstarted. It never asserts that nothing was booted out.

## Workaround

`launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.k3d-manager.<label>.plist`

## Fix

Make `K3DM_AGENT_LOAD=0` write-only everywhere it is honoured: no `launchctl bootout`, `unload`,
`bootstrap`, `load` or `kickstart` in that mode. Move each target's bootout inside the
`K3DM_AGENT_LOAD != 0` branch, so the unset mode keeps its bootout-then-bootstrap reload.

Scope: every Makefile target that reads `K3DM_AGENT_LOAD` (repo-sync :61-71, cleanup ~:655, node-health-watch
~:665, sandbox-reaper ~:680, cloud-bridge ~:815, test-metrics :96, and any other `install-*` that `bin/hub-new:94`
or `:105` invokes with `K3DM_AGENT_LOAD=0`, such as `install-prometheus-credential-rotator` and
`snapshot-schedule`). Audit the shell readers listed under Contract readers too. Change one only where a
bootout or unload runs in the `0` mode; leave a reader untouched when it already guards both.

Out of scope: `uninstall-*` targets (unloading is their job), the label-scoped bootout form itself, and
`install-webhook-token-rotate` (it does not read `K3DM_AGENT_LOAD`).

## Files

- `Makefile`
- `scripts/tests/bin/hub_new.bats`
- `scripts/tests/bin/makefile_agent_load.bats` (new, if not folded into hub_new.bats)
- Shell readers under Contract readers only if the audit finds a bootout in the `0` mode.

## Acceptance

```yaml
must:
  - id: M1
    text: with K3DM_AGENT_LOAD unset, each install target in scope still boots out and then bootstraps its agent (re-install reloads)
  - id: M2
    text: with K3DM_AGENT_LOAD=0, each install target in scope still writes its plist under $HOME/Library/LaunchAgents
must_not:
  - id: N1
    text: with K3DM_AGENT_LOAD=0, any install target in scope or shell reader issues launchctl bootout, unload, bootstrap, load or kickstart
evidence:
  - id: E1
    proves: [N1, M2]
    kind: offline
    intent: "with a fake launchctl that records its calls, each in-scope install target run with K3DM_AGENT_LOAD=0 writes its plist and records no launchctl call at all; the test fails on today's Makefile (repo-sync, cleanup and the others boot out)"
  - id: E2
    proves: [M1]
    kind: offline
    intent: "the same targets with K3DM_AGENT_LOAD unset record a bootout followed by a bootstrap for their own label (positive control for E1)"
  - id: E3
    proves: [N1]
    kind: live
    intent: "on the M4, after landing, Claude runs `make install-repo-sync HOME=<scratch> K3DM_AGENT_LOAD=0` with the real launchctl and `launchctl print gui/501/com.k3d-manager.repo-sync` still shows the agent loaded, with its run count unchanged"
interface:
  - make -s -C <repo> install-<target> HOME=<scratch> K3DM_AGENT_LOAD=0|unset  (launchctl resolved from PATH)
```

## Contract readers

`K3DM_AGENT_LOAD` (env var; `0` = write plists, load nothing). Found by `grep -rn K3DM_AGENT_LOAD bin scripts Makefile`
on 2026-11-11.
- Writer: `bin/hub-new:24` (exports `0`), `:88`, `:94-105` (per installer). Unchanged; its semantics become what it already assumed.
- Makefile readers `:65`, `:102`, `:662`, `:672`, `:686`, `:822` (+ any other `install-*` found by the worker): change, bootout moves into the load branch.
- `bin/k3dm-webhook-setup:34,42,59,104`, `bin/k3dm-hermes-setup:28`, `scripts/lib/cloudflare_tunnel.sh:60,65,78`,
  `scripts/plugins/acg.sh:76,92`, `hub_data.sh:516`, `hub_snapshot.sh:353`, `observability.sh:266`, `vault.sh:1407`,
  `tunnel.sh:232`: audit only. Each appears to guard its launchctl calls already; change one only if a bootout runs in the `0` mode.
- Test reader `scripts/tests/bin/hub_new.bats:209,413,423,428`: extend M5 to assert no bootout (it checks only bootstrap/load/kickstart today).

## Worker definition of done

- Every in-scope target changed. Report a table: target, line, bootout before → after, and audited shell readers with "already guarded" or "changed".
- New or extended BATS in `scripts/tests/bin/` (prefer `hub_new.bats` M5 or a new `makefile_agent_load.bats`). It
  puts a recording `launchctl` stub first on PATH, asserts `command -v launchctl` is the stub, and sets HOME to a scratch dir.
  It never invokes the real launchctl.
- Show E1 red against the pre-fix Makefile (`git stash` or a copy), then green.
- `bats scripts/tests/bin/hub_new.bats` and the new file pass; `make -n` must never be used on lifecycle targets.
- Commit on the worktree branch. Do not push.
