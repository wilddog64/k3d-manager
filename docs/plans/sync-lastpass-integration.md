## Goal
Integrate the existing LastPass AD sync helper with the `deploy_jenkins` workflow so operators get fresh AD credentials by default while keeping an opt-out flag for environments without LastPass access. Scope is limited to wiring the script into the CLI; no additional bootstrap or deployment refactors are planned.

## Proposed Steps
1. Confirm current `bin/sync-lastpass-ad.sh` contract (inputs, outputs, exit codes) so the wrapper behaves transparently.
2. Re-implement the script logic as a private helper `_sync_lastpass_ad` inside `scripts/lib/system.sh`, avoiding any shell-out while leaving `bin/sync-lastpass-ad.sh` untouched for direct/manual use.
3. Teach the `deploy_jenkins` plugin to accept `--sync-from-lastpass` (default) / `--no-sync-from-lastpass`, invoking `_sync_lastpass_ad` ahead of Vault work when enabled. No other deploy flags (such as `--force-bootstrap`) will be touched.
4. Update help text (CLI usage and README) so operators understand the new default/opt-out behaviour.
5. Backfill targeted BATS coverage that stubs the wrapper to validate the call path for both enabled and disabled modes.

## Open Questions / Assumptions
- The standalone script in `bin/` remains untouched for compatibility; the new helper mirrors its behaviour inline.
- Tests can rely on existing stubbing helpers without needing real LastPass access.
- No changes will be made to other deployment helpers (e.g. `--force-bootstrap`) in this pass.
- Additional documentation beyond help text (e.g. README) may be warranted if operators expect guidance on the new default behaviour.
