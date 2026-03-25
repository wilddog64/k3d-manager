# Changes - lib-foundation

## [Unreleased] — v0.3.12

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

## [Unreleased] — v0.3.10

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
