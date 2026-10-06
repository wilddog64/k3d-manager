# Release History — lib-foundation

| Version | Date | Highlights |
|---|---|---|
| [v0.5.1](https://github.com/wilddog64/lib-foundation/releases/tag/v0.5.1) | 2026-10-06 | ACG watcher checks every 30 min (was 3.5 h, which missed the 65 min extend window); yesterday's shutdown time read as expired, not ~22 h left; extend waits for the button and the launchd wrapper runs Node by absolute path; sudo runs bare names from system dirs, not the user's PATH; self-contained CDP readiness wait; `_agent_audit` no longer flags `_run_command`'s `*-sudo` flags |
| [v0.5.0](https://github.com/wilddog64/lib-foundation/releases/tag/v0.5.0) | 2026-10-04 | `_agent_audit` audits staged Python files (test shrinkage, syntax, dangerous calls with `# agent-audit: allow` markers); `# agent-audit: remote-sudo` marker; session-check contract documented |
| [v0.4.18](https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.18) | 2026-09-24 | `ACG_SESSION_OK path=` marker and `K3DM_ACG_REQUIRE_CREDENTIALS=1` fail-closed gate; headless login selector fixes; package renamed `lib-foundation-acg`; brace-expansion / js-yaml audit fixes |
| [v0.4.17](https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.17) | 2026-09-12 | Explicit signed-out detection and Prism monogram login signal; chrome-cdp launchd agent uses the managed Chromium and `pw-profile`; credential-test no longer restarts a sandbox over a broken CLI; sign-in wait no longer targets the dead `id.pluralsight.com` host |
| [v0.4.16](https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.16) | 2026-09-12 | `browserslist` family lockfile bump (GHSA-73wf-gq98-2v4g, GHSA-c83g-rgw3-j3cx) |
| [v0.4.15](https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.15) | 2026-09-05 | `_install_hermes_agent` / `_uninstall_hermes_agent` read-only launchd installer; 5 BATS |
| [v0.4.14](https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.14) | 2026-09-04 | ACG sandbox reveal/provision clicks use a dispatched MouseEvent (`_robustClick`) |
| [v0.4.13](https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.13) | 2026-08-21 | `foundation_ensure_vcluster_cli` — checksum-verified, per-version vCluster CLI install; 7 BATS |
| [v0.4.12](https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.12) | 2026-08-21 | Count-agnostic ACG agent fleet (`ACG_AGENT_COUNT`), numeric agent-IP discovery; `make shellcheck-lib` / `make bats` |
| [v0.4.11](https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.11) | 2026-08-20 | `js-yaml` 3.15.1 (CVE-2026-59870) |
| [v0.4.10](https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.10) | 2026-08-20 | ACG stale-route credential recovery; CDP listener reclaim on probe failure |
| [v0.4.9](https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.9) | 2026-08-14 | `_dry_run_active` / `_dry_guard` DRY_RUN primitives |
| [v0.4.8](https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.8) | 2026-07-25 | `brace-expansion` 1.1.16 (GHSA-3jxr-9vmj-r5cp) |
| [v0.4.7](https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.7) | 2026-07-23 | `acg_check_ttl` exit-code capture made `set -e`-safe |
| [v0.4.6](https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.6) | 2026-07-21 | `acg_restart` entrypoint restored; stale `playwright-artifacts-*` sweep |
| [v0.4.4](https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.4) | 2026-07-13 | ACG Extend sandbox-tab routing fix; `js-yaml` 3.15.0 |
| [v0.4.3](https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.3) | 2026-07-07 | Session-check render-timing race fix; parallel logged-in probes |
| [v0.4.2](https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.2) | 2026-07-06 | Headless CDP auto-login with stale-browser reclaim/reuse; managed Chromium for CDP |
| [v0.4.1](https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.1) | 2026-07-06 | Headless Pluralsight auto-login for unattended provisioning |
| [v0.4.0](https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.0) | 2026-06-22 | lib-acg absorbed as the optional `scripts/lib/acg/` module; `_ensure_agy_cli`; `_run_command_resolve_sudo` no-TTY `sudo -n` fallback |
| [v0.3.19](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.19) | 2026-05-03 | `_copilot_auth_check` token/apps.json/gh fallback chain; `_copilot_review` deny-tool pattern fix; 6 BATS |
| [v0.3.17](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.17) | 2026-05-01 | `_ai_agent_review` dispatch wrapper (`AI_REVIEW_FUNC`/`AI_REVIEW_MODEL`); `_copilot_review` rename; `K3DM_ENABLE_AI` gate removed from backend; `_agent_lint` glob expanded to `.sh`/`.js`/`.md`; 3 BATS |
| [v0.3.16](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.16) | 2026-04-05 | `_agent_audit` IP allowlist: `grep -Fqx -- "$file"` prevents dash-prefix paths from being parsed as grep flags; 2 BATS |
| [v0.3.15](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.15) | 2026-03-31 | `_agent_audit` IP allowlist — `AGENT_IP_ALLOWLIST` env var skips IP check for listed paths; 2 BATS |
| [v0.3.14](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.14) | 2026-03-27 | `agy` binary detection, `_antigravity_browser_ready` curl fast-fail, NUL-safe tab scan, doc + CHANGE.md fixes; 78 BATS |
| [v0.3.13](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.13) | 2026-03-25 | `_antigravity_browser_ready` curl probe fix — `_run_command --soft -- curl` replaces `_curl` to allow polling retries |
| [v0.3.12](https://github.com/wilddog64/lib-foundation/releases/tag/v0.3.12) | 2026-03-25 | `_ensure_antigravity_ide`, `_ensure_antigravity_mcp_playwright`, `_antigravity_browser_ready` — Antigravity IDE install + Playwright MCP config helpers; 7 BATS |
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
