# Bug: machine setup installs the gemini-cli formula, which Homebrew disables on 2026-12-18

**Status:** LIVE-VERIFIED
**Live evidence:** 2026-11-01 · run machine-check-m5-hub · env m5-air · scenario machine-check-role-hub · commit f2369dbb · proves E2
**Fix commit:** 955b979e
**Priority:** P3
**Severity:** low — today it installs and works; from 2026-12-18 `brew install gemini-cli` fails, so setup on a new machine reports `brew:gemini-cli missing` and exits 1
**Approval:** operator, 2026-11-01 ("file as you ranked and dispatch to Luna")
**Filed:** 2026-11-01
**Detected by:** Claude, from the Homebrew warning in the M4 and M5 `machine-setup.log`
**Affected:** `scripts/etc/machine/brew.hub.list`, `scripts/etc/machine/brew.worker.list`, `bin/k3dm-machine-setup`, `docs/howto/m5-hub-migration.md`
**Branch:** `k3d-manager-v1.43.13`
**Related:** `docs/bugs/2026-10-31-machine-setup-installs-wrong-gemini-and-no-agy.md` (added the formula and the `ai:` checks, `87c8d685`, `20c9bc74`)

## Observed failure

On 2026-10-31, `brew install gemini-cli` on both Macs printed:

    Warning: gemini-cli has been deprecated because it is not supported upstream! It will be disabled on 2026-12-18.
    Replacement:
      brew install --cask antigravity-cli

`20c9bc74` made a missing `ai:gemini` a check failure. Once the formula is disabled, a fresh machine cannot satisfy
either the `brew:gemini-cli` line or the `ai:gemini` line.

## Root cause

The 2026-10-31 fix chose the `gemini-cli` formula to replace MacPaw's `cask:gemini`. Homebrew has since deprecated it in
favour of `antigravity-cli` (agy), which the manifests already install.

## Fix

1. Remove `gemini-cli` from `brew.hub.list` and `brew.worker.list`. Keep `cask:antigravity-cli`.
2. `bin/k3dm-machine-setup` keeps the `ai:agy` check as it is (a missing agy fails the check). `ai:gemini` is no longer a
   failure: report `ai:gemini ok` when present on the webhook PATH and `ai:gemini skipped (optional; deprecated)` when
   absent, through `report`, not `record_failure`.
3. Setup never uninstalls an existing `gemini-cli`. The webhook's `K3DM_AI_BIN_ORDER` default (`agy,gemini`) is not
   changed, so an installed gemini stays a fallback.
4. `docs/howto/m5-hub-migration.md`: agy is the required AI CLI; gemini is optional and no longer installed.

## Files

- `scripts/etc/machine/brew.hub.list`
- `scripts/etc/machine/brew.worker.list`
- `bin/k3dm-machine-setup`
- `scripts/tests/bin/machine_setup.bats`
- `scripts/tests/bin/machine_setup_acceptance.bats`
- `docs/howto/m5-hub-migration.md`
- `CHANGELOG.md`

## What NOT to do

- Do not change `scripts/lib/webhook/agent.py` or the AI CLI order.
- Do not run `brew uninstall` from setup.
- Do not install gemini by npm or any other route.

## Acceptance

```yaml
must:
  M1: no machine manifest lists gemini-cli or cask:gemini, and hub and worker still list cask:antigravity-cli
  M2: on hub and worker, a machine without gemini on the webhook PATH reports ai:gemini as skipped and that line does not make the run exit nonzero (paired with M3)
  M3: on hub and worker, a machine with gemini on the webhook PATH reports ai:gemini ok
must_not:
  N1: a machine missing agy on the webhook PATH never passes the check (ai:agy missing, exit nonzero), even when gemini is present
  N2: setup never runs brew uninstall, and never runs agy or gemini
evidence:
  E1:
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    intent: >-
      You will see machine_setup.bats and machine_setup_acceptance.bats assert the manifests, then run setup in a
      scratch HOME (the fixture first asserts HOME and stubs are under the test tmpdir) with the system PATH directories
      rewritten to scratch dirs, for: agy and gemini present (both ok, exit 0 on a complete machine); agy present and
      gemini absent (ai:gemini skipped, exit 0 on a complete machine); gemini present and agy absent (ai:agy missing,
      exit 1). A command log shows no uninstall and no agy or gemini run. N1 fails on a mutant that makes ai:agy optional.
    what: bats scripts/tests/bin/machine_setup.bats scripts/tests/bin/machine_setup_acceptance.bats
  E2:
    proves: [M2]
    kind: live
    intent: You will see make machine-check ROLE=hub on the M5 show ai:agy ok, with no brew:gemini-cli line.
    what: operator on the M5, Claude reads the report
interface:
  - bin/k3dm-machine-setup (role hub/worker; --check; scratch HOME; PATH)
  - scripts/etc/machine/brew.hub.list, brew.worker.list
```

## Resolution

- `955b979e` (Luna): `gemini-cli` removed from the hub and worker manifests; `ai:agy` stays a failure when missing;
  `ai:gemini` reports `skipped (optional; deprecated)` when absent, through `report`. The migration howto says agy
  is required and gemini optional.
- E1: `machine_setup.bats` + `machine_setup_acceptance.bats` 121/121 when run outside Codex's sandbox. Luna's
  sandbox could not run the terminal tests and reported one failure, which did not reproduce here.
  The 3 AI CLI tests all fail on the pre-fix script and manifests. A mutant that makes `ai:agy` optional fails both
  check tests (N1).
- Claude at land: dropped Luna's sandbox-limits issue note (covered by the run above); resolved a CHANGELOG conflict
  with the rotator entry.

## Live verification (E2), 2026-11-01

- M5 at `f2369dbb`, `bin/k3dm-machine-setup --role hub --check` (read-only, by Claude over SSH): `brew:antigravity-cli ok`,
  `ai:agy ok`, `ai:gemini ok` (the existing install is kept), and no `brew:gemini-cli` line.
- The run still exits 1 on `agent:bin/k3dm-heartbeat-setup missing`. That is unrelated: the heartbeat agent is only
  rendered as a review candidate (`scripts/etc/machine/not-installed.list`) until the operator loads it.
