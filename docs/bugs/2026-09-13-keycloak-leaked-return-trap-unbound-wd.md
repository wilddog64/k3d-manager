# Bug: `keycloak.sh` RETURN traps leak and kill the caller with `wd: unbound variable`

**Filed:** 2026-09-13
**Branch:** `k3d-manager-v1.33.0`
**Status:** READY FOR CODEX

---

## Problem

The first live `hub_recovery_reconcile --confirm` on the hub (2026-09-13) ran all 8 steps successfully but exited `rc=1` with:

```
scripts/plugins/hub_recovery.sh: line 135: wd: unbound variable
```

Cause: `keycloak_seed_smoke_user` (`scripts/plugins/keycloak.sh:508`) and `keycloak_provision_shopping_cart_realm` (`:687`) both install

```bash
   trap 'rm -rf "$wd"' RETURN
```

and never clear it. A RETURN trap set inside a function stays installed after that function returns. The next function return in the caller runs `rm -rf "$wd"` after the `local wd` has gone out of scope, and under `set -u` that aborts the caller. `hub_recovery_reconcile` is the first caller that runs more functions after `keycloak_seed_smoke_user`, so it is the first to hit this.

`scripts/plugins/hub_recovery.sh:120` uses the same non-self-clearing form (`trap 'rm -f "$rendered"' RETURN`). A manual `trap - RETURN` at `:130` hides it today, but any early return between those lines would leak the trap.

The repo already has the correct idiom at `scripts/plugins/argocd.sh:738`: the trap clears itself, and the path is expanded when the trap is set.

## Fix

### Before You Start

- `git pull origin k3d-manager-v1.33.0`; read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
- Read `scripts/plugins/keycloak.sh` lines 486-520 and 643-700, `scripts/plugins/hub_recovery.sh` lines 115-133, and `scripts/plugins/argocd.sh` line 738.

### K1 — `scripts/plugins/keycloak.sh` (two sites: lines 508 and 687)

Old (both sites):

```bash
   trap 'rm -rf "$wd"' RETURN
```

New (both sites):

```bash
   trap 'trap - RETURN; rm -rf "'"${wd}"'" 2>/dev/null || true' RETURN
```

### K2 — `scripts/plugins/hub_recovery.sh`

Old (line 120):

```bash
  trap 'rm -f "$rendered"' RETURN
```

New:

```bash
  trap 'trap - RETURN; rm -f "'"${rendered}"'" 2>/dev/null || true' RETURN
```

Leave lines 130-131 (`trap - RETURN` / `rm -f "$rendered"`) as they are.

### Tests

New `scripts/tests/plugins/keycloak_return_trap.bats` (pure logic, no cluster):

- **Disappearance gate:** `grep -c "rm -rf \"\$wd\"' RETURN" scripts/plugins/keycloak.sh` outputs `0`, and `grep -c "trap - RETURN; rm -rf" scripts/plugins/keycloak.sh` outputs `2`.
- **Behaviour:** in `bash -c 'set -euo pipefail; ...'`, define `inner() { local wd; wd=$(mktemp -d); trap '<new idiom>' RETURN; }` and `outer() { inner; helper; }` with `helper() { :; }`. Run `outer` and assert exit 0, then assert `trap -p RETURN` prints nothing afterwards. Do not `grep -F` whole source lines.

## Definition of Done

- [ ] K1 and K2 implemented exactly; only `scripts/plugins/keycloak.sh`, `scripts/plugins/hub_recovery.sh`, the new BATS file and `CHANGELOG.md` changed
- [ ] `shellcheck -x scripts/plugins/keycloak.sh scripts/plugins/hub_recovery.sh` — no new warnings
- [ ] `bats scripts/tests/plugins/keycloak_return_trap.bats scripts/tests/plugins/hub_recovery.bats` green — paste the summary
- [ ] CHANGELOG `## [Unreleased]` → `### Fixed`: "Keycloak smoke-user/realm-provision RETURN traps no longer leak into callers (`hub_recovery_reconcile --confirm` exited 1 with `wd: unbound variable`)"
- [ ] Commit message verbatim: `fix(keycloak): self-clearing RETURN traps so callers do not die on unbound wd`
- [ ] Pushed to `origin/k3d-manager-v1.33.0`; report the SHA

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`
- Do NOT modify `scripts/lib/foundation/`, `scripts/lib/acg/`, `scripts/lib/system.sh`, or any file outside the targets
- Do NOT run anything against a live cluster
