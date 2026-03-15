# Active Context — lib-foundation

## Current State: `feat/run-command-refactor-v0.3.0` (as of 2026-03-15)

**v0.2.0 SHIPPED** — `agent_rigor.sh` merged, tag `v0.2.0`. Synced into k3d-manager.
**v0.3.0 active** — branch `feat/run-command-refactor-v0.3.0` cut from main 2026-03-15.

---

## Purpose

Shared Bash foundation library. Contains:
- `scripts/lib/core.sh` — cluster lifecycle, provider abstraction, `_resolve_script_dir`
- `scripts/lib/system.sh` — `_run_command`, `_detect_platform`, package helpers, BATS install

Consumed by downstream repos via git subtree pull.

---

## Version Roadmap

| Version | Status | Notes |
|---|---|---|
| v0.1.0 | released | `core.sh` + `system.sh` extraction, CI, branch protection |
| v0.1.1 | released | `_resolve_script_dir` — portable symlink-aware script locator |
| v0.1.2 | released | Drop colima support (PR #3) |
| v0.2.0 | **active** | `agent_rigor.sh` — `_agent_checkpoint`, `_agent_audit`, `_agent_lint` |

---

## v0.2.0 — Completion Report (Codex)

Files created: `scripts/lib/agent_rigor.sh`; `scripts/hooks/pre-commit`; `scripts/etc/agent/lint-rules.md`; `scripts/tests/lib/agent_rigor.bats`
Shellcheck: PASS
BATS: 12/12 passing
`_agent_checkpoint`: DONE — repo_root via `git rev-parse --show-toplevel` (line 10)
`_agent_audit`: DONE — kubectl exec credential check removed; retains BATS/if-count/bare-sudo scans (lines 40–118)
`_agent_lint`: DONE — gated via `AGENT_LINT_GATE_VAR` + `AGENT_LINT_AI_FUNC` indirection (lines 121–158)
pre-commit template: DONE — sources `system.sh` + `agent_rigor.sh`, runs `_agent_audit` + optional `_agent_lint`
lint-rules.md: DONE — 5 rules ported from k3d-manager
BATS coverage: 10 targeted tests — `_agent_checkpoint` 3, `_agent_audit` 7 (12 total including existing `_resolve_script_dir` cases)
Unexpected findings: NONE

**Bug fix (staged diff):** `_agent_audit` git diff calls corrected to `--cached` (lines 48, 65, 105); 6 BATS tests updated to `git add` before audit call.

## v0.2.0 Copilot Fix — Completion Report (Codex)

Fix 1 (staged blob): DONE — `scripts/lib/agent_rigor.sh` lines 72–85 now read staged content via `git show :"$file"`
Fix 2 (comment filter): DONE — bare-sudo grep split into comment + `_run_command` filters (line 106)
New BATS test: DONE — `_agent_audit flags sudo with inline comment`
Shellcheck: PASS (`shellcheck scripts/lib/agent_rigor.sh`)
BATS: 13/13 passing (`env -i HOME="$HOME" PATH="$PATH" bats scripts/tests/lib/`)
Status: COMPLETE

---

## Key Contracts

These function signatures must not change without coordinating across all consumers:

- `_run_command [--prefer-sudo|--require-sudo|--probe '<subcmd>'|--quiet] -- <cmd>`
- `_detect_platform` → `mac | wsl | debian | redhat | linux`
- `_cluster_provider` → `k3d | k3s | orbstack`
- `_resolve_script_dir` → absolute canonical path of calling script's real directory (follows file symlinks)

---

## Consumers (planned)

| Repo | Integration | Status |
|---|---|---|
| `k3d-manager` | git subtree at `scripts/lib/foundation/` | **ACTIVE** — subtree pulled in v0.7.0 |
| `rigor-cli` | git subtree (planned) | future |
| `shopping-carts` | git subtree (planned) | future |

---

## Open Items

- [ ] **Add `.github/copilot-instructions.md`** — first commit on next branch (v0.2.1 or v0.3.0); encode bash 3.2+ compat, `_run_command --prefer-sudo`, `env -i` BATS invocation, key contracts
- [x] **`_run_command` if-count refactor** — PR #5 (`feat/run-command-refactor-v0.3.0`). Commits `b7b5411` + `c50e294` add `_run_command_resolve_sudo`, drop if-count <8, add BATS, and replace `local -n` with `_RCRS_RUNNER` for bash 3.2 compatibility per `docs/plans/v0.3.0-run-command-if-count-refactor.md` + `...-bash-compat-fix.md`.
- [ ] BATS test suite for lib functions (broader — future)
- [ ] Add `rigor-cli` as consumer
- [ ] Add `shopping-carts` as consumer
- [ ] **Sync deploy_cluster fixes from k3d-manager back into lib-foundation** — CLUSTER_NAME propagation + provider helper extraction (done in k3d-manager v0.7.0 local core.sh; not yet in lib-foundation core.sh).
- [ ] **Remove duplicate mac+k3s guard in `deploy_cluster`** — dead code, already removed from subtree copy in k3d-manager v0.7.0 PR; apply same removal upstream here.
- [ ] **Route bare `sudo` in `_install_debian_helm` and `_install_debian_docker` through `_run_command`** — flagged by Copilot in k3d-manager PR #24.
- [ ] **Remote installer script integrity** — `_install_k3s`, `_install_istioctl`, `_install_bats_from_source`, `_install_copilot_from_release` download and execute without checksum verification. Low priority for dev-only tooling.

---

## Core Library Change Rule

**All changes to core library code — new functions, refactors, and bug fixes — must originate
in lib-foundation, not in a consumer's subtree copy.**

| Change type | Wrong | Right |
|-------------|-------|-------|
| Bug fix in `_run_command` | Edit `scripts/lib/foundation/scripts/lib/system.sh` in k3d-manager | Fix in lib-foundation → PR → tag → subtree pull |
| New helper function | Add to k3d-manager subtree copy | Add to lib-foundation → PR → tag → subtree pull |
| Refactor | Edit subtree copy directly | Refactor in lib-foundation → PR → tag → subtree pull |

**Why:** Editing the subtree copy directly creates drift — the fix lives only in the
consumer and is lost or overwritten on the next subtree pull. lib-foundation is the
source of truth.

**Exception:** Emergency hotfix directly in the subtree copy is acceptable if a blocking
bug needs an immediate workaround. In that case, a corresponding issue must be filed in
lib-foundation immediately and the fix ported upstream before the next release.

---

## Release Protocol (Option A — Independent Versioning)

lib-foundation uses independent semver (`v0.1.x`) separate from k3d-manager.

**Normal release flow (changes originate in k3d-manager):**

1. Codex edits both local k3d-manager copies and `scripts/lib/foundation/` subtree copies.
2. k3d-manager PR merges.
3. Claude applies the same changes directly to the lib-foundation local clone, opens a PR here, and merges.
   - `git subtree push` does NOT work — branch protection requires PRs; direct push is rejected.
4. Claude updates `CHANGE.md` here and cuts a new version tag (e.g. `v0.1.2`).
5. Claude runs `git subtree pull` in k3d-manager to sync the merged changes back into the subtree copy.
6. k3d-manager `CHANGE.md` records `lib-foundation @ v0.1.2`.

**Independent release flow (changes originate here):**

1. Changes made directly in lib-foundation, PR merged, tag cut.
2. Each consumer runs `git subtree pull --prefix=<path> lib-foundation <tag> --squash` to upgrade.

**Version tag convention:** `vMAJOR.MINOR.PATCH` — bump PATCH for fixes, MINOR for new functions, MAJOR for breaking contract changes.

**Breaking changes** require coordinating all consumers before merging to `main`.

---

## Engineering Protocol

- **Breaking changes**: coordinate across all consumers before merging to `main`
- **Tests**: always run with `env -i HOME="$HOME" PATH="$PATH" bats scripts/tests/lib/`
- **shellcheck**: run on every touched `.sh` file before commit
- **No bare sudo**: always `_run_command --prefer-sudo`
- **Branch protection**: 1 required review, dismiss stale, enforce_admins=false (owner can self-merge)
