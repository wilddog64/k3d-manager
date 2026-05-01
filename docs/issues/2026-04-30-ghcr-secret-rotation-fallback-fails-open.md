# Issue: GHCR secret rotation could recreate an invalid `ghcr-pull-secret`

**Date:** 2026-04-30
**Severity:** High — can reintroduce `ImagePullBackOff` after a seemingly successful rotation
**Status:** Fixed
**Assignee:** Codex

## Symptom
Shopping-cart pods intermittently returned to `ImagePullBackOff` with `403 Forbidden` from `ghcr.io` even after the GHCR token had been rotated.

## Root Cause
`bin/acg-up` still allowed a fallback to `gh auth token` whenever `GHCR_PAT` was unset and Vault had no PAT stored. In a normal browser-based `gh auth login` flow, that token is an OAuth token (`gho_...`) and may not have `read:packages`.

The rotation helper also only persisted a PAT to Vault in the interactive TTY branch. Piped usage could update repo secrets without updating Vault, which made the next `acg-up` run vulnerable to falling back to `gh auth token` again.

## Fix
1. `bin/acg-up` now fails closed if `GHCR_PAT` is missing and Vault does not contain `secret/data/github/pat`.
2. `bin/rotate-ghcr-pat` now writes the token to Vault after reading it from either the interactive prompt or stdin.

## Result
The cluster secret source is now forced to come from a real PAT path instead of silently recreating a scoped-down OAuth token.
