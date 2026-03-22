# if-count Allowlist — Deferred Refactors

**Date:** 2026-03-22
**Branch:** k3d-manager-v0.9.8 (easy wins done)

## Context

18 functions remain in `scripts/etc/agent/if-count-allowlist` after v0.9.8 easy wins.
These require architectural decomposition (extract sub-functions), not a line edit.
Blocked from removing without functional risk:

## Deferred Functions

### jenkins.sh (4 remaining)
| Function | if-count | Notes |
|---|---|---|
| `_jenkins_run_saved_trap_literal` | 11 | Complex trap chain — extract token-dedup logic |
| `_jenkins_run_smoke_test` | 15 | Long verification chain — split into stages |
| `_deploy_jenkins` | 21 | Main deploy body — needs stage helper pattern |
| `deploy_jenkins` | 24 | Outer orchestrator — extract option-parsing block |

### ldap.sh (7 remaining)
| Function | if-count | Notes |
|---|---|---|
| `_ldap_seed_admin_secret` | 11 | Secret bootstrapping — extract validation block |
| `_ldap_seed_ldif_secret` | 11 | Similar pattern to admin_secret |
| `_ldap_deploy_chart` | 17 | Helm deploy + wait chain |
| `_ldap_import_ldif` | 12 | LDIF import + retry logic |
| `_ldap_sync_admin_password` | 14 | Password rotation chain |
| `deploy_ldap` | 38 | Largest function in codebase — needs stage decomposition |
| `deploy_ad` | 15 | AD variant of deploy_ldap |

### vault.sh (5 remaining)
| Function | if-count | Notes |
|---|---|---|
| `_vault_replay_cached_unseal` | 18 | Unseal retry logic |
| `_vault_bootstrap_ha` | 14 | HA cluster init |
| `_vault_configure_secret_reader_role` | 12 | Policy + role setup |
| `_vault_seed_ldap_service_accounts` | 11 | Service account bootstrapping |
| `deploy_vault` | 19 | Main vault deploy |

### system.sh (2 blocked)
| Function | if-count | Notes |
|---|---|---|
| `_run_command` | 9 | Subtree-managed — fix must go to lib-foundation `feat/v0.3.4` first |
| `_ensure_node` | 9 | Subtree-managed — same constraint |

## Next Steps

- Target `deploy_ldap` first for v0.9.9 (largest; most impact)
- Use stage-helper pattern: `_ldap_deploy_stage_<name>()` extracted from main body
- system.sh pair: PR to lib-foundation, then subtree pull
