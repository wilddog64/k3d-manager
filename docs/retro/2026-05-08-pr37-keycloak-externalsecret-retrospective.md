# Retrospective — PR #37 Keycloak ExternalSecret Fix

**Date:** 2026-05-08
**Milestone:** Keycloak ExternalSecret missing files
**PR:** #37 — merged to main 2026-05-08 (this retrospective authored post-merge, included in PR #38)
**Participants:** Claude, Codex, Copilot

## What Went Well
- Missing ExternalSecret files created and wired correctly
- Coordinated with k3d-manager PR #73 for clean dual-repo fix

## What Went Wrong
- Files were missing from initial shopping-cart-infra Keycloak integration

## Process Rules Added
- None this milestone

## Decisions Made
- Static LDAP/Keycloak vars moved to configmap rather than multiplying ESO secrets

## Theme
Correctness fix for the Keycloak ExternalSecret integration. The missing source files were causing silent failures; this PR restores the intended ESO→Vault→Keycloak wiring.
