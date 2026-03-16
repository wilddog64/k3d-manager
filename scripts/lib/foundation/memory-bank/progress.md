# Progress — lib-foundation

## Overall Status

**v0.3.0 SHIPPED** — PR #5 merged (2104d76), tagged v0.3.0, GitHub release created 2026-03-15.
**feat/v0.3.1 ACTIVE** — branch cut from main 2026-03-15.

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
- [x] README releases table added (feat/v0.3.1)

---

## What Is Pending

- [x] `.github/copilot-instructions.md` — commit `95d3074` (feat/v0.3.1); bash 3.2 P1 rules, `_run_command --prefer-sudo` pattern, if-count threshold, OWASP checks, skip list
- [x] Route bare `sudo` in install helpers — commit `0d3d6f1` (feat/v0.3.1) updates Kubernetes, Helm, Docker installers (Debian + RedHat) and `_ensure_cargo` to call `_run_command --prefer-sudo --`. Doc: `docs/issues/2026-03-15-route-bare-sudo.md`.
- [ ] Sync `deploy_cluster` fixes from k3d-manager (CLUSTER_NAME, provider helpers, duplicate guard)
- [ ] Broader BATS coverage for remaining lib functions
- [ ] Consumer integration: `rigor-cli`, `shopping-carts`
- [ ] **k3d-manager subtree pull** — pull v0.3.0 into k3d-manager-v0.9.3

---

## Known Constraints

| Item | Notes |
|---|---|
| `SCRIPT_DIR` dependency | `system.sh` sources `agent_rigor.sh` via `$SCRIPT_DIR` at load time |
| Contract stability | `_run_command`, `_detect_platform`, `_cluster_provider` — signature changes require all-consumer coordination |
| Clean env testing | BATS must run with `env -i` — ambient `SCRIPT_DIR` causes false passes |
| bash 3.2 compat | No `local -n`, no `declare -A`, no `mapfile` in lib code |
