# Progress — lib-foundation

## Overall Status

**v0.3.3 SHIPPED** — PR #8 squash-merged (b9f1fda), tagged, GitHub release created 2026-03-16.
**feat/v0.3.4 ACTIVE** — branch cut from main 2026-03-16.

---

## What Is Complete

- [x] GitHub repo + CI + branch protection (v0.1.0)
- [x] `core.sh` + `system.sh` extracted from k3d-manager (v0.1.0)
- [x] `_resolve_script_dir` — portable symlink-aware locator + BATS (v0.1.1)
- [x] Drop Colima support (v0.1.2)
- [x] `agent_rigor.sh` — `_agent_checkpoint`, `_agent_audit`, `_agent_lint`, pre-commit hook, 13 BATS (v0.2.0)
- [x] k3d-manager subtree wired at `scripts/lib/foundation/` (k3d-manager v0.7.0)
- [x] `_run_command` if-count refactor — `_run_command_resolve_sudo` extracted, both < 8 if-blocks (v0.3.0)
- [x] Bash 3.2 compat — `_RCRS_RUNNER` global temp (v0.3.0)
- [x] Route bare `sudo` in install helpers through `_run_command --interactive-sudo` (v0.3.1)
- [x] Fix `_ensure_cargo` WSL redhat branch (v0.3.1)
- [x] AGENTS.md, GEMINI.md, CLAUDE.md, copilot-instructions.md overhaul (v0.3.1)
- [x] Sync `deploy_cluster` helpers from k3d-manager; TTY fix (`_DCRS_PROVIDER` global); BATS 36 tests (v0.3.2)
- [x] Repo flipped **public** (v0.3.2)
- [x] API reference — `docs/api/functions.md` (v0.3.3)
- [x] README releases table split — top 3 + `docs/releases.md` full history (v0.3.3)

---

## What Is Pending

### v0.3.4 — active

- [ ] **Fix `docs/api/functions.md`** — 12 Copilot findings from PR #8 (merged); all doc accuracy issues requiring reading actual function bodies. Assigned to Codex.
  - Remove `_DETECTED_PLATFORM` global — does not exist; `_detect_platform` exits via `_err` on unsupported, no caching
  - `_detect_platform` returns `mac|wsl|debian|redhat|linux` only — no `unknown`
  - `_deploy_cluster_resolve_provider` — sets `_DCRS_PROVIDER` global, does not print/return
  - `_agent_lint` — AI-based (calls `AGENT_LINT_AI_FUNC`), not shellcheck; gated by `AGENT_LINT_GATE_VAR`
  - `_safe_path` — validates existing PATH for unsafe entries, does not construct a new PATH
  - `_curl` — ensures curl exists + adds `--max-time` default; does not enforce `_safe_path`
  - `_cluster_provider` — actual precedence: `K3D_MANAGER_PROVIDER` → `K3DMGR_PROVIDER` → `CLUSTER_PROVIDER`
  - `_agent_audit` — no path args; audits staged diffs for BATS removal, if-count, bare sudo; no kubectl credential check
  - Sourcing example paths — wrong; update to reflect actual `scripts/lib/` layout and subtree consumer path
  - `create_cluster` — missing `--dry-run/-n`, `--help`, positional ports `[http_port] [https_port]`
  - Same `_DETECTED_PLATFORM` / `unknown` errors in `docs/plans/v0.3.3-api-reference.md` — fix there too
- [ ] `rigor-cli` — separate repo (planned, no spec yet)
- [ ] Consumer integration: `shopping-carts`

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
