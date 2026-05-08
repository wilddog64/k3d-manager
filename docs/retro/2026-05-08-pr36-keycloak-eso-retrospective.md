# Retrospective — PR #36: Keycloak frontend OIDC client + ESO migration

**Date:** 2026-05-08
**PR:** #36 — already merged to main at `060e388320e9335167390c76825874f34dbebb0f` (retro doc added in PR #37)
**Participants:** Claude, Gemini, Copilot

## What Went Well
- Gemini correctly generated real SSHA hashes for all 3 LDAP sample users (Admin@Cart2024, Dev@Cart2024, Ops@Cart2024) — verified cryptographically
- All 7 Copilot findings were substantive and caught real issues (missing ESO labels, wrong Vault path for LDAP_BIND_CREDENTIAL, security risk with directAccessGrantsEnabled, missing sync-wave ordering)
- CI green on first pass (YAML lint, Kubeconform, Kustomize build, GitGuardian)

## What Went Wrong
- PR description omitted the planning/retro docs that were bundled in the k3d-manager PR — Copilot flagged it; always list all additions in the PR body
- keycloak-secrets ESO initially sourced LDAP_BIND_CREDENTIAL from keycloak/admin (duplicate) instead of ldap/admin (canonical source) — drift risk caught by Copilot
- All three ESO target templates were missing type: Opaque and metadata.labels — missed from Gemini's implementation

## Process Rules Added
| Rule | File |
|------|------|
| ESO target.template must include type: Opaque + metadata.labels | spec boilerplate |
| Deployments consuming ESO-managed Secrets must have sync-wave: "1" | ESO migration checklist |
| Public SPA clients must have directAccessGrantsEnabled: false | Keycloak client checklist |
| Source shared credentials from canonical Vault path — no duplication | ESO design rules |

## Decisions Made
- LDAP_BIND_CREDENTIAL now sourced directly from secret/data/ldap/admin in keycloak-secrets ESO — single source of truth, rotation-safe
- keycloak-client-secrets ESO added as a separate resource (not in original spec) — correct separation of admin vs per-client secrets

## Theme
The Keycloak identity layer migrated from static Kubernetes Secrets to Vault-backed ESO, added a frontend public OIDC client for SPA login, and seeded the Vault KV paths from acg-up provisioning. Gemini executed the implementation correctly but missed three ESO boilerplate conventions (labels, type, sync-wave) that Copilot caught. The LDAP_BIND_CREDENTIAL design was improved from a duplicate-and-drift approach to single-source-of-truth.
