# Copilot PR #93 Review Findings

**PR:** #93 — feat(webhook): Slack Events API thread commands, Prometheus auth, ACG screenshot archival
**Date:** 2026-06-10
**Fix commit:** 6c814019

## Findings

### 1. CodeQL: clear-text storage of sensitive information — `bin/k3dm-webhook:204`
Local variable `secret` held an ArgoCD secret name (not a secret value) but CodeQL tainted it because of the variable name. Renamed to `secret_ref`.

### 2. Prometheus bootstrap hardcodes `admin:password` — `scripts/plugins/observability.sh:200`
Bootstrap path only stored `password_bcrypt` in Vault, making `show-service-passwords` and future rotation inconsistent. Fixed: store `password` plaintext field alongside `password_bcrypt`; read from `PROM_ADMIN_PASSWORD` env (default: `password`).

### 3. `show-service-passwords` prints literal "password" — `Makefile:321`
After rotation, the output would be wrong. Fixed: read `password` field from Vault secret, fall back to `N/A`.

### 4–5. Thread-reply docs inconsistency — `docs/howto/slack-slash-commands.md:296,300`
Examples showed `/claude`/`/gemini` for thread replies but the doc said to use bare names. Fixed: examples and paragraph now consistently describe bare names for threads, slash commands for main channel.

## Process note
Variable naming that matches secret-sounding words (`secret`, `token`, `password`) will taint CodeQL data-flow analysis even when the value is not actually sensitive. Use non-generic names (`secret_ref`, `token_name`) for non-sensitive references.
