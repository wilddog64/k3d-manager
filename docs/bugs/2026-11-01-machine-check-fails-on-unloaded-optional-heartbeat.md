# Bug: `make machine-check ROLE=hub` can never pass, because the never-loaded heartbeat agent counts as missing

**Status:** OPEN
**Priority:** P3
**Severity:** low — the hub check exits 1 on every run even when every real item is ok, so a real failure is hidden behind a permanent red; no runtime impact
**Approval:** operator, 2026-11-01 ("then file a P3 and dispatch to Luna")
**Filed:** 2026-11-01
**Detected by:** operator (`make machine-check ROLE=hub` on the M5), root cause by Claude
**Affected:** `bin/k3dm-machine-setup` (`run_one_agent`, `render_heartbeat`)
**Branch:** `k3d-manager-v1.43.13`
**Related:** `docs/bugs/2026-10-26-independent-heartbeat-healthchecks-monitoring.md` (the heartbeat feature; provider enrollment still pending); `docs/plans/v1.43.12-one-command-machine-setup.md` (its live check E4 was left open on this row)

## Observed failure

On the M5 hub at `88813427`, from a local Terminal on 2026-11-01:

    agent:bin/k3dm-hermes-setup      ok
    agent:bin/k3dm-heartbeat-setup   missing
    make: *** [machine-check] Error 1

Every other line in the report was `ok`. `~/.local/share/k3d-manager/heartbeat-candidates/` on the M5 holds
`com.k3d-manager.heartbeat.plist` and `heartbeat.json` (read-only listing, 2026-11-01).

## Root cause

- `scripts/etc/machine/agents.hub.list` lists `bin/k3dm-heartbeat-setup`, and the agent check reports `ok` only when
  `~/Library/LaunchAgents/com.k3d-manager.heartbeat.plist` exists.
- By design, setup never installs that plist. `render_heartbeat` only writes review candidates, and then always calls
  `record_failure "agent:bin/k3dm-heartbeat-setup" 'missing (review candidates: ...)'`.
  `scripts/etc/machine/not-installed.list` records the same intent: "renders a review candidate only".
- Loading the heartbeat needs provider enrollment and ping URLs (see the 2026-10-26 bug), which no hub has ever had. So
  the hub check fails permanently on an item that setup itself chose not to install.

## Fix

1. In `bin/k3dm-machine-setup`, for `bin/k3dm-heartbeat-setup` only:
   - plist present in `~/Library/LaunchAgents`: report `ok`, exactly as today.
   - plist absent, check mode: `report "agent:bin/k3dm-heartbeat-setup" 'not loaded (optional; review candidates: docs/howto/independent-heartbeats.md)'`. Use `report`, not `record_failure`.
   - plist absent, setup mode: render the candidates as today when they are absent, then report the same `not loaded`
     line through `report`. If the render fails, keep `record_failure ... 'missing (candidate render failed)'`.
   - `AGENTS=skip` and the worker/console role behaviour stay as they are.
2. Every other agent keeps its current behaviour: a missing plist is still a failure.
3. `docs/howto/independent-heartbeats.md`: one sentence saying machine setup reports the heartbeat as `not loaded
   (optional)` until the operator loads it, and `ok` after.

## Files

- `bin/k3dm-machine-setup`
- `scripts/tests/bin/machine_setup.bats`
- `scripts/tests/bin/machine_setup_acceptance.bats`
- `docs/howto/independent-heartbeats.md`
- `CHANGELOG.md`

## What NOT to do

- Do not load, bootstrap or copy the heartbeat plist into `~/Library/LaunchAgents`, and do not call `launchctl`.
- Do not remove `bin/k3dm-heartbeat-setup` from `agents.hub.list` or change `not-installed.list`.
- Do not make other agents optional, and do not add a general "optional agent" mechanism.
- Do not read or edit the heartbeat config or any ping URL.

## Acceptance

```yaml
must:
  M1: on the hub role in check mode, with no heartbeat plist in LaunchAgents and every other item complete, the report shows agent:bin/k3dm-heartbeat-setup "not loaded (optional; ...)" and the run exits 0
  M2: with the heartbeat plist present in LaunchAgents, the same check reports agent:bin/k3dm-heartbeat-setup ok and exits 0 (paired with M1)
  M3: in setup mode with no plist, candidates are rendered when absent and the line is "not loaded (optional; ...)"; when the candidate render fails, the line is "missing (candidate render failed)" and the run exits nonzero
must_not:
  N1: machine setup never writes com.k3d-manager.heartbeat.plist into LaunchAgents and never calls launchctl for it
  N2: a missing plist for any other hub agent (for example bin/k3dm-webhook-setup) still reports missing and exits nonzero, also when the heartbeat line is "not loaded"
evidence:
  E1:
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    intent: >-
      You will see machine_setup.bats and machine_setup_acceptance.bats run setup in a scratch HOME (the fixture first
      asserts HOME and stubs are under the test tmpdir) on a complete hub with the heartbeat plist absent (not loaded,
      exit 0), present (ok, exit 0), and with the webhook plist removed (missing, exit 1); then setup mode with a
      failing bin/k3dm-heartbeat-setup stub (exit 1). A command log shows no launchctl call and no heartbeat plist under
      the scratch LaunchAgents. N2 fails on a mutant that reports every missing agent through report.
    what: bats scripts/tests/bin/machine_setup.bats scripts/tests/bin/machine_setup_acceptance.bats
  E2:
    proves: [M1]
    kind: live
    intent: >-
      You will see make machine-check ROLE=hub in a local M5 Terminal print agent:bin/k3dm-heartbeat-setup not loaded
      (optional; ...) and exit 0, which also closes the open E4 of docs/plans/v1.43.12-one-command-machine-setup.md.
    what: operator on the M5, Claude reads the report
interface:
  - bin/k3dm-machine-setup (role hub; --check and setup; AGENTS; scratch HOME with Library/LaunchAgents)
  - scripts/etc/machine/agents.hub.list
```
