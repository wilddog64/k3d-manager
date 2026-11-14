# Bug: public plugin functions with a subshell body are unreachable through the dispatcher (`make dev-hub-sync`, `make snapshot`)

**Status:** LIVE-VERIFIED — live E4 2026-11-13 on deploy/hub 9a579a05 (dispatch mark live_verified); LANDED — d1c2c441 on k3d-manager-v1.44.0 2026-11-13 (Claude verified: pre-fix red, mutant red, Fable review no high/medium); originally captured 2026-11-13 from the independent Acceptance verification of dev-hub B (Opus verifier; Claude reproduced)
**Priority:** P1 (dev-hub E2 `make dev-hub-sync` cannot work; no workaround through the interface; blocks the v1.44.0 release PR)
**Introduced by:** `65e4799f` (v1.44.0 dev-hub B, `dev_hub_sync`); `6974f426` (v1.43.8, `hub_snapshot_capture`)
**Should have been caught by:** offline test (dev_hub.bats and hub_snapshot.bats source the plugin directly and never go through the dispatcher)
**Fix commit:** `d1c2c441`
**Prior art:** exact-slug glob: none. `make find-similar-docs` not run
**Approval:** operator, 2026-11-13: "go ahead for those three fix intents"
**Dispatch go:** operator, 2026-11-13: "go ahead for those three fix intents"
**Intent approved:** operator, 2026-11-13
**Intent approval words:** "go ahead for those three fix intents", in reply to Claude's three proposed intents

## Symptom

`scripts/k3d-manager dev_hub_sync feature-x` (and `make dev-hub-sync BRANCH=feature-x`) print `Error: Function 'dev_hub_sync' not found in plugins`. `make snapshot` (`./scripts/k3d-manager hub_snapshot_capture`) fails the same way.

## Root cause

- `scripts/plugins/dev_hub.sh:270` declares `function dev_hub_sync() (` and `scripts/plugins/hub_snapshot.sh:202` declares `function hub_snapshot_capture() (`, both with a subshell body.
- The lazy loader `_load_plugin_function` (`scripts/lib/foundation/scripts/lib/system.sh` ~1398) finds a plugin with `grep -Eq "^[[:space:]]*(function[[:space:]]+${func}[[:space:]]*\(\)|${func}[[:space:]]*\(\))[[:space:]]*\{"`, so only a `{` body matches.
- The weekly scheduled snapshot is unaffected: `hub_snapshot_scheduled` (hub_snapshot.sh:333) uses `function hub_snapshot_scheduled() { (`, which matches, and calls `hub_snapshot_capture` in-process.

## Fix

Change both declarations to the `{ ( … ) }` form already used by `hub_snapshot_scheduled` (keeping subshell semantics), or wrap them as `function name() { _name_impl "$@"; }`. Do not change the loader (lib-foundation subtree). Add a guard test that scans `scripts/plugins/*.sh` for public (no leading `_`) functions declared in a form the loader's pattern does not match.

## Acceptance

```yaml
must:
  M1: scripts/k3d-manager dev_hub_sync reaches the dev_hub_sync function through the dispatcher (refusing main with its own message, not "not found in plugins")
  M2: scripts/k3d-manager hub_snapshot_capture reaches the hub_snapshot_capture function through the dispatcher
  M3: a guard test fails when any public function in scripts/plugins/*.sh is declared in a form the loader's grep does not match
must_not:
  N1: dev_hub_sync and hub_snapshot_capture lose subshell isolation (a variable set or cd inside them must not leak to the caller)
  N2: the lib-foundation subtree (scripts/lib/foundation/) is modified
evidence:
  - {id: E1, proves: [M1, M2], kind: offline, intent: "You will see scripts/k3d-manager dev_hub_sync and make snapshot reach their functions through the dispatcher, with stubs for every external tool; on today's code both print 'not found in plugins'."}
  - {id: E2, proves: [M3], kind: offline, intent: "You will see a new test that fails if any public plugin function is declared in a form the loader can't find; on today's code it names dev_hub_sync and hub_snapshot_capture."}
  - {id: E3, proves: [N1, N2], kind: offline, intent: "You will see a test that a cd and a variable set inside each function do not reach the caller, and git diff showing nothing under scripts/lib/foundation/."}
  - {id: E4, proves: [M1], kind: live, intent: "The operator runs make dev-hub-sync BRANCH=<feature branch> on the M5 as part of dev-hub E2 and it reaches the sync."}
interface:
  - "scripts/k3d-manager dev_hub_sync [BRANCH]; make dev-hub-sync BRANCH=..."
  - "scripts/k3d-manager hub_snapshot_capture; make snapshot"
```

## Files

| File | Change |
|---|---|
| `scripts/plugins/dev_hub.sh` | `dev_hub_sync` declaration form |
| `scripts/plugins/hub_snapshot.sh` | `hub_snapshot_capture` declaration form |
| `scripts/tests/plugins/dev_hub.bats` | E1 dispatcher test, E3 isolation |
| `scripts/tests/plugins/hub_snapshot.bats` | E1 dispatcher test, E3 isolation |
| `scripts/tests/lib/plugin_function_declarations.bats` | new: E2 guard |

## Worker definition of done

- Change only the files above. Stub every external tool (kubectl, helm, vcluster, ssh, rsync, security, curl, launchctl) on PATH with a scratch HOME; no real cluster, hub or Keychain call. Show E1 and E2 red on today's code, then green. Run the touched suites plus `bats scripts/tests/lib/plugin_function_declarations.bats` and paste command, rc and proving lines. Leave changes uncommitted.

## Residual lows (P3 batch candidates)

- Low (Fable): the guard's regex is a hand copy of the loader's (`plugin_function_declarations.bats:6`); a loader change after a subtree pull would not be noticed.
- Fixed before landing (Fable low): the guard originally selected only `name()` lines, so `function name {` / `function name (` escaped it; Claude widened the selector and proved all three unreachable forms fail the guard, with a passing positive control.

## Live verification 2026-11-13

E4 PASS after the operator promoted 9a579a05 (appsets-check + platform-ops): make dev-hub-sync on m5-air reached dev_hub_sync and stopped at the child apply (no dev-hub kubeconfig: dev-hub-up not run first), not "Function not found". Recorded with `bin/k3dm-codex-dispatch mark --state live_verified --sha 9a579a05...`.

**Live evidence:** 2026-11-13 · run operator-m5-dev-hub-sync · env hub · scenario dev-hub-sync-reaches-function · commit 9a579a05 · proves E4
