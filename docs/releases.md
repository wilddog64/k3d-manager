# Release History — lib-foundation

| Version | Date | Highlights |
|---|---|---|
| [v0.3.2](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.2) | 2026-03-16 | Sync `deploy_cluster` helpers from k3d-manager (`_deploy_cluster_prompt_provider`, `_deploy_cluster_resolve_provider`, `CLUSTER_NAME` propagation, remove duplicate mac+k3s guard); TTY fix (`_DCRS_PROVIDER` global replaces command substitution); BATS expanded to 36 tests |
| [v0.3.1](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.1) | 2026-03-16 | Route bare `sudo` in all install helpers through `_run_command --interactive-sudo`; fix `_ensure_cargo` WSL redhat branch; AGENTS.md, GEMINI.md, CLAUDE.md overhaul; `.github/copilot-instructions.md` |
| [v0.3.0](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.0) | 2026-03-15 | `_run_command` if-count refactor, `_run_command_resolve_sudo` extracted, bash 3.2 compat (`_RCRS_RUNNER` global), BATS coverage |
| [v0.2.0](https://github.com/wilddog64/lib-foundation/releases/tag/v0.2.0) | 2026-03-08 | `agent_rigor.sh` — `_agent_checkpoint`, `_agent_audit`, `_agent_lint`, pre-commit hook, 13 BATS tests |
| [v0.1.2](https://github.com/wilddog64/lib-foundation/releases/tag/v0.1.2) | 2026-03-07 | Drop Colima support |
| [v0.1.1](https://github.com/wilddog64/lib-foundation/releases/tag/v0.1.1) | 2026-03-07 | `_resolve_script_dir` — portable symlink-aware script locator |
| [v0.1.0](https://github.com/wilddog64/lib-foundation/releases/tag/v0.1.0) | 2026-03-07 | Initial extraction from k3d-manager — `core.sh`, `system.sh`, CI, branch protection |
