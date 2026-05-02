# Changes - lib-foundation

## [Unreleased]

### Fixed
- `scripts/lib/system.sh`: `_copilot_auth_check` — remove `K3DM_ENABLE_AI` gate; check env tokens (`COPILOT_GITHUB_TOKEN`/`GH_TOKEN`/`GITHUB_TOKEN`), then `~/.config/github-copilot/apps.json`, then `gh auth status`; `_err` on failure with clear message — Copilot v1.0.40 has no `auth status` subcommand (`f0e29d9`, `eede5c3`)

### Added
- `scripts/tests/lib/copilot_auth.bats`: 5-test BATS suite covering all auth paths — env token (3 variants), `apps.json`, and failure with clear error message (`f0e29d9`)

## [v0.3.17] — 2026-05-01

### Added
- `scripts/lib/system.sh`: `_ai_agent_review` — generic AI dispatch wrapper; routes to backend selected by `AI_REVIEW_FUNC` (default: `copilot`) with model from `AI_REVIEW_MODEL` (default: `gpt-5.4-mini`); passes all args through to the selected backend (`448560a`)
- `scripts/tests/lib/ai_agent_review.bats`: 3-test BATS suite — default dispatch to `_copilot_review`, `AI_REVIEW_MODEL` override, unknown `AI_REVIEW_FUNC` error path (`448560a`)
- `docs/api/functions.md`: `_ai_agent_review` function entry + `AI_REVIEW_FUNC` / `AI_REVIEW_MODEL` env var table in Copilot CLI Integration section (`448560a`)

### Changed
- `scripts/lib/system.sh`: `_k3d_manager_copilot` renamed to `_copilot_review` — aligns with the `_copilot_*` helper family; no behavior change (`d24b457`)
- `docs/api/functions.md`: Copilot CLI Integration section — full documentation of `_copilot_auth_check`, `_copilot_scope_prompt`, `_copilot_prompt_guard`, `_copilot_review` with usage examples and adoption pattern (`98a58e0`)

### Fixed
- `scripts/lib/system.sh`: removed `K3DM_ENABLE_AI` gate from `_copilot_review` — a lib-foundation backend must not check a consumer-specific env var; gate belongs in callers (`657fd91`)
- `scripts/lib/agent_rigor.sh`: `_agent_lint` staged-files glob expanded to `.sh`, `.js`, `.md` — previously only matched `.sh` (`af1356a`)

## [v0.3.16] — 2026-04-05

### Fixed
- `_agent_audit` IP allowlist: use `grep -Fqx -- "$file"` to prevent repo-relative paths beginning with `-` from being parsed as grep flags.

## [v0.3.15] — 2026-03-31

### Fixed
- `_agent_audit` IP audit loop — supports `AGENT_IP_ALLOWLIST` env var; when set to a readable regular file, skips IP literal check for paths listed in it (one repo-relative path per line; lines beginning with `#` are ignored). Consumers set this env var before running `_agent_audit` (for example, in the pre-commit hook environment).

## [v0.3.14] — 2026-03-27

### Fixed
- `_ensure_antigravity_ide()` — detect `agy` (Homebrew macOS binary) alongside `antigravity` at all 4 detection points
- `_antigravity_browser_ready()` — fail fast with clear error when `curl` missing, instead of silently looping to timeout
- `_agent_audit` tab-indentation scan — replace word-splitting `for file in $changed_sh` with NUL-delimited `while IFS= read -r -d ''` loop; safe for filenames with spaces
- `docs/api/functions.md` — document `PLAYWRIGHT_MCP_VERSION` pinned default; remove `@latest` inaccuracy
- `CHANGE.md` — version shipped v0.3.12 and v0.3.13 entries (were `[Unreleased]`)

## [v0.3.13] — 2026-03-25

### Fixed
- `_antigravity_browser_ready()` — replace `_curl` boolean probe with `_run_command --soft -- curl` so the poll loop retries instead of calling `exit 1` on the first failed attempt

## [v0.3.12] — 2026-03-25

### Added
- `_ensure_antigravity_ide()` — install Antigravity IDE via brew (macOS), apt-get (Debian), or dnf (RedHat)
- `_ensure_antigravity_mcp_playwright()` — inject Playwright MCP entry into Antigravity `mcp_config.json` (requires `jq`; idempotent)
- `_antigravity_browser_ready()` — verify Antigravity remote debugging port 9222 is listening; configurable timeout
- `_antigravity_mcp_config_path()` — resolve Antigravity `mcp_config.json` path for macOS/Linux

## [v0.3.11] — 2026-03-25

### Added
- `scripts/lib/agent_rigor.sh`: YAML hardcoded-IP check in `_agent_audit` — staged `.yaml`/`.yml` files containing IPv4 addresses now fail the pre-commit hook; warns to use CoreDNS hostname instead.
- `scripts/tests/lib/agent_rigor.bats`: two new tests covering clean YAML (pass) and hardcoded-IP YAML (fail) scenarios.

---

## [v0.3.10]

### Fixed
- `.clinerules`: correct `_detect_platform` return values — `mac | wsl | debian | redhat | linux` (was `debian | rhel | arch | darwin | unknown`)

---

## [v0.3.8] — _agent_audit tab indentation enforcement

### Added
- `scripts/lib/agent_rigor.sh`: tab indentation check in `_agent_audit` — staged `.sh` files containing tab-indented lines now fail the pre-commit hook; enforces 2-space style across all shell scripts.
- `scripts/tests/lib/agent_rigor.bats`: two new tests covering tab-indented (fail) and 2-space-indented (pass) scenarios.

### Fixed
- `scripts/tests/lib/system.bats`: assert exit status in quiet-mode `_run_command_handle_failure` test.

---

## [v0.3.7] — system.sh if-count cleanup

### Changed
- `scripts/lib/system.sh`: extracted `_run_command_handle_failure` and `_node_install_via_redhat` helpers so `_run_command`/`_ensure_node` drop to ≤8 ifs; clears remaining allowlist entries.
- `scripts/tests/lib/system.bats`: added coverage for `_run_command_handle_failure` soft/quiet modes and `_node_install_via_redhat` fallback behavior.
