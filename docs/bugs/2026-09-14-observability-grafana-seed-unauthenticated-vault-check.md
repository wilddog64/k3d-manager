# Bug: `make observability` checks Vault for the Grafana credential without logging in

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-14
**Status:** FIXED (Claude; BATS 19/19)
**Files:** `scripts/plugins/observability.sh`, `scripts/tests/plugins/observability_grafana_seed.bats`, `CHANGELOG.md`

## Problem

Live run on 2026-09-14 (`make observability` on the hub, Vault `secrets/vault-0` unsealed and active):

```
INFO: [observability] Grafana admin credential ExternalSecret applied
ERROR: [observability] failed to seed Grafana admin credential in Vault
make: *** [observability] Error 1
```

Call order in `deploy_observability`:

1. `_observability_apply_grafana_rotator`
2. which calls `_observability_seed_grafana_if_absent "secrets" "vault"` **first**
3. and only afterwards `_vault_configure_secret_writer_role`, the first caller of `_vault_login`.

With no session token in `_VAULT_SESSION_TOKENS`, `_vault_exec` runs `vault kv get` with no `VAULT_TOKEN`:

- The permission-denied failure is read as "credential absent".
- The seed then tries `vault kv put` with a **fresh random password**. That also fails unauthenticated, so nothing is overwritten today.
- The `|| _err` in `_observability_apply_grafana_rotator` aborts the whole deploy. The PrometheusRules, Istio VirtualServices, alertmanager secret and ApplicationSet steps never run.

This is a latent overwrite hazard. In any shell where the `vault` CLI has ambient credentials but the read fails for a different reason, the seed would replace the live Grafana admin password. `observability_seed_grafana` (the public entry point) already calls `_vault_login` first; only the deploy path is missing it.

The live `monitoring/grafana-admin-credentials` ExternalSecret is `SecretSynced` / `Ready=True`, so the credential exists in Vault.

## Fix

### S1 — `scripts/plugins/observability.sh`: log in before the seed

Old:

```bash
function _observability_apply_grafana_rotator() {
  _observability_seed_grafana_if_absent "secrets" "vault" \
    || _err "[observability] Grafana credential seed skipped/failed"
```

New:

```bash
function _observability_apply_grafana_rotator() {
  _vault_login "secrets" "vault"
  _observability_seed_grafana_if_absent "secrets" "vault" \
    || _err "[observability] Grafana credential seed skipped/failed"
```

### S2 — tests: append to `scripts/tests/plugins/observability_grafana_seed.bats`

- Stub `_vault_login`, `_observability_seed_grafana_if_absent`, `_kubectl` and `_vault_configure_secret_writer_role` to append to a call log.
- Run `_observability_apply_grafana_rotator`.
- Assert line 1 is `login secrets vault` and line 2 is `seed secrets vault`.

## CHANGELOG

Under `## [Unreleased]` → `### Fixed`, as the last bullet:

```
- `make observability` logs in to the hub Vault before checking for the Grafana admin credential; the unauthenticated check read as "absent", attempted to seed a fresh password, and aborted the deploy with `failed to seed Grafana admin credential in Vault`
```

## Definition of Done

- [ ] S1–S2 applied.
- [ ] `bats scripts/tests/plugins/observability_grafana_seed.bats scripts/tests/lib/observability.bats` all pass.
- [ ] `shellcheck -x scripts/plugins/observability.sh`: no new warnings.
- [ ] Live: `make observability` completes; Grafana admin credential unchanged (ExternalSecret still `SecretSynced`, no "Seeded" log line).

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`.
- Do NOT change `_vault_login`, `_vault_exec`, or the seed's `kv put` command.
- Do NOT edit `scripts/lib/foundation/`, `scripts/lib/acg/`, or `scripts/lib/system.sh`.
