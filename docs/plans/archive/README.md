# Archived Specs — k3d-manager

Specs from shipped releases. Full history via `git log --follow docs/plans/archive/`.

| Version | Merge SHA | Key Changes |
|---------|-----------|-------------|
| v1.0.2 | `1e6d35d` | `make up` 12-step automation, ESO, ArgoCD, vault-bridge, Playwright CDP fixes |
| v1.0.1 | `a8b6c58` | Multi-node k3s-aws, CloudFormation parallel provisioning, Playwright hardening |
| v1.0.0 | `807c043` | k3s-aws provider foundation, single-node deploy/destroy, SSH config auto-update |
| v0.9.21 | `f98f2a8` | `_ensure_k3sup` + `deploy_app_cluster` auto-install |
| v0.9.20 | `bfd66fe` | Chrome launch fix, `acg_credentials.js` SPA nav guard |
| v0.9.19 | `0f13be1` | `acg_get_credentials` + `acg_import_credentials` — AWS credential extraction |
| v0.9.18 | `7567a5c` | ACG plugin: `acg_provision`, `acg_extend`, CloudFormation |
| v0.9.17 | `c88ca7a` | Tunnel reverse Vault port, autossh launchd |
| v0.9.16 | `484354da` | Antigravity plugin rewrite, Copilot agent validation |
| v0.9.15 | `484354da` | ldap-password-rotator stdin hardening, `_ensure_copilot_cli` |
| v0.9.14 | `d317429b` | if-count allowlist cleared, `_ensure_node` via lib-foundation |
| v0.9.13 | `c54fbe6` | CHANGE.md backfill, mergeable_state process check |
| v0.9.12 | `f8014bc` | Copilot CLI CI integration, lib-foundation v0.3.6 subtree |
