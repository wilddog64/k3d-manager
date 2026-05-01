# Issue: `gh auth token` returns insufficient scope for GHCR pulls

**Date:** 2026-04-29
**Severity:** High — causes `ImagePullBackOff` even after PAT rotation
**Status:** Resolved (via Vault-first strategy)
**Assignee:** Gemini CLI

## Symptom
After running `bin/rotate-ghcr-pat` or `bin/acg-up`, shopping-cart pods remain in `ImagePullBackOff`.
Inspecting the `ghcr-pull-secret` reveals a token starting with `gho_` (e.g., `gho_UxrC...`).

## Root Cause
When a user logs into the GitHub CLI via the browser (default), the `gh auth token` returns an **OAuth token** (starting with `gho_`). These tokens are designed for CLI-to-GitHub interactions and **do not include the `read:packages` scope** required for Kubernetes `docker-registry` secrets to pull from `ghcr.io`.

The previous "fix" in `bin/acg-up` relied on `gh auth token` as a fallback, which inadvertently injected the scoped-down OAuth token into the cluster.

## Resolution
Implemented a **Vault-First** strategy in `bin/acg-up` and `bin/rotate-ghcr-pat`:
1. The scripts now check for a PAT at `secret/data/github/pat` in the local Vault.
2. If found, this PAT (which should be a `ghp_` token provided by the user) is used as the primary source of truth.
3. The `gh auth token` is now the *last* resort fallback and generates a warning.

## Verification
1. Seed Vault: `curl -X POST -H "X-Vault-Token: $VTOKEN" -d '{"data": {"token": "ghp_..."}}' http://localhost:18200/v1/secret/data/github/pat`
2. Run `acg-up` or `rotate-ghcr-pat`.
3. Secret in cluster now contains the `ghp_` token.
4. Pods successfully pull images and transition to `Running`.

## Lessons Learned
Never trust `gh auth token` for cross-system authentication (like K8s pull secrets) if the user typically uses the browser-based OAuth login flow. Always prefer a dedicated PAT.
