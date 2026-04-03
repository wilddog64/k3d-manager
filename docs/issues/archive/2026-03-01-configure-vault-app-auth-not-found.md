# Issue: `configure_vault_app_auth` function not found in plugins

## Date
2026-03-01

## Environment
- Hostname: `m4-air.local`
- Branch: `feature/app-cluster-deploy` (HEAD: `68fabb2`)

## Symptoms
Attempting to run `./scripts/k3d-manager configure_vault_app_auth` fails with:
`Error: Function 'configure_vault_app_auth' not found in plugins`

Manual inspection of `scripts/plugins/vault.sh` confirms the function is missing.

## Root Cause
The Codex task to implement this function (assigned in `memory-bank/activeContext.md`) was either not picked up or not successfully committed/pushed to the branch.

## Status
Verification blocked. Gemini found the missing function during the initial mechanical check phase.

## Evidence
`grep "function configure_vault_app_auth" scripts/plugins/vault.sh` returned nothing.
