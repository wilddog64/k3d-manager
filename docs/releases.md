# Release History — k3d-manager

| Version | Date | Highlights |
|---|---|---|
| [v1.0.1](https://github.com/wilddog64/k3d-manager/releases/tag/v1.0.1) | 2026-03-31 | multi-node k3s-aws + CloudFormation + Playwright hardening — 3-node CF stack; auto sign-in; remove Antigravity pre-calls from `acg_get_credentials`; `AGENT_IP_ALLOWLIST` in pre-commit hook |
| [v1.0.0](https://github.com/wilddog64/k3d-manager/releases/tag/v1.0.0) | 2026-03-29 | k3s-aws provider foundation — `CLUSTER_PROVIDER=k3s-aws` end-to-end deploy; `aws_import_credentials`; `acg_provision --recreate`; `acg_watch` background TTL watcher; keypair idempotency + `page.goto()` fix |
| [v0.9.21](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.21) | 2026-03-29 | `_ensure_k3sup` auto-install helper — `deploy_app_cluster` now auto-installs k3sup via brew or curl; consistent with `_ensure_node`/`_ensure_copilot_cli` pattern |
| [v0.9.20](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.20) | 2026-03-29 | ACG Chrome launch fix — `_antigravity_launch` now opens Chrome (not Antigravity IDE) with `--password-store=basic`; `acg_credentials.js` SPA nav guard avoids hard reload |
| [v0.9.19](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.19) | 2026-03-28 | ACG automated credential extraction — `acg_get_credentials` (Playwright CDP auto-start), `acg_import_credentials` (stdin fallback), static `acg_credentials.js`; live-verified |
| [v0.9.18](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.18) | 2026-03-28 | Pluralsight URL migration — `_ACG_SANDBOX_URL` + `_antigravity_ensure_acg_session` updated to `app.pluralsight.com` |
| [v0.9.17](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.17) | 2026-03-27 | Antigravity model fallback (`gemini-2.5-flash` first), ACG session check, nested agent fix (`--approval-mode yolo` + workspace temp path) |
| [v0.9.16](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.16) | 2026-03-26 | Antigravity IDE + CDP browser automation — gemini CLI + Playwright engine; `antigravity_install`, `antigravity_trigger_copilot_review`, `antigravity_acg_extend`; ldap stdin hardening |
| [v0.9.13](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.13) | 2026-03-23 | v0.9.12 retro, `/create-pr` `mergeable_state` check, CHANGE.md backfill for v0.9.12 |
| [v0.9.11](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.11) | 2026-03-22 | dynamic plugin CI — `detect` job skips cluster tests for docs-only PRs; maps plugin changes to targeted smoke tests |
| [v0.9.10](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.10) | 2026-03-22 | if-count allowlist elimination (jenkins) — 8 helpers extracted; allowlist now `system.sh` only |
| [v0.9.9](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.9) | 2026-03-22 | if-count allowlist elimination — 11 ldap helpers + 6 vault helpers extracted; allowlist down to `system.sh` only |
| [v0.9.7](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.7) | 2026-03-22 | lib-foundation sync (`--interactive-sudo`, `_run_command_resolve_sudo`), `deploy_cluster` no-args guard, `bin/` `_kubectl` wrapper, BATS stub fixes, Copilot PR #41 findings |
| [v0.9.6](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.6) | 2026-03-22 | ACG sandbox plugin (`acg_provision/status/extend/teardown`), VPC/SG idempotency, `ACG_ALLOWED_CIDR` security, kops-for-k3s reframe |
| [v0.9.5](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.5) | 2026-03-21 | `deploy_app_cluster` — EC2 k3sup install + kubeconfig merge + ArgoCD registration; replaces manual rebuild |
| [v0.9.4](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.4) | 2026-03-21 | autossh tunnel plugin, ArgoCD cluster registration, smoke-test gate, `_run_command` TTY fallback, lib-foundation v0.3.3 |
| [v0.9.3](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.3) | 2026-03-16 | TTY fix (`_DCRS_PROVIDER` global), lib-foundation v0.3.2 subtree, cluster rebuild smoke test |
| [v0.9.2](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.2) | 2026-03-15 | vCluster E2E composite actions, 11-finding Copilot hardening (curl safety, mktemp, sudo -n, input validation) |
| [v0.9.1](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.1) | 2026-03-15 | vCluster plugin (`create/destroy/use/list`), two-tier `--help`, `function test()` refactor, 11 Copilot findings fixed |
| [v0.9.0](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.0) | 2026-03-15 | k3dm-mcp planning, agent workflow lessons, roadmap restructure |
| [v0.8.0](https://github.com/wilddog64/k3d-manager/releases/tag/v0.8.0) | 2026-03-13 | Vault-managed ArgoCD deploy keys, `deploy_cert_manager` (ACME/Let's Encrypt), Istio IngressClass, `install-hooks.sh` |
| [v0.7.3](https://github.com/wilddog64/k3d-manager/releases/tag/v0.7.3) | 2026-03-11 | `shopping_cart.sh` plugin, reusable GitHub Actions CI/CD workflow, ArgoCD ubuntu-k3s, infra rebuilt on M2 Air |
| [v0.7.2](https://github.com/wilddog64/k3d-manager/releases/tag/v0.7.2) | 2026-03-08 | dotfiles/hooks integration, lib-foundation v0.2.0, Ubuntu ESO + shopping-cart-data |
| [v0.7.0](https://github.com/wilddog64/k3d-manager/releases/tag/v0.7.0) | 2026-03-07 | lib-foundation subtree, `deploy_cluster` refactored 12→5 if-blocks |
| [v0.6.5](https://github.com/wilddog64/k3d-manager/releases/tag/v0.6.5) | 2026-03-07 | Agent Rigor BATS coverage, lib-foundation extracted |
| [v0.6.4](https://github.com/wilddog64/k3d-manager/releases/tag/v0.6.4) | 2026-03-07 | Linux k3s validation, `_agent_audit`, provider contract BATS (30 tests) |
| [v0.6.3](https://github.com/wilddog64/k3d-manager/releases/tag/v0.6.3) | 2026-03-06 | `_agent_lint` + `_agent_audit`, permission cascade refactor |
| [v0.6.2](https://github.com/wilddog64/k3d-manager/releases/tag/v0.6.2) | 2026-03-06 | Agent Rigor Protocol, `_k3d_manager_copilot` wrapper, PATH hardening |
| [v0.1.0](https://github.com/wilddog64/k3d-manager/releases/tag/v0.1.0) | 2026-02-27 | Initial release — k3d/k3s/OrbStack providers, Vault PKI, Jenkins, ESO, LDAP/AD |
