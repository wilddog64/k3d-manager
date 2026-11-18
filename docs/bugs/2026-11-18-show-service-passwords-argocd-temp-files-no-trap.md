# Bug: `show-service-passwords` can leave the Vault root token and ArgoCD password in temp files

**Status:** OPEN — captured 2026-11-18
**Priority:** P2 (plaintext credential left in `$TMPDIR` only when one of three blocks is interrupted or fails mid-way; must be fixed before the travel-bundle LaunchAgent runs the target every 15 minutes)
**Introduced by:** v1.43.5 (`401e4eca`, squash merge #148)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-18
**Prior art:** `docs/bugs/2026-09-21-show-service-passwords-keycloak-block-defeats-redaction.md` (slug match, no score; `find-similar-docs` not run: the vector store is on the hub) — read, different root cause
**Found by:** Luna (Codex), stopping the `v1.45.0-service-password-travel-bundle` dispatch on 2026-11-18 because its spec forbade plaintext in `TMPDIR`.

## Symptom

`make show-service-passwords` (`Makefile:1038`) has two shell blocks. The first creates `_vault_hdr` with `mktemp`
and removes it with `trap 'rm -f "$$_vault_hdr"' EXIT`. The second block (`Makefile:1056-1076`) creates four more
`mktemp` files: `_vault_hdr` (the Vault root token as an `X-Vault-Token:` header), `_argocd_vault_file` and
`_argocd_initial_file` (ArgoCD admin password candidates in plaintext) and `_argocd_payload` (a JSON login body that
holds the password). It removes them with a plain `rm -f` (`:1076`), with no `trap`. The next two blocks do the same with the Vault
root token alone: `_vault_hdr` created at `:1084` and `:1095`, removed by a plain `rm -f` at `:1088` and `:1100`.

If one of those blocks is interrupted (Ctrl-C, a killed LaunchAgent, a timeout) before the `rm -f` line, the files stay in
`$TMPDIR`, readable by the operator account, until macOS cleans the temp directory.

## Why it matters now

Today the target only runs when the operator types it. The travel-bundle plan (`docs/plans/v1.45.0-service-password-travel-bundle.md`,
B3/B4) runs it from a LaunchAgent every 15 minutes, about 96 times a day, so an interrupted run becomes far more likely.

## Fix direction (not yet specced)

Smallest: a `trap 'rm -f …' EXIT` in each of the three blocks, like the first block's. Better: keep the token and
passwords in memory (`curl -H @-` from stdin, `jq --arg` instead of `--rawfile`) so nothing reaches disk. The output
of the target must not change.

## Workaround

None needed for manual runs beyond not interrupting them; do not run `make password-bundle-install` until this is fixed.
