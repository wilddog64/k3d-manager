# Changes - lib-foundation

## [Unreleased] v0.3.8 — _agent_audit tab indentation enforcement

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
