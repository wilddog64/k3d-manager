# Copilot PR #126 review findings

**PR:** #126 (`k3d-manager-v1.33.0` → `main`)
**Date:** 2026-09-13

## F1: Kine stale-registration signature could never match (review summary)

**Where:** `bin/k3dm-hermes` `_datastore_run`

**What Copilot flagged:** the check ran `"host.k3d.internal" in json.dumps(item)` over ArgoCD cluster Secrets. Kubernetes returns Secret `data` base64-encoded, so the server URL never appears as plain text. `stale_acg_registration` was therefore always `False`, and the opt-in R5 Kine circuit breaker could never fire.

**Fix:** added `scripts/lib/hermes/sensors.py` `stale_acg_registration(items)`. It base64-decodes each `data` value, skipping invalid values, and also matches `stringData` and metadata as plain text. `_datastore_run` now calls it. The new test `test_stale_acg_registration_decodes_base64_secret_data` asserts that the raw JSON does *not* contain the marker, while the helper still detects it.

**Root cause:** the unit tests only injected an already-computed `stale_acg_registration` boolean. Nothing exercised the Secret → boolean step against real Secret encoding.

**Process note:** when a spec's signal comes from Kubernetes Secrets, the tests must use a base64-encoded `data` fixture, not a precomputed flag.

## F2: `_vault_role_merged_policies` interpolated `role_path` unquoted (`scripts/plugins/vault.sh`)

**What Copilot flagged:** `role_path` went into a command string that `_vault_exec` runs through `sh -lc`, so whitespace or metacharacters could split the command or be interpreted by the shell.

**Fix:**

```bash
printf -v safe_role_path '%q' "$role_path"
role_json=$(_vault_exec --no-exit "$ns" "vault read -format=json ${safe_role_path}" "$release" 2>/dev/null || true)
```

This is the same `%q` idiom the neighbouring role writers already use. The new BATS test `shell-escapes the role path` fails against the pre-fix file and passes after the fix.

**Root cause:** the helper was new in this release, and its spec's code block omitted the `%q` step that the other `_vault_exec` callers use.

**Process note:** specs that build a `_vault_exec` command string must show `printf -v safe_x '%q'` for every interpolated value.

## F3: duplicate `### Added` / `### Fixed` headings under `[Unreleased]` (`CHANGELOG.md`)

**What Copilot flagged:** the Kine circuit breaker and Loki entries each added a second `### Added` / `### Fixed` block.

**Fix:** merged them into a single `### Added` and a single `### Fixed`. No bullets were dropped.

**Root cause:** a later commit appended new heading blocks instead of adding its bullets to the existing sections.

**Process note:** CHANGELOG instructions in specs must say "add to the existing `### <Type>` under `[Unreleased]`".
