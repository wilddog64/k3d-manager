# Progress — lib-foundation

## Overall Status

**v0.3.2 SHIPPED** — PR #7 merged (98f6ee0), tagged, GitHub release created. Repo **public**.
**feat/v0.3.3 ACTIVE** — branch cut from main 2026-03-16.

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
- [x] Tag v0.3.1 + GitHub release created — https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.1
- [x] Sync `deploy_cluster` helpers from k3d-manager — `_deploy_cluster_prompt_provider`, `_deploy_cluster_resolve_provider`, CLUSTER_NAME propagation, duplicate mac+k3s guard removed (v0.3.2)
- [x] Fix TTY detection — `_DCRS_PROVIDER` global replaces command substitution (v0.3.2)
- [x] Expand BATS to 36 tests — `_detect_platform`, `_cluster_provider`, `_deploy_cluster_resolve_provider`, `_run_command` flags (v0.3.2)
- [x] Tag v0.3.2 + GitHub release created — https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.2
- [x] Repo flipped to **public**

---

## What Is Pending

- [x] **k3d-manager subtree pull** — v0.3.2 pulled into k3d-manager-v0.9.3 (commit `e4d2eed`)
- [ ] Consumer integration: `rigor-cli`, `shopping-carts`
  - `rigor-cli` — **separate repo**, lib-foundation as git subtree (same pattern as k3d-manager)
    - CLI dispatcher: `rigor-cli checkpoint|audit|lint`
    - Wraps `_agent_checkpoint`, `_agent_audit`, `_agent_lint` as callable commands
    - Any repo can adopt without sourcing lib-foundation directly
    - Planned milestone after v0.3.3 ships
- [ ] **README releases table fix** — split into: first 3 releases in main table, rest in a separate table below (same convention as k3d-manager). Do as first commit on feat/v0.3.3.
- [x] **API reference** — commit `9b224bb` adds `docs/api/functions.md` documenting system/core/agent_rigor helpers and globals per `docs/plans/v0.3.3-api-reference.md`.

---

## Known Constraints

| Item | Notes |
|---|---|
| `SCRIPT_DIR` dependency | `system.sh` sources `agent_rigor.sh` via `$SCRIPT_DIR` at load time |
| Contract stability | `_run_command`, `_detect_platform`, `_cluster_provider` — signature changes require all-consumer coordination |
| Clean env testing | BATS must run with `env -i` — ambient `SCRIPT_DIR` causes false passes |
| bash 3.2 compat | No `local -n`, no `declare -A`, no `mapfile` in lib code |
| `--interactive-sudo` for installs | Install helpers use `--interactive-sudo`; `--prefer-sudo` is for non-interactive contexts only |
| Global temp vars | `_RCRS_RUNNER` (sudo runner), `_DCRS_PROVIDER` (deploy provider) — never use `$()` for functions that check TTY |
