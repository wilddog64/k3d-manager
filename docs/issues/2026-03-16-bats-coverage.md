# Issue: Core/System BATS Coverage Gaps

**Date identified:** 2026-03-16  
**Functions:** `_detect_platform`, `_cluster_provider`, `_deploy_cluster_resolve_provider`, `_run_command`

---

## Problem

lib-foundation's BATS suites only covered `_resolve_script_dir`, `_run_command`, and the
agent rigor helpers (total 21 tests). Critical functions in `core.sh` and `system.sh`
were untested:
- `_detect_platform` branches had no verification
- `_cluster_provider` env precedence lacked tests
- Newly added `_deploy_cluster_resolve_provider` helper was untested
- `_run_command` flag parsing for `--interactive-sudo` / `--prefer-sudo` had no checks

## Fix

Added 15 new BATS cases:
- 5 `_detect_platform` tests (mac, wsl, debian, redhat, linux) using stubbed probes
- 3 `_cluster_provider` env precedence tests (CLUSTER_PROVIDER, K3D_MANAGER_PROVIDER,
  K3DMGR_PROVIDER)
- 5 `_deploy_cluster_resolve_provider` tests (CLI flag, force flag, three env overrides,
  mac default, non-interactive default)
- 2 `_run_command` flag-acceptance tests ensuring `--interactive-sudo` and
  `--prefer-sudo` parse without hanging (sudo stubbed)

Total suite count is now 36 (system 8 + core 17 + agent_rigor 11).

## Verification

- `shellcheck scripts/tests/lib/core.bats scripts/tests/lib/system.bats`
- `env -i PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" HOME="$HOME" TMPDIR="$TMPDIR" \
  bash --norc --noprofile -c 'bats scripts/tests/lib/system.bats scripts/tests/lib/core.bats scripts/tests/lib/agent_rigor.bats'`

## Status

Fixed on `feat/v0.3.2` (commit `5cb8a5a`).
