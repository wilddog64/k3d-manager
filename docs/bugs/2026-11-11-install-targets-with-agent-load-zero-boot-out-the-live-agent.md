# Bug: `install-*` with `K3DM_AGENT_LOAD=0` boots out the live agent it promises not to load

**Status:** OPEN
**Priority:** P3
**Waiting on:** dispatch — since 2026-11-11
**Severity:** Low. A warning alert. The agent stays unloaded until someone reloads it.
**Introduced by:** bd68d6ff (v1.43.12, `K3DM_AGENT_LOAD=0` guard added beside an existing unconditional bootout)
**Should have been caught by:** offline test
**Prior art:** `make find-similar-docs` unavailable (vector store context `k3d-k3d-cluster` missing); exact-slug glob: none. Related, different root cause: `docs/bugs/2026-11-11-cluster-up-vault-port-forward-reload-race-fails-and-unloads-hub-agent.md`.
**Approval:** filed by Claude, 2026-11-11; triage at the next `/release-groom`.

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

## Fix direction

Move the bootout inside the `K3DM_AGENT_LOAD != 0` branch, so the `0` mode is write-only. Extend
`hub_new.bats` M5 (or the installer tests) to assert that no `launchctl bootout` is issued with
`K3DM_AGENT_LOAD=0`, paired with the existing positive control that the unset mode still bootstraps.
Write the Acceptance block before dispatch.
