# Active Context — lib-foundation

## Current State: `feat/v0.3.2` (as of 2026-03-16)

**v0.3.1 SHIPPED** — PR #6 merged (38a91a8), tagged, GitHub release created.
**feat/v0.3.2 ACTIVE** — branch cut from main 2026-03-16.

---

## Purpose

Shared Bash foundation library. Contains:
- `scripts/lib/core.sh` — cluster lifecycle, provider abstraction, `_resolve_script_dir`
- `scripts/lib/system.sh` — `_run_command`, `_run_command_resolve_sudo`, `_detect_platform`, package helpers, BATS install
- `scripts/lib/agent_rigor.sh` — `_agent_checkpoint`, `_agent_audit`, `_agent_lint`

Consumed by downstream repos via git subtree pull.

---

## Version Roadmap

| Version | Status | Notes |
|---|---|---|
| v0.1.0–v0.3.1 | released | See README Releases table |
| v0.3.2 | **active** | cut 2026-03-16 |

---

## Open Items

- [x] **Tag v0.3.1 + GitHub release** — https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.1
- [x] **Add v0.3.1 entry to README releases table** — commit `2294bf7` on feat/v0.3.2
- [x] **Sync deploy_cluster fixes from k3d-manager** — commit `0501c7a` adds `_deploy_cluster_prompt_provider`, `_deploy_cluster_resolve_provider`, CLUSTER_NAME propagation, and removes the duplicate mac+k3s guard per `docs/plans/v0.3.2-sync-deploy-cluster.md`.
- [x] **Expand BATS coverage** — commit `5cb8a5a` adds 15 tests (platform detection, provider overrides, `_deploy_cluster_resolve_provider`, `_run_command` flags). Total BATS count now 36 per `docs/plans/v0.3.2-bats-coverage.md`.
- [ ] **k3d-manager subtree pull** — pull v0.3.2 into k3d-manager-v0.9.3 after v0.3.2 ships
- [ ] Add `rigor-cli` as consumer
- [ ] Add `shopping-carts` as consumer

---

## Key Contracts (must not change without coordinating all consumers)

- `_run_command [--prefer-sudo|--require-sudo|--interactive-sudo|--probe '<subcmd>'|--quiet|--soft] -- <cmd>`
- `_detect_platform` → `mac | wsl | debian | redhat | linux`
- `_cluster_provider` → `k3d | k3s | orbstack`
- `_resolve_script_dir` → absolute canonical path of calling script's real directory

---

## Consumers

| Repo | Integration | Status |
|---|---|---|
| `k3d-manager` | git subtree at `scripts/lib/foundation/` | subtree pull to v0.3.1 pending |
| `rigor-cli` | git subtree (planned) | future |
| `shopping-carts` | git subtree (planned) | future |

---

## Engineering Protocol

- **Tests**: always run with `env -i PATH="..." HOME="$HOME" TMPDIR="$TMPDIR" bash --norc --noprofile -c 'bats scripts/tests/lib/'`
- **shellcheck**: run on every touched `.sh` file before commit
- **No bare sudo**: always `_run_command --interactive-sudo` for install helpers, `--prefer-sudo` for non-interactive
- **All changes originate here** — never edit consumer subtree copies directly
- **Release flow**: PR → merge → tag → GitHub release → consumers run `git subtree pull`

## Lessons Learned

- `local -n` nameref requires bash 4.3+ — use global temp vars (`_RCRS_RUNNER`) for array output from helpers
- `--prefer-sudo` silently drops to non-root when password sudo required — use `--interactive-sudo` for install helpers
- `git subtree add --squash` creates a merge commit that blocks GitHub rebase-merge — use squash-merge with admin override in consumers
- BATS must run with `env -i` — ambient `SCRIPT_DIR` causes false passes
