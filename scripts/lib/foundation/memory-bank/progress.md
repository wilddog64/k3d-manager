# Progress — lib-foundation

## Overall Status

**v0.3.1 SHIPPED** — PR #6 merged (38a91a8), tagged, GitHub release created.
**feat/v0.3.2 ACTIVE** — branch cut from main 2026-03-16.

---

## What Is Complete

- [x] GitHub repo + CI + branch protection (v0.1.0)
- [x] `core.sh` + `system.sh` extracted from k3d-manager (v0.1.0)
- [x] `_resolve_script_dir` — portable symlink-aware locator + BATS (v0.1.1)
- [x] Drop Colima support (v0.1.2)
- [x] `agent_rigor.sh` — `_agent_checkpoint`, `_agent_audit`, `_agent_lint`, pre-commit hook, 13 BATS (v0.2.0)
- [x] k3d-manager subtree wired at `scripts/lib/foundation/` (k3d-manager v0.7.0)
- [x] `_run_command` if-count refactor — `_run_command_resolve_sudo` extracted, both functions < 8 if-blocks (v0.3.0)
- [x] Bash 3.2 compat — replaced `local -n` nameref with `_RCRS_RUNNER` global temp (v0.3.0)
- [x] `scripts/tests/lib/system.bats` — 6 tests (v0.3.0)
- [x] Route bare `sudo` in all install helpers through `_run_command --interactive-sudo` (v0.3.1)
- [x] Fix `_ensure_cargo` WSL redhat branch — was using `apt-get`, now uses `dnf` (v0.3.1)
- [x] `AGENTS.md`, `GEMINI.md`, `CLAUDE.md` overhaul — agent session rules, bash 3.2 compat, privilege model (v0.3.1)
- [x] `.github/copilot-instructions.md` — bash 3.2 P1 rules, `--interactive-sudo` pattern, if-count threshold (v0.3.1)
- [x] README releases table + Contents table (agent_rigor.sh added) (v0.3.1)

---

## What Is Pending

- [x] Tag v0.3.1 + GitHub release created — https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.1
- [x] Add v0.3.1 entry to README releases table — commit `2294bf7` on feat/v0.3.2
- [x] Sync `deploy_cluster` fixes from k3d-manager — commit `0501c7a` adds prompt/resolution helpers, CLUSTER_NAME propagation, and removes duplicate mac+k3s guard per `docs/plans/v0.3.2-sync-deploy-cluster.md`.
- [x] Expand BATS coverage — commit `5cb8a5a` adds 5 `_detect_platform`, 5 `_deploy_cluster_resolve_provider`, 3 `_cluster_provider`, and 2 `_run_command` flag tests (total now 36) per `docs/plans/v0.3.2-bats-coverage.md`.
- [ ] Consumer integration: `rigor-cli`, `shopping-carts`
- [ ] **k3d-manager subtree pull** — pull v0.3.2 into k3d-manager-v0.9.3 after v0.3.2 ships

---

## Known Constraints

| Item | Notes |
|---|---|
| `SCRIPT_DIR` dependency | `system.sh` sources `agent_rigor.sh` via `$SCRIPT_DIR` at load time |
| Contract stability | `_run_command`, `_detect_platform`, `_cluster_provider` — signature changes require all-consumer coordination |
| Clean env testing | BATS must run with `env -i` — ambient `SCRIPT_DIR` causes false passes |
| bash 3.2 compat | No `local -n`, no `declare -A`, no `mapfile` in lib code |
| `--interactive-sudo` for installs | Install helpers use `--interactive-sudo`; `--prefer-sudo` is for non-interactive contexts only |
