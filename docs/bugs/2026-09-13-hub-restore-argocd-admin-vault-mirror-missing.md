# Bug: after a hub restore, Vault has no ArgoCD admin password (`make show-service-passwords` shows N/A)

**Filed:** 2026-09-13
**Branch:** `k3d-manager-v1.33.0`
**Status:** DONE `b231fb51`

---

## Problem

After the 2026-09-13 hub restore and `hub_recovery_reconcile --confirm`, `make show-service-passwords` prints `password: N/A` for ArgoCD. The Makefile target reads `secret/data/argocd/admin` field `password` from Vault via `127.0.0.1:18200`.

Observed on hub `k3d-k3d-cluster`:

- The Vault port-forward on `:18200` is listening and `/v1/sys/health` returns 200, so this is not the port-forward cause in `reference_show_service_passwords_na_root_causes`.
- `cicd/argocd-initial-admin-secret` and `cicd/argocd-secret` exist. There is no `argocd-admin-secret` ExternalSecret on the hub.
- `cicd/argocd-credential-rotator` (monthly) has never run on the restored hub, and it is the only writer of `secret/argocd/admin`. Its first step reads the old password from that path with `jq -e`, so its first run would also fail.

Nothing in `hub_recovery_reconcile` recreates that path. `_argocd_seed_vault_admin_secret` (`scripts/plugins/argocd.sh:575`) is not a fix: it writes a **new random** password, which ArgoCD would not accept.

## Fix

Add a reconcile step that mirrors the **real** ArgoCD admin password into Vault. It runs only when the Vault entry lacks a `password` field, and only writes a password that ArgoCD has just accepted.

### Before You Start

- `git pull origin k3d-manager-v1.33.0`; read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
- Read in full `scripts/plugins/hub_recovery.sh`, especially `_hub_recovery_seed_app_cluster_reader` (the root-token-over-stdin `vault kv put -` idiom to copy) and `hub_recovery_reconcile`.
- Read `scripts/tests/plugins/hub_recovery.bats` (stub idiom and the dry-run test that loops `{1..8}`).

### H1 — new function in `scripts/plugins/hub_recovery.sh` (place it after `_hub_recovery_replay_identity_hook`)

```bash
function _hub_recovery_mirror_argocd_admin() {
  local hub_context="$1" root_token password payload_file argocd_url="${HUB_RECOVERY_ARGOCD_URL:-https://argocd.3ai-talk.org}" code
  root_token=$(_kubectl -- --context "$hub_context" -n secrets get secret vault-root -o jsonpath='{.data.root_token}' 2>/dev/null | base64 --decode 2>/dev/null || true)
  [[ -n "$root_token" ]] || { _err "[hub-recovery] Vault root token unavailable for ArgoCD admin mirror"; return 1; }
  if printf '%s\n' "$root_token" | _no_trace _kubectl -- --context "$hub_context" -n secrets exec -i vault-0 -- sh -c 'read -r VAULT_TOKEN; export VAULT_TOKEN; vault kv get -mount=secret -field=password argocd/admin >/dev/null 2>&1'; then
    return 0
  fi
  password=$(_kubectl -- --context "$hub_context" -n cicd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode 2>/dev/null || true)
  if [[ -z "$password" ]]; then
    _warn "[hub-recovery] argocd-initial-admin-secret unavailable; cannot mirror ArgoCD admin password into Vault"
    return 0
  fi
  payload_file=$(mktemp)
  trap 'trap - RETURN; rm -f "'"${payload_file}"'" 2>/dev/null || true' RETURN
  jq -n --arg username admin --arg password "$password" '{username:$username,password:$password}' > "$payload_file"
  code=$(curl -s -o /dev/null -w '%{http_code}' -H 'User-Agent: k3dm-hub-recovery/1' -H 'Content-Type: application/json' --data @"$payload_file" "${argocd_url}/api/v1/session" || true)
  if [[ "$code" != "200" ]]; then
    _warn "[hub-recovery] argocd-initial-admin-secret password rejected by ArgoCD (HTTP ${code:-000}); not mirroring into Vault"
    return 0
  fi
  { printf '%s\n' "$root_token"; cat "$payload_file"; } | _no_trace _kubectl -- --context "$hub_context" -n secrets exec -i vault-0 -- sh -c 'read -r VAULT_TOKEN; export VAULT_TOKEN; vault kv put -mount=secret argocd/admin -' >/dev/null || return 1
  _info "[hub-recovery] ArgoCD admin password mirrored into Vault secret/argocd/admin"
}
```

### H2 — `hub_recovery_reconcile`

- In `steps=(...)`, insert `"ArgoCD admin Vault mirror"` between `"Smoke user"` and `"Cloudflare origins"`, making 9 steps.
- In the confirm path, insert `_hub_recovery_mirror_argocd_admin "$hub_context" || return 1` between the `keycloak_seed_smoke_user` line and `_hub_recovery_install_cloudflared_config`.

### Tests — `scripts/tests/plugins/hub_recovery.bats`

- Dry-run test: loop `{1..9}` instead of `{1..8}`, and assert the output contains `ArgoCD admin Vault mirror`.
- New tests for `_hub_recovery_mirror_argocd_admin`, stubbing `_kubectl`, `curl`, `_no_trace` (pass-through), `_info`, `_warn` and `_err`. Record calls to a file; never use real credentials.
  1. Vault already has the password (the `kv get` stub exits 0): no `curl` call, no `kv put`, rc 0.
  2. Vault missing, initial secret present, `curl` prints `200`: `kv put` is called and the stdin it receives contains `"username": "admin"`; rc 0.
  3. Vault missing, `curl` prints `401`: no `kv put`, rc 0.
  4. Vault missing, initial secret empty: no `curl`, no `kv put`, rc 0.
  5. Root token empty: rc 1.
- Assert on meaningful tokens (`kv put`, `argocd/admin`, `username`), not whole source lines. Assert that the recorded call log never contains the stub password value.

## Definition of Done

- [ ] H1 and H2 implemented exactly; only `scripts/plugins/hub_recovery.sh`, `scripts/tests/plugins/hub_recovery.bats` and `CHANGELOG.md` changed
- [ ] `shellcheck -x scripts/plugins/hub_recovery.sh` — rc 0
- [ ] `bats scripts/tests/plugins/hub_recovery.bats scripts/tests/plugins/keycloak_return_trap.bats` green — paste the summary
- [ ] CHANGELOG `## [Unreleased]` → `### Fixed`: "`hub_recovery_reconcile` mirrors the verified ArgoCD admin password into Vault `secret/argocd/admin` when missing (`make show-service-passwords` ArgoCD N/A after hub restore)"
- [ ] Commit message verbatim: `fix(hub-recovery): mirror verified ArgoCD admin password into Vault after restore`
- [ ] Pushed to `origin/k3d-manager-v1.33.0`; report the SHA

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`
- Do NOT call `_argocd_seed_vault_admin_secret` or generate a new password
- Do NOT put the password or root token in argv, logs, `_info` output, or test output
- Do NOT modify `scripts/lib/foundation/`, `scripts/lib/acg/`, `scripts/lib/system.sh`, `scripts/plugins/argocd.sh`, the Makefile, or any file outside the targets
- Do NOT run anything against a live cluster, Vault, or ArgoCD
