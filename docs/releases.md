# Release History — lib-foundation

| Version | Date | Highlights |
|---|---|---|
| [v0.3.11](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.11) | 2026-03-25 | `_agent_audit` YAML hardcoded-IP check — staged `.yaml`/`.yml` files with IPv4 addresses fail pre-commit; 2 BATS |
| [v0.3.8](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.8) | 2026-03-24 | `_agent_audit` tab indentation enforcement — staged `.sh` files with tab/mixed indent fail pre-commit; 3 new BATS (15 total) |
| [v0.3.7](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.7) | 2026-03-24 | `system.sh` if-count cleanup — extract `_run_command_handle_failure` + `_node_install_via_redhat`; clears k3d-manager allowlist entries |
| [v0.3.6](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.6) | 2026-03-23 | `doc_hygiene.sh`: exclude fenced code blocks from Check 2 (`_dh_strip_fences`); add Check 4 — warn on hardcoded internal CoreDNS names in YAML (21 BATS) |
| [v0.3.4](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.4) | 2026-03-22 | Fix 12 Copilot PR #8 doc accuracy findings in `docs/api/functions.md` and `docs/plans/v0.3.3-api-reference.md` — correct descriptions for `_detect_platform`, `_safe_path`, `_curl`, `_cluster_provider`, `_agent_audit`, `_agent_lint`, `create_cluster`; remove nonexistent `_DETECTED_PLATFORM` global |
| [v0.3.3](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.3) | 2026-03-16 | API reference (`docs/api/functions.md`); README releases table split; `docs/releases.md` full history |
| [v0.3.2](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.2) | 2026-03-16 | Sync `deploy_cluster` helpers from k3d-manager (`_deploy_cluster_prompt_provider`, `_deploy_cluster_resolve_provider`, `CLUSTER_NAME` propagation, remove duplicate mac+k3s guard); TTY fix (`_DCRS_PROVIDER` global replaces command substitution); BATS expanded to 36 tests |
| [v0.3.1](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.1) | 2026-03-16 | Route bare `sudo` in all install helpers through `_run_command --interactive-sudo`; fix `_ensure_cargo` WSL redhat branch; AGENTS.md, GEMINI.md, CLAUDE.md overhaul; `.github/copilot-instructions.md` |
| [v0.3.0](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.0) | 2026-03-15 | `_run_command` if-count refactor, `_run_command_resolve_sudo` extracted, bash 3.2 compat (`_RCRS_RUNNER` global), BATS coverage |
| [v0.2.0](https://github.com/wilddog64/lib-foundation/releases/tag/v0.2.0) | 2026-03-08 | `agent_rigor.sh` — `_agent_checkpoint`, `_agent_audit`, `_agent_lint`, pre-commit hook, 13 BATS tests |
| [v0.1.2](https://github.com/wilddog64/lib-foundation/releases/tag/v0.1.2) | 2026-03-07 | Drop Colima support |
| [v0.1.1](https://github.com/wilddog64/lib-foundation/releases/tag/v0.1.1) | 2026-03-07 | `_resolve_script_dir` — portable symlink-aware script locator |
| [v0.1.0](https://github.com/wilddog64/lib-foundation/releases/tag/v0.1.0) | 2026-03-07 | Initial extraction from k3d-manager — `core.sh`, `system.sh`, CI, branch protection |
